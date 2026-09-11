#!/usr/bin/env python3
"""Stream and characterize the full UZH shapes_rotation event file."""

from __future__ import annotations

import argparse
from collections import Counter
from collections import deque
import hashlib
import json
from pathlib import Path
import sys


EXPECTED_SHA256 = "d0b66503613354d1d274c56c979dfd89ba80b256c31eaba459a52adb7d03ffda"
SENSOR_WIDTH = 240
SENSOR_HEIGHT = 180
CLOCK_NS = 5
BIN_NS = 1_000_000
CENTRAL_X = range(110, 114)
CENTRAL_Y = range(85, 89)


def timestamp_to_ns(token: str) -> int:
    """Convert a decimal second token exactly; reject sub-nanosecond input."""
    whole, separator, fraction = token.partition(".")
    if (
        not whole.isdecimal()
        or (separator and not fraction.isdecimal())
        or len(fraction) > 9
    ):
        raise ValueError(f"timestamp is not a non-negative integer nanosecond: {token!r}")
    return int(whole) * 1_000_000_000 + int((fraction + "000000000")[:9])


def percentile(counter: Counter[int], numerator: int, denominator: int) -> int:
    """Return the nearest-rank percentile of a counted integer population."""
    population = sum(counter.values())
    if not population:
        raise ValueError("empty percentile population")
    rank = (numerator * population + denominator - 1) // denominator
    cumulative = 0
    for value, frequency in sorted(counter.items()):
        cumulative += frequency
        if cumulative >= rank:
            return value
    raise AssertionError("percentile rank escaped its population")


def histogram(counter: Counter[int]) -> list[list[int]]:
    return [
        [value, frequency]
        for value, frequency in sorted(counter.items())
        if frequency
    ]


class FiniteWaitingQueue:
    """Loss-only FIFO model; the in-service event is not in waiting_count."""

    def __init__(self, initiation_interval: int, depth: int) -> None:
        self.initiation_interval = initiation_interval
        self.depth = depth
        self.waiting_count = 0
        self.next_start_cycle: int | None = None
        self.lost_events = 0
        self.peak_waiting = 0

    def observe_batch(self, cycle: int, count: int) -> None:
        if self.next_start_cycle is not None and self.waiting_count:
            available = max(0, cycle - self.next_start_cycle)
            starts_before_arrival = (
                available + self.initiation_interval - 1
            ) // self.initiation_interval
            starts = min(self.waiting_count, starts_before_arrival)
            self.waiting_count -= starts
            self.next_start_cycle += starts * self.initiation_interval

        self.waiting_count += count
        if (
            self.waiting_count
            and (
                self.next_start_cycle is None
                or self.next_start_cycle <= cycle
            )
        ):
            self.waiting_count -= 1
            self.next_start_cycle = cycle + self.initiation_interval

        if self.waiting_count > self.depth:
            self.lost_events += self.waiting_count - self.depth
            self.waiting_count = self.depth
        self.peak_waiting = max(self.peak_waiting, self.waiting_count)


class SharedServerEnvelope:
    """Schedule infinite-FIFO starts and mirror finite waiting-depth loss."""

    def __init__(self, initiation_interval: int) -> None:
        self.initiation_interval = initiation_interval
        self.pending_starts: deque[int] = deque()
        self.next_start_cycle: int | None = None
        self.latencies: Counter[int] = Counter()
        self.post_dispatch_peak_waiting = 0
        self.cross_batch_overlap_batches = 0
        self.batch_count = 0
        self.finite = {
            depth: FiniteWaitingQueue(initiation_interval, depth)
            for depth in (8, 16, 32)
        }

    def observe_batch(self, cycle: int, count: int) -> None:
        while self.pending_starts and self.pending_starts[0] < cycle:
            self.pending_starts.popleft()
        if self.pending_starts or (
            self.next_start_cycle is not None
            and self.next_start_cycle > cycle
        ):
            self.cross_batch_overlap_batches += 1

        for _ in range(count):
            start = max(cycle, self.next_start_cycle or cycle)
            self.pending_starts.append(start)
            self.latencies[start - cycle] += 1
            self.next_start_cycle = start + self.initiation_interval
        while self.pending_starts and self.pending_starts[0] == cycle:
            self.pending_starts.popleft()
        self.post_dispatch_peak_waiting = max(
            self.post_dispatch_peak_waiting, len(self.pending_starts)
        )
        self.batch_count += 1
        for finite in self.finite.values():
            finite.observe_batch(cycle, count)

    def report(self, event_count: int) -> dict[str, object]:
        return {
            "initiation_interval_cycles": self.initiation_interval,
            "batch_count": self.batch_count,
            "cross_batch_overlap_batches": self.cross_batch_overlap_batches,
            "infinite_waiting_queue": {
                "post_dispatch_peak_waiting": self.post_dispatch_peak_waiting,
                "start_latency_cycles": {
                    "population": sum(self.latencies.values()),
                    "histogram": histogram(self.latencies),
                    "p99_nearest_rank": percentile(self.latencies, 99, 100),
                    "maximum": max(self.latencies),
                },
            },
            "finite_waiting_queues": [
                {
                    "depth": depth,
                    "accepted_events": event_count - finite.lost_events,
                    "lost_events": finite.lost_events,
                    "peak_waiting_after_loss": finite.peak_waiting,
                }
                for depth, finite in self.finite.items()
            ],
        }


class Partition:
    def __init__(self, side: int) -> None:
        self.side = side
        self.columns = (SENSOR_WIDTH + side - 1) // side
        self.rows = (SENSOR_HEIGHT + side - 1) // side
        self.totals = [0] * (self.columns * self.rows)
        self.cycle_counts: dict[int, int] = {}
        self.active_per_cycle: Counter[int] = Counter()
        self.events_per_active_partition_cycle: Counter[int] = Counter()

    def add(self, x: int, y: int) -> None:
        region = (y // self.side) * self.columns + x // self.side
        self.totals[region] += 1
        self.cycle_counts[region] = self.cycle_counts.get(region, 0) + 1

    def flush_cycle(self) -> None:
        if not self.cycle_counts:
            return
        self.active_per_cycle[len(self.cycle_counts)] += 1
        self.events_per_active_partition_cycle.update(self.cycle_counts.values())
        self.cycle_counts.clear()

    def report(self) -> dict[str, object]:
        totals = Counter(self.totals)
        active = sum(value != 0 for value in self.totals)
        active_cycle_population = sum(self.active_per_cycle.values())
        partition_cycle_population = sum(
            self.events_per_active_partition_cycle.values()
        )
        return {
            "side_pixels": self.side,
            "columns": self.columns,
            "rows": self.rows,
            "region_count": len(self.totals),
            "edge_region_width_pixels": SENSOR_WIDTH % self.side or self.side,
            "edge_region_height_pixels": SENSOR_HEIGHT % self.side or self.side,
            "active_partitions_per_active_global_cycle": {
                "population": active_cycle_population,
                "histogram": histogram(self.active_per_cycle),
                "maximum": max(self.active_per_cycle),
            },
            "events_per_active_partition_cycle": {
                "population": partition_cycle_population,
                "histogram": histogram(self.events_per_active_partition_cycle),
                "maximum": max(self.events_per_active_partition_cycle),
            },
            "total_events_per_region": {
                "population_including_zero_regions": len(self.totals),
                "active_regions": active,
                "sum": sum(self.totals),
                "minimum": min(self.totals),
                "p50_nearest_rank": percentile(totals, 50, 100),
                "p99_nearest_rank": percentile(totals, 99, 100),
                "maximum": max(self.totals),
                "histogram": histogram(totals),
            },
        }


def analyze(
    path: Path, expected_sha256: str = EXPECTED_SHA256
) -> dict[str, object]:
    expected_sha256 = expected_sha256.lower()
    if len(expected_sha256) != 64 or any(
        c not in "0123456789abcdef" for c in expected_sha256
    ):
        raise ValueError("expected SHA-256 must be 64 hexadecimal characters")

    digest = hashlib.sha256()
    partitions = {side: Partition(side) for side in (4, 8)}
    servers = {
        interval: SharedServerEnvelope(interval)
        for interval in (1, 2, 4, 8)
    }
    global_cycle_histogram: Counter[int] = Counter()
    millisecond_histogram: Counter[int] = Counter()
    current_cycle: int | None = None
    current_cycle_events = 0
    current_pixels: set[int] = set()
    current_colliding_pixels: set[int] = set()
    current_bin: int | None = None
    current_bin_events = 0
    peak_bin_events = -1
    peak_bin_index: int | None = None
    first_timestamp_ns: int | None = None
    previous_timestamp_ns: int | None = None
    minimum_positive_timestamp_delta_ns: int | None = None
    last_timestamp_ns: int | None = None
    first_bin: int | None = None
    last_bin: int | None = None
    event_count = 0
    central_count = 0
    same_pixel_collision_extra_events = 0
    same_pixel_collision_groups = 0
    raw_line_count = 0
    skipped_line_count = 0
    byte_count = 0

    def flush_cycle() -> None:
        nonlocal current_cycle_events, same_pixel_collision_groups
        if not current_cycle_events:
            return
        assert current_cycle is not None
        global_cycle_histogram[current_cycle_events] += 1
        same_pixel_collision_groups += len(current_colliding_pixels)
        for partition in partitions.values():
            partition.flush_cycle()
        for server in servers.values():
            server.observe_batch(current_cycle, current_cycle_events)
        current_cycle_events = 0
        current_pixels.clear()
        current_colliding_pixels.clear()

    def flush_bin() -> None:
        nonlocal peak_bin_events, peak_bin_index
        if current_bin is None:
            return
        millisecond_histogram[current_bin_events] += 1
        if current_bin_events > peak_bin_events:
            peak_bin_events = current_bin_events
            peak_bin_index = current_bin

    with path.open("rb") as handle:
        for line_number, raw_line in enumerate(handle, 1):
            digest.update(raw_line)
            byte_count += len(raw_line)
            raw_line_count += 1
            try:
                fields = raw_line.decode("ascii").split()
            except UnicodeDecodeError as exc:
                raise ValueError(f"line {line_number}: input is not ASCII") from exc
            if not fields or fields[0].startswith("#"):
                skipped_line_count += 1
                continue
            if len(fields) != 4:
                raise ValueError(f"line {line_number}: expected timestamp x y polarity")
            try:
                timestamp_ns = timestamp_to_ns(fields[0])
                x, y, polarity = map(int, fields[1:])
            except ValueError as exc:
                raise ValueError(f"line {line_number}: {exc}") from exc
            if not 0 <= x < SENSOR_WIDTH or not 0 <= y < SENSOR_HEIGHT:
                raise ValueError(f"line {line_number}: pixel ({x},{y}) is outside 240x180")
            if polarity not in (0, 1):
                raise ValueError(f"line {line_number}: polarity must be 0 or 1")
            if (
                previous_timestamp_ns is not None
                and timestamp_ns < previous_timestamp_ns
            ):
                raise ValueError(f"line {line_number}: timestamps are not monotonic")
            if previous_timestamp_ns is not None:
                timestamp_delta_ns = timestamp_ns - previous_timestamp_ns
                if timestamp_delta_ns > 0 and (
                    minimum_positive_timestamp_delta_ns is None
                    or timestamp_delta_ns < minimum_positive_timestamp_delta_ns
                ):
                    minimum_positive_timestamp_delta_ns = timestamp_delta_ns

            cycle = timestamp_ns // CLOCK_NS
            if current_cycle is None:
                current_cycle = cycle
            elif cycle != current_cycle:
                flush_cycle()
                current_cycle = cycle

            bin_index = timestamp_ns // BIN_NS
            if current_bin is None:
                current_bin = bin_index
                first_bin = bin_index
            elif bin_index != current_bin:
                flush_bin()
                millisecond_histogram[0] += bin_index - current_bin - 1
                current_bin = bin_index
                current_bin_events = 0

            pixel = y * SENSOR_WIDTH + x
            if pixel in current_pixels:
                same_pixel_collision_extra_events += 1
                current_colliding_pixels.add(pixel)
            else:
                current_pixels.add(pixel)
            current_cycle_events += 1
            current_bin_events += 1
            for partition in partitions.values():
                partition.add(x, y)

            event_count += 1
            central_count += int(x in CENTRAL_X and y in CENTRAL_Y)
            if first_timestamp_ns is None:
                first_timestamp_ns = timestamp_ns
            previous_timestamp_ns = timestamp_ns
            last_timestamp_ns = timestamp_ns
            last_bin = bin_index

    raw_sha256 = digest.hexdigest()
    if raw_sha256 != expected_sha256:
        raise ValueError(
            f"raw SHA-256 mismatch: expected {expected_sha256}, got {raw_sha256}"
        )
    if not event_count:
        raise ValueError("input contains no events")

    flush_cycle()
    flush_bin()
    active_five_ns_cycles = sum(global_cycle_histogram.values())
    total_millisecond_bins = sum(millisecond_histogram.values())
    active_millisecond_bins = total_millisecond_bins - millisecond_histogram[0]
    if sum(
        value * frequency
        for value, frequency in global_cycle_histogram.items()
    ) != event_count:
        raise AssertionError("global 5 ns event conservation failed")
    if sum(
        value * frequency
        for value, frequency in millisecond_histogram.items()
    ) != event_count:
        raise AssertionError("1 ms bin event conservation failed")
    for partition in partitions.values():
        if sum(partition.totals) != event_count:
            raise AssertionError(
                f"{partition.side}x{partition.side} event conservation failed"
            )
        if sum(
            value * frequency
            for value, frequency in
            partition.events_per_active_partition_cycle.items()
        ) != event_count:
            raise AssertionError(
                f"{partition.side}x{partition.side} cycle conservation failed"
            )
        if sum(partition.active_per_cycle.values()) != active_five_ns_cycles:
            raise AssertionError(
                f"{partition.side}x{partition.side} active-cycle count failed"
            )
    for server in servers.values():
        if (
            sum(server.latencies.values()) != event_count
            or server.batch_count != active_five_ns_cycles
        ):
            raise AssertionError(
                f"II={server.initiation_interval} server conservation failed"
            )

    assert first_timestamp_ns is not None and last_timestamp_ns is not None
    assert first_bin is not None and last_bin is not None
    return {
        "schema_version": 1,
        "definitions": {
            "timestamp_ns": "Decimal seconds multiplied exactly by 1e9; sub-nanosecond timestamps are rejected.",
            "five_ns_cycle": "floor(timestamp_ns/5); concurrency populations contain active global cycles only.",
            "same_pixel_collision": "An extra event after the first for one (pixel, 5 ns cycle); groups count distinct colliding (pixel, cycle) pairs.",
            "one_ms_bin": "floor(timestamp_ns/1,000,000); population spans first through last event bin inclusive and includes empty bins.",
            "p99": "Nearest-rank percentile: 1-indexed sorted value at ceil(0.99*N).",
            "partition_grid": "Row-major regions anchored at sensor (0,0); the final 8x8 row is 8x4 pixels.",
            "shared_server": "At each active 5 ns cycle the complete batch is enqueued in file order. If the server can start, the oldest event starts in that same cycle; later starts are separated by II cycles. Start latency is start_cycle-occurrence_cycle. Waiting occupancy is measured after same-cycle dispatch and excludes the event that starts.",
            "cross_batch_overlap": "An arriving batch overlaps when an older event is still waiting or the prior batch's start interval prevents a same-cycle start.",
            "finite_waiting_loss": "After the possible same-cycle oldest start, newest arrivals beyond waiting depth are dropped; the event that starts does not consume a waiting entry.",
        },
        "input_receipt": {
            "raw_sha256": raw_sha256,
            "expected_raw_sha256": expected_sha256,
            "sha256_match": True,
            "bytes": byte_count,
            "raw_lines": raw_line_count,
            "skipped_blank_or_comment_lines": skipped_line_count,
            "event_count": event_count,
        },
        "validation": {
            "timestamps_monotonic_non_decreasing": True,
            "timestamps_exact_integer_nanoseconds": True,
            "sensor_range_240x180": True,
            "polarity_range_0_or_1": True,
            "count_conserved_across_all_histograms": True,
        },
        "time_span": {
            "first_timestamp_ns": first_timestamp_ns,
            "last_timestamp_ns": last_timestamp_ns,
            "span_ns": last_timestamp_ns - first_timestamp_ns,
            "minimum_positive_timestamp_delta_ns": (
                minimum_positive_timestamp_delta_ns
            ),
        },
        "global_5ns": {
            "active_cycles": active_five_ns_cycles,
            "concurrency_histogram": histogram(global_cycle_histogram),
            "maximum_concurrency": max(global_cycle_histogram),
            "simultaneous_cycles": active_five_ns_cycles - global_cycle_histogram[1],
            "same_pixel_collision_extra_events": same_pixel_collision_extra_events,
            "same_pixel_collision_groups": same_pixel_collision_groups,
        },
        "global_1ms": {
            "first_bin_index": first_bin,
            "last_bin_index": last_bin,
            "total_bins_including_empty": total_millisecond_bins,
            "active_bins": active_millisecond_bins,
            "empty_bins": millisecond_histogram[0],
            "events_per_bin_histogram": histogram(millisecond_histogram),
            "peak_events_per_bin": max(millisecond_histogram),
            "peak_bin_index": peak_bin_index,
            "p99_events_per_bin_nearest_rank": percentile(
                millisecond_histogram, 99, 100
            ),
        },
        "central_4x4": {
            "x_min": CENTRAL_X.start,
            "x_max_inclusive": CENTRAL_X.stop - 1,
            "y_min": CENTRAL_Y.start,
            "y_max_inclusive": CENTRAL_Y.stop - 1,
            "event_count": central_count,
        },
        "partitions": {
            f"{side}x{side}": partition.report()
            for side, partition in partitions.items()
        },
        "shared_server_envelope": [
            server.report(event_count) for server in servers.values()
        ],
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--events", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--expected-sha256", default=EXPECTED_SHA256)
    return parser.parse_args()


def render(report: dict[str, object]) -> str:
    return json.dumps(report, indent=2, sort_keys=True) + "\n"


def main() -> None:
    args = parse_args()
    try:
        output = render(analyze(args.events, args.expected_sha256))
    except (OSError, ValueError) as exc:
        raise SystemExit(str(exc)) from exc
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open("w", encoding="utf-8", newline="\n") as handle:
            handle.write(output)
    else:
        sys.stdout.write(output)


if __name__ == "__main__":
    main()
