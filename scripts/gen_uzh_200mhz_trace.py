#!/usr/bin/env python3
"""Quantize checked-in UZH event metadata onto a real 200 MHz clock."""

from __future__ import annotations

import argparse
from pathlib import Path

import gen_uzh_physical_affine_vectors as oracle


def parse_args() -> argparse.Namespace:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--eventmeta", type=Path,
        default=root / "common_traces_uzh/uzh_shapes_rotation_patch.eventmeta.tsv",
    )
    parser.add_argument(
        "--output", type=Path,
        default=root / "tb/uzh_200mhz.addrpol.txt",
    )
    parser.add_argument("--clock-period-ns", type=int, default=5)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.clock_period_ns <= 0:
        raise SystemExit("clock period must be positive")
    digest = oracle.canonical_text_sha256(args.eventmeta)
    if digest != oracle.EXPECTED_EVENTMETA_SHA256:
        raise SystemExit("eventmeta SHA-256 receipt mismatch")
    events = oracle.load_events(args.eventmeta)
    origin_cycle = events[0].timestamp_ns // args.clock_period_ns

    cycles: dict[int, tuple[int, int, int]] = {}
    same_source_collisions = 0
    for event in events:
        cycle = event.timestamp_ns // args.clock_period_ns - origin_cycle
        address, polarity, count = cycles.get(cycle, (0, 0, 0))
        local_x = event.x - oracle.PATCH_X.start
        local_y = event.y - oracle.PATCH_Y.start
        source = local_y * 4 + local_x
        if not 0 <= source < 16:
            raise SystemExit("event escaped the checked-in 4x4 patch")
        bit = 1 << source
        same_source_collisions += int(bool(address & bit))
        address |= bit
        polarity = (polarity & ~bit) | (event.polarity << source)
        cycles[cycle] = address, polarity, count + 1

    if same_source_collisions != 0:
        raise SystemExit(
            "multiple events hit one source in a "
            f"{args.clock_period_ns} ns cycle"
        )
    if sum(count for _, _, count in cycles.values()) != len(events):
        raise AssertionError("event count changed during clock quantization")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8", newline="\n") as handle:
        for cycle, (address, polarity, _) in sorted(cycles.items()):
            handle.write(f"{cycle} {address:04x} {polarity:04x}\n")

    simultaneous = sum(count > 1 for _, _, count in cycles.values())
    max_simultaneous = max(count for _, _, count in cycles.values())
    span_cycles = max(cycles) - min(cycles)
    print(
        "UZH_200MHZ_TRACE "
        f"clock_period_ns={args.clock_period_ns} events={len(events)} "
        f"active_cycles={len(cycles)} simultaneous_cycles={simultaneous} "
        f"max_simultaneous={max_simultaneous} span_cycles={span_cycles} "
        f"same_source_collisions={same_source_collisions}"
    )
    print(f"UZH_200MHZ_TRACE_PASS output={args.output}")


if __name__ == "__main__":
    main()
