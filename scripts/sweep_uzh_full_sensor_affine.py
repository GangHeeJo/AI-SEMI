#!/usr/bin/env python3
"""Characterize local affine regions across the full 240x180 UZH sensor."""

from __future__ import annotations

import argparse
import math
from array import array
from pathlib import Path

import gen_uzh_physical_affine_vectors as oracle


def fits_signed(value: int, bits: int) -> bool:
    return -(1 << (bits - 1)) <= value < (1 << (bits - 1))


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
    parser.add_argument("--sensor-width", type=int, default=240)
    parser.add_argument("--sensor-height", type=int, default=180)
    parser.add_argument("--tile-side", type=int, default=4)
    parser.add_argument("--world-width", type=int, default=512)
    parser.add_argument("--world-height", type=int, default=256)
    parser.add_argument("--pose-samples", type=int, default=32)
    parser.add_argument("--max-fixed-error-cell", type=float, default=0.5)
    parser.add_argument("--max-axis-cell-error", type=float, default=1.0)
    parser.add_argument("--min-exact-percent", type=float, default=99.0)
    parser.add_argument(
        "--skip-global-baseline",
        action="store_true",
        help="skip the region-independent full-sensor affine diagnostic",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.tile_side < 2:
        raise SystemExit("tile-side must be at least two")
    if args.sensor_width < 2 or args.sensor_height < 2:
        raise SystemExit("sensor dimensions must be at least two")
    if args.world_width < 1 or args.world_height < 1:
        raise SystemExit("world dimensions must be positive")
    if not all(math.isfinite(value) for value in (
        args.max_fixed_error_cell,
        args.max_axis_cell_error,
        args.min_exact_percent,
    )):
        raise SystemExit("error gates must be finite")
    if args.max_fixed_error_cell < 0 or args.max_axis_cell_error < 0:
        raise SystemExit("maximum error gates must be non-negative")
    if not 0 <= args.min_exact_percent <= 100:
        raise SystemExit("min-exact-percent must be in [0,100]")
    if any(
        dimension > args.tile_side and dimension % args.tile_side == 1
        for dimension in (args.sensor_width, args.sensor_height)
    ):
        raise SystemExit("tile-side would leave a one-pixel edge region")
    if args.pose_samples < 2:
        raise SystemExit("pose-samples must be at least two")

    hashes = {
        "eventmeta": oracle.canonical_text_sha256(args.eventmeta),
        "groundtruth": oracle.canonical_text_sha256(args.groundtruth),
        "calibration": oracle.canonical_text_sha256(args.calibration),
    }
    expected = {
        "eventmeta": oracle.EXPECTED_EVENTMETA_SHA256,
        "groundtruth": oracle.EXPECTED_GROUNDTRUTH_SHA256,
        "calibration": oracle.EXPECTED_CALIBRATION_SHA256,
    }
    if hashes != expected:
        raise SystemExit("input SHA-256 receipt mismatch")

    events = oracle.load_events(args.eventmeta)
    poses = oracle.load_poses(args.groundtruth)
    calibration = oracle.load_calibration(args.calibration)
    pose_timestamps = [pose.timestamp_s for pose in poses]
    first_time = events[0].timestamp_ns * 1e-9
    last_time = events[-1].timestamp_ns * 1e-9
    uniform_sample_times = [
        first_time + index*(last_time - first_time)/(args.pose_samples - 1)
        for index in range(args.pose_samples)
    ]
    in_span_poses = [
        pose for pose in poses
        if first_time <= pose.timestamp_s <= last_time
    ]
    rotations = [
        oracle.quaternion_matrix(pose.quaternion) for pose in in_span_poses
    ]
    risk_times: set[float] = set()
    anchor_rays = [
        oracle.pixel_ray(u, v, calibration, 0.0)
        for v in (0, (args.sensor_height - 1)/2, args.sensor_height - 1)
        for u in (0, (args.sensor_width - 1)/2, args.sensor_width - 1)
    ]
    pole_risk = [
        max(abs(oracle.rotate(rotation, ray)[2]) for ray in anchor_rays)
        for rotation in rotations
    ]
    local_peaks = [
        index for index in range(1, len(pole_risk) - 1)
        if pole_risk[index] >= pole_risk[index - 1]
        and pole_risk[index] >= pole_risk[index + 1]
    ]
    for index in sorted(
        local_peaks, key=pole_risk.__getitem__, reverse=True
    )[:8]:
        risk_times.add(in_span_poses[index].timestamp_s)

    angular_jumps: list[tuple[float, int]] = []
    for index in range(len(in_span_poses) - 1):
        left = in_span_poses[index].quaternion
        right = in_span_poses[index + 1].quaternion
        cosine = min(1.0, abs(sum(a*b for a, b in zip(left, right))))
        angular_jumps.append((2.0*math.acos(cosine), index))
    for _, index in sorted(angular_jumps, reverse=True)[:8]:
        risk_times.add(in_span_poses[index].timestamp_s)
        risk_times.add(in_span_poses[index + 1].timestamp_s)

    sample_times = sorted(set(uniform_sample_times) | risk_times)

    float_errors = array("d")
    fixed_errors = array("d")
    cell_errors = array("d")
    shared_float_errors = array("d")
    shared_cell_errors = array("d")
    exact_cells = 0
    shared_exact_cells = 0
    q14_samples = 0
    shared_q14_samples = 0
    tile_count = 0
    coefficient_overflow_tiles = 0
    seam_tiles = 0
    seam_samples = 0
    wrapped_x_samples = 0
    y_out_of_range_samples = 0
    max_axis_cell_error = 0.0
    max_fixed_axis_error = 0.0
    fixed_samples_over_budget = 0
    dual_axis_mismatches = 0
    axis_samples_over_budget = 0
    worst_float = (-1.0, 0.0, -1, -1)
    worst_cell = (-1.0, 0.0, -1, -1)
    shared_coefficient_overflow_poses = 0
    shared_seam_samples = 0
    shared_x_wrap_samples = 0
    shared_y_out_of_range_samples = 0

    for timestamp in sample_times:
        pose = oracle.interpolate_pose(poses, pose_timestamps, timestamp)
        rotation = oracle.quaternion_matrix(pose.quaternion)

        for origin_y in range(0, args.sensor_height, args.tile_side):
            y_values = range(
                origin_y, min(origin_y + args.tile_side, args.sensor_height)
            )
            for origin_x in range(0, args.sensor_width, args.tile_side):
                x_values = range(
                    origin_x,
                    min(origin_x + args.tile_side, args.sensor_width),
                )
                a, b, c, d, tx, ty, samples, adjusted = oracle.fit_affine(
                    rotation, calibration, args.world_width,
                    args.world_height, 0.0, x_values, y_values,
                )
                tile_count += 1
                seam_samples += adjusted
                seam_tiles += int(adjusted != 0)
                tile_float_errors: list[float] = []
                for (x, y), (exact_x, exact_y) in samples.items():
                    affine_x = a*x + b*y + tx
                    affine_y = c*x + d*y + ty
                    error = math.hypot(
                        oracle.wrapped_delta(
                            affine_x, exact_x, args.world_width
                        ),
                        affine_y - exact_y,
                    )
                    float_errors.append(error)
                    tile_float_errors.append(error)
                tile_float_max = max(tile_float_errors)
                if tile_float_max > worst_float[0]:
                    worst_float = (
                        tile_float_max, timestamp, origin_x, origin_y
                    )

                q_values = [
                    oracle.round_half_away(value*oracle.SCALE)
                    for value in (a, b, c, d, tx, ty)
                ]
                if not all(
                    fits_signed(value, bits)
                    for value, bits in zip(
                        q_values,
                        (oracle.MATRIX_BITS,)*4 + (oracle.OFFSET_BITS,)*2,
                    )
                ):
                    coefficient_overflow_tiles += 1
                    continue

                a_q, b_q, c_q, d_q, tx_q, ty_q = q_values
                tile_cell_errors: list[float] = []
                for (x, y), (exact_float_x, exact_float_y) in samples.items():
                    fixed_x = (a_q*x + b_q*y + tx_q) / oracle.SCALE
                    fixed_y = (c_q*x + d_q*y + ty_q) / oracle.SCALE
                    fixed_delta_x = abs(oracle.wrapped_delta(
                        fixed_x, exact_float_x, args.world_width
                    ))
                    fixed_delta_y = abs(fixed_y - exact_float_y)
                    fixed_error = math.hypot(fixed_delta_x, fixed_delta_y)
                    fixed_errors.append(fixed_error)
                    max_fixed_axis_error = max(
                        max_fixed_axis_error,
                        fixed_delta_x,
                        fixed_delta_y,
                    )
                    fixed_samples_over_budget += int(
                        fixed_error > args.max_fixed_error_cell
                    )
                    rtl_x = oracle.round_q14_away(a_q*x + b_q*y + tx_q)
                    rtl_y = oracle.round_q14_away(c_q*x + d_q*y + ty_q)
                    exact_x = oracle.round_half_away(exact_float_x) % args.world_width
                    exact_y = oracle.round_half_away(exact_float_y)
                    wrapped_x = rtl_x % args.world_width
                    wrapped_x_samples += int(wrapped_x != rtl_x)
                    y_out_of_range_samples += int(
                        not 0 <= rtl_y < args.world_height
                    )
                    delta_x = abs(oracle.wrapped_delta(
                        wrapped_x, exact_x, args.world_width
                    ))
                    delta_y = abs(rtl_y - exact_y)
                    error = math.hypot(delta_x, delta_y)
                    cell_errors.append(error)
                    tile_cell_errors.append(error)
                    max_axis_cell_error = max(
                        max_axis_cell_error, delta_x, delta_y
                    )
                    axis_samples_over_budget += int(
                        delta_x > args.max_axis_cell_error
                        or delta_y > args.max_axis_cell_error
                    )
                    dual_axis_mismatches += int(
                        delta_x != 0.0 and delta_y != 0.0
                    )
                    exact_cells += int(
                        wrapped_x == exact_x and rtl_y == exact_y
                    )
                    q14_samples += 1
                tile_cell_max = max(tile_cell_errors)
                if tile_cell_max > worst_cell[0]:
                    worst_cell = (
                        tile_cell_max, timestamp, origin_x, origin_y
                    )

    # Keep the shared-coefficient diagnostic on the original uniform sample
    # set. It is not a PASS gate and need not repeat every added risk pose.
    if not args.skip_global_baseline:
        for timestamp in uniform_sample_times:
            pose = oracle.interpolate_pose(poses, pose_timestamps, timestamp)
            rotation = oracle.quaternion_matrix(pose.quaternion)
            (
                shared_a, shared_b, shared_c, shared_d,
                shared_tx, shared_ty, shared_samples, shared_adjusted,
            ) = oracle.fit_affine(
                rotation, calibration, args.world_width,
                args.world_height, 0.0,
                range(args.sensor_width), range(args.sensor_height),
            )
            shared_seam_samples += shared_adjusted
            shared_q_values = [
                oracle.round_half_away(value*oracle.SCALE)
                for value in (
                    shared_a, shared_b, shared_c, shared_d,
                    shared_tx, shared_ty,
                )
            ]
            shared_fits = all(
                fits_signed(value, bits)
                for value, bits in zip(
                    shared_q_values,
                    (oracle.MATRIX_BITS,)*4 + (oracle.OFFSET_BITS,)*2,
                )
            )
            shared_coefficient_overflow_poses += int(not shared_fits)
            for (x, y), (exact_float_x, exact_float_y) in shared_samples.items():
                affine_x = shared_a*x + shared_b*y + shared_tx
                affine_y = shared_c*x + shared_d*y + shared_ty
                shared_float_errors.append(math.hypot(
                    oracle.wrapped_delta(
                        affine_x, exact_float_x, args.world_width
                    ),
                    affine_y - exact_float_y,
                ))
                if not shared_fits:
                    continue
                a_q, b_q, c_q, d_q, tx_q, ty_q = shared_q_values
                rtl_x = oracle.round_q14_away(a_q*x + b_q*y + tx_q)
                rtl_y = oracle.round_q14_away(c_q*x + d_q*y + ty_q)
                exact_x = (
                    oracle.round_half_away(exact_float_x)
                    % args.world_width
                )
                exact_y = oracle.round_half_away(exact_float_y)
                wrapped_x = rtl_x % args.world_width
                shared_x_wrap_samples += int(wrapped_x != rtl_x)
                shared_y_out_of_range_samples += int(
                    not 0 <= rtl_y < args.world_height
                )
                delta_x = abs(oracle.wrapped_delta(
                    wrapped_x, exact_x, args.world_width
                ))
                delta_y = abs(rtl_y - exact_y)
                shared_cell_errors.append(math.hypot(delta_x, delta_y))
                shared_exact_cells += int(
                    wrapped_x == exact_x and rtl_y == exact_y
                )
                shared_q14_samples += 1

    total_samples = len(sample_times) * args.sensor_width * args.sensor_height
    if len(float_errors) != total_samples:
        raise AssertionError("full-sensor float sample count mismatch")
    if not fixed_errors:
        raise SystemExit("no tile fit the current fixed-point coefficient widths")
    if len(fixed_errors) != q14_samples or len(cell_errors) != q14_samples:
        raise AssertionError("full-sensor fixed-point sample count mismatch")
    print(
        "UZH_FULL_SENSOR_REGION_SWEEP "
        f"sensor={args.sensor_width}x{args.sensor_height} "
        f"tile={args.tile_side} world={args.world_width}x{args.world_height} "
        f"uniform_poses={args.pose_samples} selected_poses={len(sample_times)} "
        f"risk_poses_added={len(sample_times)-args.pose_samples} "
        f"tiles={tile_count} samples={total_samples}"
    )
    print(
        "UZH_FULL_SENSOR_FLOAT_ERROR_PX "
        f"mean={sum(float_errors)/len(float_errors):.6f} "
        f"p99={oracle.percentile(float_errors, 0.99):.6f} "
        f"max={max(float_errors):.6f} "
        f"worst_time_tile={worst_float[1]:.9f},"
        f"{worst_float[2]},{worst_float[3]}"
    )
    print(
        "UZH_FULL_SENSOR_Q14_CONTINUOUS_ERROR_CELL "
        f"mean={sum(fixed_errors)/len(fixed_errors):.6f} "
        f"p99={oracle.percentile(fixed_errors, 0.99):.6f} "
        f"max={max(fixed_errors):.6f} "
        f"max_axis={max_fixed_axis_error:.6f} "
        f"samples_over_{args.max_fixed_error_cell:g}cell="
        f"{fixed_samples_over_budget}"
    )
    if q14_samples:
        print(
            "UZH_FULL_SENSOR_Q14_CELL_ERROR "
            f"samples={q14_samples} exact={exact_cells}/{q14_samples} "
            f"exact_percent={100.0*exact_cells/q14_samples:.4f} "
            f"mean={sum(cell_errors)/len(cell_errors):.6f} "
            f"p99={oracle.percentile(cell_errors, 0.99):.6f} "
            f"max={max(cell_errors):.6f} max_axis={max_axis_cell_error:.6f} "
            f"dual_axis_mismatches={dual_axis_mismatches} "
            f"axis_samples_over_{args.max_axis_cell_error:g}cell="
            f"{axis_samples_over_budget} "
            f"worst_time_tile={worst_cell[1]:.9f},"
            f"{worst_cell[2]},{worst_cell[3]}"
        )
    print(
        "UZH_FULL_SENSOR_BOUNDARIES "
        f"coefficient_overflow_tiles={coefficient_overflow_tiles} "
        f"seam_tiles={seam_tiles} seam_samples={seam_samples} "
        f"x_wrap_samples={wrapped_x_samples} "
        f"y_out_of_range_samples={y_out_of_range_samples}"
    )
    if shared_float_errors:
        print(
            "UZH_FULL_SENSOR_SHARED_AFFINE_FLOAT_ERROR_PX "
            f"mean={sum(shared_float_errors)/len(shared_float_errors):.6f} "
            f"p99={oracle.percentile(shared_float_errors, 0.99):.6f} "
            f"max={max(shared_float_errors):.6f}"
        )
    if shared_q14_samples:
        print(
            "UZH_FULL_SENSOR_SHARED_AFFINE_Q14_CELL_ERROR "
            f"samples={shared_q14_samples} "
            f"exact={shared_exact_cells}/{shared_q14_samples} "
            f"exact_percent="
            f"{100.0*shared_exact_cells/shared_q14_samples:.4f} "
            f"mean={sum(shared_cell_errors)/len(shared_cell_errors):.6f} "
            f"p99={oracle.percentile(shared_cell_errors, 0.99):.6f} "
            f"max={max(shared_cell_errors):.6f}"
        )
    if not args.skip_global_baseline:
        print(
            "UZH_FULL_SENSOR_SHARED_AFFINE_BOUNDARIES "
            f"coefficient_overflow_poses="
            f"{shared_coefficient_overflow_poses} "
            f"seam_samples={shared_seam_samples} "
            f"x_wrap_samples={shared_x_wrap_samples} "
            f"y_out_of_range_samples={shared_y_out_of_range_samples}"
        )
    if (
        not all(math.isfinite(value) for value in float_errors)
        or not all(math.isfinite(value) for value in fixed_errors)
        or not all(math.isfinite(value) for value in cell_errors)
        or not all(math.isfinite(value) for value in shared_float_errors)
        or not all(math.isfinite(value) for value in shared_cell_errors)
    ):
        raise SystemExit("full-sensor sweep produced a non-finite error")
    exact_percent = 100.0 * exact_cells / q14_samples
    if max(fixed_errors) > args.max_fixed_error_cell:
        raise SystemExit("full-sensor continuous Q14 error exceeded its gate")
    if max_axis_cell_error > args.max_axis_cell_error:
        raise SystemExit("full-sensor Q14 axis error exceeded its gate")
    if exact_percent < args.min_exact_percent:
        raise SystemExit("full-sensor exact-cell rate fell below its gate")
    if coefficient_overflow_tiles:
        raise SystemExit("full-sensor sweep found coefficient overflows")
    if seam_tiles or wrapped_x_samples or y_out_of_range_samples:
        raise SystemExit(
            "full-sensor sweep requires an unimplemented seam or boundary stage"
        )
    print("UZH_FULL_SENSOR_SAMPLED_REGION_SWEEP_PASS")


if __name__ == "__main__":
    main()
