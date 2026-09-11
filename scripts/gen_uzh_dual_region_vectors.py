#!/usr/bin/env python3
"""Generate measured-pose vectors for two adjacent 8x8 RTL regions."""

from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path

import gen_uzh_physical_affine_vectors as oracle


WORLD_WIDTH = 512
WORLD_HEIGHT = 256
BASE_X = 32
BASE_Y = 168
REGION_SIDE = 8
# First checked-in event, then the full-sensor sweep's worst 8x8 float-error pose.
POSE_TIMESTAMPS_S = (4.101324001, 53.732373158)
FIELDNAMES = (
    "kind", "pose_version", "region", "source", "sensor_x", "sensor_y",
    "polarity", "timestamp_ns_hex", "m00_q14", "m01_q14", "m10_q14",
    "m11_q14", "tx_q14", "ty_q14", "rtl_x", "rtl_y", "exact_x",
    "exact_y",
)


def parse_args() -> argparse.Namespace:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--eventmeta", type=Path,
        default=root / "common_traces_uzh/uzh_shapes_rotation_patch.eventmeta.tsv",
    )
    parser.add_argument(
        "--groundtruth", type=Path,
        default=root / "common_traces_uzh/uzh_shapes_rotation_groundtruth.txt",
    )
    parser.add_argument(
        "--calibration", type=Path,
        default=root / "common_traces_uzh/uzh_shapes_rotation_calib.txt",
    )
    parser.add_argument(
        "--output", type=Path,
        default=root / "tb/uzh_dual_region_vectors.tsv",
    )
    return parser.parse_args()


def fits_signed(value: int, bits: int) -> bool:
    return -(1 << (bits - 1)) <= value < (1 << (bits - 1))


def source_index(sensor_x: int, sensor_y: int, origin_x: int) -> int:
    local_x = sensor_x - origin_x
    local_y = sensor_y - BASE_Y
    tile = (local_y // 4) * 2 + local_x // 4
    return tile * 16 + (local_y % 4) * 4 + local_x % 4


def main() -> None:
    args = parse_args()
    hashes = {
        "eventmeta": oracle.canonical_text_sha256(args.eventmeta),
        "groundtruth": oracle.canonical_text_sha256(args.groundtruth),
        "calibration": oracle.canonical_text_sha256(args.calibration),
    }
    expected_hashes = {
        "eventmeta": oracle.EXPECTED_EVENTMETA_SHA256,
        "groundtruth": oracle.EXPECTED_GROUNDTRUTH_SHA256,
        "calibration": oracle.EXPECTED_CALIBRATION_SHA256,
    }
    if hashes != expected_hashes:
        raise SystemExit("input SHA-256 receipt mismatch")

    events = oracle.load_events(args.eventmeta)
    poses = oracle.load_poses(args.groundtruth)
    calibration = oracle.load_calibration(args.calibration)
    pose_times = [pose.timestamp_s for pose in poses]
    event_start = events[0].timestamp_ns * 1e-9
    event_end = events[-1].timestamp_ns * 1e-9
    if not all(event_start <= value <= event_end for value in POSE_TIMESTAMPS_S):
        raise SystemExit("selected pose is outside the measured event interval")

    rows: list[dict[str, int | str]] = []
    float_errors: list[float] = []
    fixed_errors: list[float] = []
    cell_errors: list[float] = []
    exact_cells = 0
    seam_adjustments = 0
    coefficient_records = 0

    for pose_version, timestamp_s in enumerate(POSE_TIMESTAMPS_S):
        pose = oracle.interpolate_pose(poses, pose_times, timestamp_s)
        rotation = oracle.quaternion_matrix(pose.quaternion)
        timestamp_ns = oracle.round_half_away(timestamp_s * 1_000_000_000)
        region_payloads = []

        for region in range(2):
            origin_x = BASE_X + region * REGION_SIDE
            x_values = range(origin_x, origin_x + REGION_SIDE)
            y_values = range(BASE_Y, BASE_Y + REGION_SIDE)
            a, b, c, d, tx, ty, samples, adjusted = oracle.fit_affine(
                rotation, calibration, WORLD_WIDTH, WORLD_HEIGHT, 0.0,
                x_values, y_values,
            )
            seam_adjustments += adjusted
            q_values = [
                oracle.round_half_away(value * oracle.SCALE)
                for value in (a, b, c, d, tx, ty)
            ]
            if not all(
                fits_signed(value, bits)
                for value, bits in zip(
                    q_values,
                    (oracle.MATRIX_BITS,) * 4 + (oracle.OFFSET_BITS,) * 2,
                )
            ):
                raise SystemExit("selected coefficient does not fit RTL width")
            m00, m01, m10, m11, tx_q14, ty_q14 = q_values
            rows.append({
                "kind": 0, "pose_version": pose_version, "region": region,
                "source": 0, "sensor_x": 0, "sensor_y": 0, "polarity": 0,
                "timestamp_ns_hex": "0", "m00_q14": m00, "m01_q14": m01,
                "m10_q14": m10, "m11_q14": m11, "tx_q14": tx_q14,
                "ty_q14": ty_q14, "rtl_x": 0, "rtl_y": 0,
                "exact_x": 0, "exact_y": 0,
            })
            coefficient_records += 1
            region_payloads.append((
                region, origin_x, x_values, y_values,
                a, b, c, d, tx, ty, samples, q_values,
            ))

        for (
            region, origin_x, x_values, y_values,
            a, b, c, d, tx, ty, samples, q_values,
        ) in region_payloads:
            m00, m01, m10, m11, tx_q14, ty_q14 = q_values
            for sensor_y in y_values:
                for sensor_x in x_values:
                    exact_float_x, exact_float_y = samples[(sensor_x, sensor_y)]
                    affine_x = a * sensor_x + b * sensor_y + tx
                    affine_y = c * sensor_x + d * sensor_y + ty
                    float_errors.append(math.hypot(
                        oracle.wrapped_delta(
                            affine_x, exact_float_x, WORLD_WIDTH
                        ),
                        affine_y - exact_float_y,
                    ))
                    fixed_x = (
                        m00 * sensor_x + m01 * sensor_y + tx_q14
                    ) / oracle.SCALE
                    fixed_y = (
                        m10 * sensor_x + m11 * sensor_y + ty_q14
                    ) / oracle.SCALE
                    fixed_errors.append(math.hypot(
                        oracle.wrapped_delta(
                            fixed_x, exact_float_x, WORLD_WIDTH
                        ),
                        fixed_y - exact_float_y,
                    ))
                    rtl_x = oracle.round_q14_away(
                        m00 * sensor_x + m01 * sensor_y + tx_q14
                    )
                    rtl_y = oracle.round_q14_away(
                        m10 * sensor_x + m11 * sensor_y + ty_q14
                    )
                    exact_x = oracle.round_half_away(exact_float_x) % WORLD_WIDTH
                    exact_y = oracle.round_half_away(exact_float_y)
                    delta_x = abs(oracle.wrapped_delta(
                        rtl_x % WORLD_WIDTH, exact_x, WORLD_WIDTH
                    ))
                    delta_y = abs(rtl_y - exact_y)
                    cell_errors.append(math.hypot(delta_x, delta_y))
                    exact_cells += int(rtl_x == exact_x and rtl_y == exact_y)
                    if not 0 <= rtl_x < WORLD_WIDTH or not 0 <= rtl_y < WORLD_HEIGHT:
                        raise SystemExit("selected RTL result is outside world bounds")
                    source = source_index(sensor_x, sensor_y, origin_x)
                    if not 0 <= source < 64:
                        raise AssertionError("invalid 8x8 AER source index")
                    rows.append({
                        "kind": 1, "pose_version": pose_version,
                        "region": region, "source": source,
                        "sensor_x": sensor_x, "sensor_y": sensor_y,
                        "polarity": (sensor_x + sensor_y + pose_version) & 1,
                        "timestamp_ns_hex": f"{timestamp_ns:016x}",
                        "m00_q14": 0, "m01_q14": 0,
                        "m10_q14": 0, "m11_q14": 0,
                        "tx_q14": 0, "ty_q14": 0,
                        "rtl_x": rtl_x, "rtl_y": rtl_y,
                        "exact_x": exact_x, "exact_y": exact_y,
                    })

    event_count = len(cell_errors)
    exact_percent = 100.0 * exact_cells / event_count
    if coefficient_records != 4 or event_count != 256:
        raise AssertionError("dual-region vector count mismatch")
    print(
        "UZH_DUAL_REGION_VECTOR_SET "
        f"origin={BASE_X},{BASE_Y} region=8x8 poses={len(POSE_TIMESTAMPS_S)} "
        f"coefficients={coefficient_records} events={event_count}"
    )
    print(
        "UZH_DUAL_REGION_ERROR "
        f"float_max={max(float_errors):.6f} "
        f"q14_continuous_max={max(fixed_errors):.6f} "
        f"exact={exact_cells}/{event_count} exact_percent={exact_percent:.4f} "
        f"cell_max={max(cell_errors):.6f} seam_adjustments={seam_adjustments}"
    )
    if seam_adjustments != 0:
        raise SystemExit("selected regions cross the panorama seam")
    if max(fixed_errors) > 0.5:
        raise SystemExit("selected continuous Q14 error exceeded 0.5 cell")
    if max(cell_errors) > 1.0:
        raise SystemExit("selected rounded-cell error exceeded one cell")
    if exact_cells != 251:
        raise SystemExit("selected exact-cell receipt changed from 251/256")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, FIELDNAMES, delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)
    print(f"UZH_DUAL_REGION_ORACLE_PASS output={args.output}")


if __name__ == "__main__":
    main()
