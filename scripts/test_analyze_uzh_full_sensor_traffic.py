from __future__ import annotations

import hashlib
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import analyze_uzh_full_sensor_traffic as analyzer


EVENTS = b"""\
0.000000000 0 0 1
0.000000001 0 0 0
0.000000004 4 0 1
0.000000005 8 0 1
0.001000000 110 85 1
0.003000000 113 88 0
"""


class AnalyzerTest(unittest.TestCase):
    def analyze(self, content: bytes = EVENTS):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "events.txt"
            path.write_bytes(content)
            return analyzer.analyze(path, hashlib.sha256(content).hexdigest())

    def test_histograms_and_receipt(self) -> None:
        report = self.analyze()
        self.assertEqual(report["input_receipt"]["event_count"], 6)
        self.assertEqual(report["central_4x4"]["event_count"], 2)
        self.assertEqual(
            report["global_5ns"]["concurrency_histogram"],
            [[1, 3], [3, 1]],
        )
        self.assertEqual(
            report["global_5ns"]["same_pixel_collision_extra_events"], 1
        )
        self.assertEqual(
            report["global_5ns"]["same_pixel_collision_groups"], 1
        )
        self.assertEqual(
            report["global_1ms"]["events_per_bin_histogram"],
            [[0, 1], [1, 2], [4, 1]],
        )
        self.assertEqual(
            report["global_1ms"]["p99_events_per_bin_nearest_rank"], 4
        )
        self.assertEqual(report["global_1ms"]["peak_events_per_bin"], 4)
        self.assertEqual(report["global_1ms"]["peak_bin_index"], 0)
        self.assertEqual(
            report["time_span"]["minimum_positive_timestamp_delta_ns"], 1
        )
        leaf = report["partitions"]["4x4"]
        self.assertEqual(
            leaf["active_partitions_per_active_global_cycle"]["histogram"],
            [[1, 3], [2, 1]],
        )
        self.assertEqual(
            leaf["events_per_active_partition_cycle"]["histogram"],
            [[1, 4], [2, 1]],
        )
        self.assertEqual(
            leaf["total_events_per_region"]["histogram"],
            [[0, 2695], [1, 4], [2, 1]],
        )
        region = report["partitions"]["8x8"]
        self.assertEqual(
            region["total_events_per_region"]["histogram"],
            [[0, 686], [1, 3], [3, 1]],
        )
        self.assertEqual(analyzer.render(report), analyzer.render(report))

    def test_shared_server_rules(self) -> None:
        server = analyzer.SharedServerEnvelope(initiation_interval=2)
        server.finite = {
            depth: analyzer.FiniteWaitingQueue(2, depth)
            for depth in (1, 8)
        }
        server.observe_batch(cycle=10, count=3)
        server.observe_batch(cycle=100, count=1)
        report = server.report(event_count=4)
        self.assertEqual(report["cross_batch_overlap_batches"], 0)
        self.assertEqual(
            report["infinite_waiting_queue"]["post_dispatch_peak_waiting"],
            2,
        )
        self.assertEqual(
            report["infinite_waiting_queue"]["start_latency_cycles"]["histogram"],
            [[0, 2], [2, 1], [4, 1]],
        )
        self.assertEqual(
            [queue["lost_events"] for queue in report["finite_waiting_queues"]],
            [1, 0],
        )

    def test_hash_gate(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "events.txt"
            path.write_bytes(EVENTS)
            with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
                analyzer.analyze(path, "0" * 64)

    def test_rejects_non_monotonic_timestamp(self) -> None:
        with self.assertRaisesRegex(ValueError, "not monotonic"):
            self.analyze(
                b"0.000000001 0 0 0\n0.000000000 0 0 0\n"
            )

    def test_rejects_sub_nanosecond_timestamp(self) -> None:
        with self.assertRaisesRegex(ValueError, "integer nanosecond"):
            self.analyze(b"0.0000000001 0 0 0\n")

    def test_rejects_pixel_and_polarity_out_of_range(self) -> None:
        for content, message in (
            (b"0.000000000 240 0 0\n", "outside 240x180"),
            (b"0.000000000 0 0 2\n", "polarity must be 0 or 1"),
        ):
            with self.subTest(content=content):
                with self.assertRaisesRegex(ValueError, message):
                    self.analyze(content)


if __name__ == "__main__":
    unittest.main()
