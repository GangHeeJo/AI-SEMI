#!/usr/bin/env python3
"""Generate UZH pose/calibration vectors for the Stage-2 affine RTL.

This is a direction-only panorama oracle: it uses the measured camera pose and
calibration, but deliberately ignores translation because the event stream has
no depth. The selected quaternion direction is an explicit command-line
contract rather than something inferred from rotation magnitude.
"""

from __future__ import annotations

import argparse
import bisect
import csv
import hashlib
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


FRAC_BITS = 14
SCALE = 1 << FRAC_BITS
HALF = SCALE >> 1
MATRIX_BITS = 16
OFFSET_BITS = 24
PATCH_X = range(110, 114)
PATCH_Y = range(85, 89)
EXPECTED_EVENTMETA_SHA256 = (
    "af8fffc3a5f4de04c298f15fdce1ef9fa487f936001d99436a567d3c24443830"
)
EXPECTED_GROUNDTRUTH_SHA256 = (
    "bb62c320a51c1be412e17065eb86cfffa9041841290d439c23e447f1991aabdb"
)
EXPECTED_CALIBRATION_SHA256 = (
    "ab797c55a990c03656fbddac2473d3eace2a22f87fea4ca3b0497862b50545cd"
)


@dataclass(frozen=True)
class Calibration:
    fx: float
    fy: float
    cx: float
    cy: float
    k1: float
    k2: float
    p1: float
    p2: float
    k3: float


@dataclass(frozen=True)
class Pose:
    timestamp_s: float
    translation: tuple[float, float, float]
    quaternion: tuple[float, float, float, float]  # Hamilton x, y, z, w


@dataclass(frozen=True)
class Event:
    event_id: int
    x: int
    y: int
    polarity: int
    timestamp_ns: int


def canonical_text_sha256(path: Path) -> str:
    # Text-mode newline normalization makes the receipt independent of Git's
    # LF/CRLF checkout policy while retaining every numeric character.
    canonical = path.read_text(encoding="utf-8").encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


def normalize_quaternion(
    quaternion: tuple[float, float, float, float],
) -> tuple[float, float, float, float]:
    norm = math.sqrt(sum(value * value for value in quaternion))
    if norm == 0.0:
        raise ValueError("zero-norm quaternion")
    return tuple(value / norm for value in quaternion)  # type: ignore[return-value]


def load_calibration(path: Path) -> Calibration:
    values = [float(value) for value in path.read_text(encoding="utf-8").split()]
    if len(values) != 9:
        raise ValueError(f"expected 9 calibration values, got {len(values)}")
    return Calibration(*values)


def load_poses(path: Path) -> list[Pose]:
    poses: list[Pose] = []
    with path.open(encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, 1):
            if not line.strip():
                continue
            values = [float(value) for value in line.split()]
            if len(values) != 8:
                raise ValueError(f"{path}:{line_number}: expected 8 columns")
            timestamp, tx, ty, tz, qx, qy, qz, qw = values
            poses.append(
                Pose(
                    timestamp,
                    (tx, ty, tz),
                    normalize_quaternion((qx, qy, qz, qw)),
                )
            )
    if len(poses) < 2:
        raise ValueError("at least two pose samples are required")
    if any(a.timestamp_s >= b.timestamp_s for a, b in zip(poses, poses[1:])):
        raise ValueError("pose timestamps must be strictly increasing")
    return poses


def load_events(path: Path) -> list[Event]:
    events: list[Event] = []
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        required = {
            "event_id", "x", "y", "polarity", "occurrence_timestamp_ns"
        }
        if reader.fieldnames is None or not required.issubset(reader.fieldnames):
            raise ValueError(f"event metadata is missing columns {sorted(required)}")
        for row in reader:
            events.append(
                Event(
                    int(row["event_id"]),
                    int(row["x"]),
                    int(row["y"]),
                    int(row["polarity"]),
                    int(row["occurrence_timestamp_ns"]),
                )
            )
    if not events:
        raise ValueError("event metadata is empty")
    if [event.event_id for event in events] != list(range(len(events))):
        raise ValueError("event_id must be contiguous and start at zero")
    return events


def quaternion_dot(
    left: tuple[float, float, float, float],
    right: tuple[float, float, float, float],
) -> float:
    return sum(a * b for a, b in zip(left, right))


def slerp(
    left: tuple[float, float, float, float],
    right: tuple[float, float, float, float],
    fraction: float,
) -> tuple[float, float, float, float]:
    dot = quaternion_dot(left, right)
    if dot < 0.0:
        right = tuple(-value for value in right)  # type: ignore[assignment]
        dot = -dot
    dot = max(-1.0, min(1.0, dot))
    if dot > 0.9995:
        return normalize_quaternion(
            tuple(
                a + fraction * (b - a) for a, b in zip(left, right)
            )  # type: ignore[arg-type]
        )
    angle = math.acos(dot)
    sine = math.sin(angle)
    left_weight = math.sin((1.0 - fraction) * angle) / sine
    right_weight = math.sin(fraction * angle) / sine
    return normalize_quaternion(
        tuple(
            left_weight * a + right_weight * b for a, b in zip(left, right)
        )  # type: ignore[arg-type]
    )


def interpolate_pose(
    poses: list[Pose], timestamps: list[float], timestamp_s: float
) -> Pose:
    if not poses[0].timestamp_s <= timestamp_s <= poses[-1].timestamp_s:
        raise ValueError(f"event timestamp {timestamp_s} is outside pose coverage")
    upper = bisect.bisect_right(timestamps, timestamp_s)
    if upper == 0:
        return poses[0]
    if upper == len(poses):
        return poses[-1]
    left = poses[upper - 1]
    right = poses[upper]
    fraction = (
        (timestamp_s - left.timestamp_s)
        / (right.timestamp_s - left.timestamp_s)
    )
    translation = tuple(
        a + fraction * (b - a)
        for a, b in zip(left.translation, right.translation)
    )
    return Pose(
        timestamp_s,
        translation,  # type: ignore[arg-type]
        slerp(left.quaternion, right.quaternion, fraction),
    )


def quaternion_matrix(
    quaternion: tuple[float, float, float, float],
) -> tuple[tuple[float, float, float], ...]:
    x, y, z, w = quaternion
    return (
        (1.0 - 2.0*(y*y + z*z), 2.0*(x*y - z*w), 2.0*(x*z + y*w)),
        (2.0*(x*y + z*w), 1.0 - 2.0*(x*x + z*z), 2.0*(y*z - x*w)),
        (2.0*(x*z - y*w), 2.0*(y*z + x*w), 1.0 - 2.0*(x*x + y*y)),
    )


def transpose(
    matrix: tuple[tuple[float, float, float], ...],
) -> tuple[tuple[float, float, float], ...]:
    return tuple(tuple(matrix[row][column] for row in range(3)) for column in range(3))


def rotate(
    matrix: tuple[tuple[float, float, float], ...],
    vector: tuple[float, float, float],
) -> tuple[float, float, float]:
    return tuple(sum(row[i] * vector[i] for i in range(3)) for row in matrix)  # type: ignore[return-value]


def pixel_ray(
    u: float,
    v: float,
    calibration: Calibration,
    pixel_center_offset: float,
) -> tuple[float, float, float]:
    distorted_x = (u + pixel_center_offset - calibration.cx) / calibration.fx
    distorted_y = (v + pixel_center_offset - calibration.cy) / calibration.fy
    x = distorted_x
    y = distorted_y
    for _ in range(10):
        radius2 = x*x + y*y
        radial = (
            1.0 + calibration.k1*radius2
            + calibration.k2*radius2*radius2
            + calibration.k3*radius2*radius2*radius2
        )
        if abs(radial) < 1e-12:
            raise ValueError("distortion inversion encountered zero radial factor")
        delta_x = (
            2.0*calibration.p1*x*y
            + calibration.p2*(radius2 + 2.0*x*x)
        )
        delta_y = (
            calibration.p1*(radius2 + 2.0*y*y)
            + 2.0*calibration.p2*x*y
        )
        next_x = (distorted_x - delta_x) / radial
        next_y = (distorted_y - delta_y) / radial
        if max(abs(next_x - x), abs(next_y - y)) < 1e-14:
            x, y = next_x, next_y
            break
        x, y = next_x, next_y
    norm = math.sqrt(x*x + y*y + 1.0)
    return (x / norm, y / norm, 1.0 / norm)


def equirectangular(
    ray: tuple[float, float, float], width: int, height: int
) -> tuple[float, float]:
    x, y, z = ray
    norm = math.sqrt(x*x + y*y + z*z)
    longitude = math.atan2(y, x)
    latitude = math.asin(max(-1.0, min(1.0, z / norm)))
    world_x = width * ((longitude / (2.0*math.pi) + 0.5) % 1.0)
    world_y = height * (0.5 - latitude / math.pi)
    return world_x, world_y


def unwrap(value: float, reference: float, period: float) -> float:
    return value + round((reference - value) / period) * period


def world_coordinate(
    u: float,
    v: float,
    rotation: tuple[tuple[float, float, float], ...],
    calibration: Calibration,
    width: int,
    height: int,
    pixel_center_offset: float,
) -> tuple[float, float]:
    ray = pixel_ray(u, v, calibration, pixel_center_offset)
    return equirectangular(rotate(rotation, ray), width, height)


def fit_affine(
    rotation: tuple[tuple[float, float, float], ...],
    calibration: Calibration,
    width: int,
    height: int,
    pixel_center_offset: float,
) -> tuple[float, float, float, float, float, float, dict[tuple[int, int], tuple[float, float]], int]:
    mean_u = sum(PATCH_X) / len(PATCH_X)
    mean_v = sum(PATCH_Y) / len(PATCH_Y)
    reference_x, _ = world_coordinate(
        mean_u, mean_v, rotation, calibration, width, height,
        pixel_center_offset,
    )
    samples: dict[tuple[int, int], tuple[float, float]] = {}
    seam_adjustments = 0
    for v in PATCH_Y:
        for u in PATCH_X:
            raw_x, world_y = world_coordinate(
                u, v, rotation, calibration, width, height,
                pixel_center_offset,
            )
            world_x = unwrap(raw_x, reference_x, width)
            seam_adjustments += int(abs(world_x - raw_x) > 0.5*width)
            samples[(u, v)] = (world_x, world_y)

    mean_x = sum(value[0] for value in samples.values()) / len(samples)
    mean_y = sum(value[1] for value in samples.values()) / len(samples)
    denominator_u = sum((u - mean_u)**2 for u, _ in samples)
    denominator_v = sum((v - mean_v)**2 for _, v in samples)
    a = sum((u - mean_u)*(value[0] - mean_x) for (u, _), value in samples.items()) / denominator_u
    b = sum((v - mean_v)*(value[0] - mean_x) for (_, v), value in samples.items()) / denominator_v
    c = sum((u - mean_u)*(value[1] - mean_y) for (u, _), value in samples.items()) / denominator_u
    d = sum((v - mean_v)*(value[1] - mean_y) for (_, v), value in samples.items()) / denominator_v
    tx = mean_x - a*mean_u - b*mean_v
    ty = mean_y - c*mean_u - d*mean_v
    return a, b, c, d, tx, ty, samples, seam_adjustments


def round_half_away(value: float) -> int:
    rounded = math.floor(abs(value) + 0.5)
    return rounded if value >= 0.0 else -rounded


def round_q14_away(value: int) -> int:
    rounded = (abs(value) + HALF) >> FRAC_BITS
    return rounded if value >= 0 else -rounded


def check_signed(value: int, bits: int, label: str) -> None:
    if not -(1 << (bits - 1)) <= value < (1 << (bits - 1)):
        raise ValueError(f"{label}={value} does not fit signed {bits} bits")


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    index = max(0, math.ceil(fraction * len(ordered)) - 1)
    return ordered[index]


def wrapped_delta(left: float, right: float, period: int) -> float:
    delta = left - right
    return (delta + period/2.0) % period - period/2.0


FIELDNAMES = (
    "event_id", "sensor_x", "sensor_y", "polarity", "timestamp_ns_hex",
    "a_q14", "b_q14", "c_q14", "d_q14", "tx_q14", "ty_q14",
    "rtl_x", "rtl_y", "exact_x", "exact_y",
)


def generate(
    events: list[Event],
    poses: list[Pose],
    calibration: Calibration,
    width: int,
    height: int,
    pose_direction: str,
    pixel_center_offset: float,
) -> tuple[list[dict[str, object]], dict[str, float | int]]:
    timestamps = [pose.timestamp_s for pose in poses]
    rows: list[dict[str, object]] = []
    float_errors: list[float] = []
    cell_errors: list[float] = []
    exact_matches = 0
    event_exact_matches = 0
    sample_count = 0
    seam_adjustments = 0
    out_of_range = 0
    max_translation = 0.0
    origin_translation = poses[0].translation

    for event in events:
        pose = interpolate_pose(poses, timestamps, event.timestamp_ns * 1e-9)
        rotation = quaternion_matrix(pose.quaternion)
        if pose_direction == "world-to-camera":
            rotation = transpose(rotation)
        a, b, c, d, tx, ty, samples, adjusted = fit_affine(
            rotation, calibration, width, height, pixel_center_offset
        )
        seam_adjustments += adjusted

        coefficients = [round_half_away(value*SCALE) for value in (a, b, c, d)]
        offsets = [round_half_away(value*SCALE) for value in (tx, ty)]
        for label, value in zip(("a", "b", "c", "d"), coefficients):
            check_signed(value, MATRIX_BITS, f"event {event.event_id} {label}")
        for label, value in zip(("tx", "ty"), offsets):
            check_signed(value, OFFSET_BITS, f"event {event.event_id} {label}")

        a_q, b_q, c_q, d_q = coefficients
        tx_q, ty_q = offsets
        quantized: dict[tuple[int, int], tuple[int, int, int, int]] = {}
        for (sample_x, sample_y), (exact_float_x, exact_float_y) in samples.items():
            rtl_x = round_q14_away(a_q*sample_x + b_q*sample_y + tx_q)
            rtl_y = round_q14_away(c_q*sample_x + d_q*sample_y + ty_q)
            exact_x = round_half_away(exact_float_x) % width
            exact_y = round_half_away(exact_float_y)
            affine_float_x = a*sample_x + b*sample_y + tx
            affine_float_y = c*sample_x + d*sample_y + ty
            float_errors.append(
                math.hypot(
                    wrapped_delta(affine_float_x, exact_float_x, width),
                    affine_float_y - exact_float_y,
                )
            )
            cell_error = math.hypot(
                wrapped_delta(rtl_x, exact_x, width), rtl_y - exact_y
            )
            cell_errors.append(cell_error)
            exact_matches += int(rtl_x == exact_x and rtl_y == exact_y)
            sample_count += 1
            out_of_range += int(
                not (0 <= rtl_x < width and 0 <= rtl_y < height)
            )
            quantized[(sample_x, sample_y)] = (
                rtl_x, rtl_y, exact_x, exact_y
            )

        rtl_x, rtl_y, exact_x, exact_y = quantized[(event.x, event.y)]
        event_exact_matches += int(rtl_x == exact_x and rtl_y == exact_y)
        max_translation = max(
            max_translation,
            math.sqrt(sum((a0 - b0)**2 for a0, b0 in zip(
                pose.translation, origin_translation
            ))),
        )
        rows.append({
            "event_id": event.event_id,
            "sensor_x": event.x,
            "sensor_y": event.y,
            "polarity": event.polarity,
            "timestamp_ns_hex": f"{event.timestamp_ns:016x}",
            "a_q14": a_q,
            "b_q14": b_q,
            "c_q14": c_q,
            "d_q14": d_q,
            "tx_q14": tx_q,
            "ty_q14": ty_q,
            "rtl_x": rtl_x,
            "rtl_y": rtl_y,
            "exact_x": exact_x,
            "exact_y": exact_y,
        })

    metrics: dict[str, float | int] = {
        "events": len(rows),
        "samples": sample_count,
        "float_mean": sum(float_errors) / len(float_errors),
        "float_p99": percentile(float_errors, 0.99),
        "float_max": max(float_errors),
        "cell_match": exact_matches,
        "cell_match_percent": 100.0 * exact_matches / sample_count,
        "event_cell_match": event_exact_matches,
        "event_cell_match_percent": 100.0 * event_exact_matches / len(rows),
        "cell_mean": sum(cell_errors) / len(cell_errors),
        "cell_p99": percentile(cell_errors, 0.99),
        "cell_max": max(cell_errors),
        "seam_adjustments": seam_adjustments,
        "out_of_range": out_of_range,
        "max_translation_m": max_translation,
    }
    return rows, metrics


def write_rows(path: Path, rows: Iterable[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, FIELDNAMES, delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)


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
        default=root / "tb/uzh_physical_affine_vectors.tsv",
    )
    parser.add_argument("--world-width", type=int, default=512)
    parser.add_argument("--world-height", type=int, default=256)
    parser.add_argument(
        "--pose-direction",
        choices=("camera-to-world", "world-to-camera"),
        default="camera-to-world",
    )
    parser.add_argument(
        "--pixel-center-offset", type=float, choices=(0.0, 0.5), default=0.0
    )
    parser.add_argument("--max-affine-error-px", type=float, default=0.01)
    parser.add_argument("--max-cell-error", type=float, default=1.0)
    parser.add_argument("--min-exact-percent", type=float, default=99.0)
    parser.add_argument(
        "--skip-input-hash-check",
        action="store_true",
        help="allow an explicitly selected experiment with different inputs",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.world_width <= 1 or args.world_height <= 1:
        raise SystemExit("world dimensions must be greater than one")
    calibration = load_calibration(args.calibration)
    poses = load_poses(args.groundtruth)
    events = load_events(args.eventmeta)
    input_hashes = {
        "eventmeta": canonical_text_sha256(args.eventmeta),
        "groundtruth": canonical_text_sha256(args.groundtruth),
        "calibration": canonical_text_sha256(args.calibration),
    }
    expected_hashes = {
        "eventmeta": EXPECTED_EVENTMETA_SHA256,
        "groundtruth": EXPECTED_GROUNDTRUTH_SHA256,
        "calibration": EXPECTED_CALIBRATION_SHA256,
    }
    if not args.skip_input_hash_check and input_hashes != expected_hashes:
        changed = [
            name for name in input_hashes
            if input_hashes[name] != expected_hashes[name]
        ]
        raise SystemExit(
            "input SHA-256 mismatch for " + ", ".join(changed)
            + "; use --skip-input-hash-check only for an explicit experiment"
        )
    if any(event.x not in PATCH_X or event.y not in PATCH_Y for event in events):
        raise SystemExit("event metadata is not the expected x=110..113/y=85..88 patch")
    rows, metrics = generate(
        events, poses, calibration, args.world_width, args.world_height,
        args.pose_direction, args.pixel_center_offset,
    )
    write_rows(args.output, rows)
    sign_flips = sum(
        quaternion_dot(a.quaternion, b.quaternion) < 0.0
        for a, b in zip(poses, poses[1:])
    )
    print(
        "UZH_PHYSICAL_INPUT "
        f"eventmeta_sha256={input_hashes['eventmeta']} "
        f"groundtruth_sha256={input_hashes['groundtruth']} "
        f"calibration_sha256={input_hashes['calibration']}"
    )
    print(
        "UZH_PHYSICAL_ORACLE "
        f"direction={args.pose_direction} pixel_center={args.pixel_center_offset:.1f} "
        f"world={args.world_width}x{args.world_height} events={metrics['events']} "
        f"quaternion_sign_flips={sign_flips} "
        f"translation_ignored_max_m={metrics['max_translation_m']:.6f}"
    )
    print(
        "UZH_PHYSICAL_AFFINE_ERROR_PX "
        f"samples={metrics['samples']} mean={metrics['float_mean']:.6f} "
        f"p99={metrics['float_p99']:.6f} "
        f"max={metrics['float_max']:.6f}"
    )
    print(
        "UZH_PHYSICAL_Q14_CELL_ERROR "
        f"samples={metrics['samples']} "
        f"exact={metrics['cell_match']}/{metrics['samples']} "
        f"exact_percent={metrics['cell_match_percent']:.4f} "
        f"event_exact={metrics['event_cell_match']}/{metrics['events']} "
        f"event_exact_percent={metrics['event_cell_match_percent']:.4f} "
        f"mean={metrics['cell_mean']:.6f} p99={metrics['cell_p99']:.6f} "
        f"max={metrics['cell_max']:.6f} "
        f"seam_adjustments={metrics['seam_adjustments']} "
        f"out_of_range={metrics['out_of_range']}"
    )
    if metrics["out_of_range"] != 0:
        raise SystemExit("RTL-affine coordinates escaped the configured world grid")
    if metrics["float_max"] > args.max_affine_error_px:
        raise SystemExit(
            "float affine error exceeded --max-affine-error-px"
        )
    if metrics["cell_max"] > args.max_cell_error:
        raise SystemExit("Q14 cell error exceeded --max-cell-error")
    if metrics["cell_match_percent"] < args.min_exact_percent:
        raise SystemExit("Q14 exact-cell rate fell below --min-exact-percent")
    print(f"UZH_PHYSICAL_ORACLE_PASS output={args.output}")


if __name__ == "__main__":
    main()
