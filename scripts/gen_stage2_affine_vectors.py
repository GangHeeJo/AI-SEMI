#!/usr/bin/env python3
"""Generate self-contained vectors for the Stage-2 affine geometry contract."""

from __future__ import annotations

import argparse
import csv
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Mapping


FRAC_BITS = 14
SCALE = 1 << FRAC_BITS
HALF = SCALE >> 1
COEFF_BITS = 16
OFFSET_BITS = 24
SENSOR_SIDE = 4


@dataclass(frozen=True)
class Pose:
    version: int
    name: str
    a: int
    b: int
    c: int
    d: int
    tx: int
    ty: int


@dataclass(frozen=True)
class Bounds:
    x_min: int
    x_max: int
    y_min: int
    y_max: int


@dataclass(frozen=True)
class Result:
    pose_found: int
    x_acc_q14: int
    y_acc_q14: int
    ref_x: int
    ref_y: int
    in_range: int
    write_valid: int


def q_integer(value: int) -> int:
    return value * SCALE


# Raw Q2.14 value nearest to 1/sqrt(2); kept literal so vector generation is
# independent of host floating-point/libm behavior.
Q14_INV_SQRT2 = 11585


POSE_LIST = (
    Pose(0, "identity", SCALE, 0, 0, SCALE, 0, 0),
    Pose(1, "quarter_turn_tile", 0, -SCALE, SCALE, 0, q_integer(3), 0),
    Pose(2, "half_turn_tile", -SCALE, 0, 0, -SCALE, q_integer(3), q_integer(3)),
    Pose(3, "translate_positive_edge", SCALE, 0, 0, SCALE, q_integer(5), q_integer(3)),
    Pose(4, "translate_negative_edge", SCALE, 0, 0, SCALE, q_integer(-2), q_integer(-1)),
    Pose(5, "half_tie_translation", SCALE, 0, 0, SCALE, HALF, -HALF),
    Pose(
        6,
        "quantized_45deg_translate",
        Q14_INV_SQRT2,
        -Q14_INV_SQRT2,
        Q14_INV_SQRT2,
        Q14_INV_SQRT2,
        q_integer(3),
        q_integer(1),
    ),
)
POSES = {pose.version: pose for pose in POSE_LIST}


def check_signed(value: int, bits: int, label: str) -> None:
    low = -(1 << (bits - 1))
    high = (1 << (bits - 1)) - 1
    if not low <= value <= high:
        raise ValueError(f"{label}={value} does not fit signed {bits} bits")


def round_q14_away_from_zero(value: int) -> int:
    magnitude = abs(value)
    rounded = (magnitude + HALF) >> FRAC_BITS
    return rounded if value >= 0 else -rounded


def transform(
    pose_version: int,
    local_x: int,
    local_y: int,
    bounds: Bounds,
    poses: Mapping[int, Pose] = POSES,
) -> Result:
    if not 0 <= local_x < SENSOR_SIDE or not 0 <= local_y < SENSOR_SIDE:
        raise ValueError("local coordinates must be in the 4x4 tile")

    pose = poses.get(pose_version)
    if pose is None:
        return Result(0, 0, 0, 0, 0, 0, 0)

    x_acc = pose.a * local_x + pose.b * local_y + pose.tx
    y_acc = pose.c * local_x + pose.d * local_y + pose.ty
    ref_x = round_q14_away_from_zero(x_acc)
    ref_y = round_q14_away_from_zero(y_acc)
    in_range = int(
        bounds.x_min <= ref_x <= bounds.x_max
        and bounds.y_min <= ref_y <= bounds.y_max
    )
    return Result(1, x_acc, y_acc, ref_x, ref_y, in_range, in_range)


DIRECTED_CASES = (
    ("identity_origin", 0, 0, 0),
    ("quarter_turn_corner", 1, 3, 0),
    ("half_turn_corner", 2, 0, 0),
    ("positive_boundary_low", 3, 2, 3),
    ("positive_boundary_high", 3, 3, 3),
    ("negative_boundary_high", 4, 2, 1),
    ("negative_boundary_low", 4, 1, 0),
    ("positive_and_negative_half_ties", 5, 0, 0),
    ("quantized_rotation", 6, 3, 3),
    ("unknown_pose", 255, 0, 0),
)


FIELDNAMES = (
    "case_id",
    "case_kind",
    "case_name",
    "pose_version",
    "pose_name",
    "local_x",
    "local_y",
    "a_q14",
    "b_q14",
    "c_q14",
    "d_q14",
    "tx_q14",
    "ty_q14",
    "pose_found",
    "x_acc_q14",
    "y_acc_q14",
    "ref_x",
    "ref_y",
    "in_range",
    "write_valid",
)


def make_row(
    case_id: int,
    case_kind: str,
    case_name: str,
    pose_version: int,
    local_x: int,
    local_y: int,
    bounds: Bounds,
) -> dict[str, object]:
    pose = POSES.get(pose_version)
    result = transform(pose_version, local_x, local_y, bounds)
    return {
        "case_id": case_id,
        "case_kind": case_kind,
        "case_name": case_name,
        "pose_version": pose_version,
        "pose_name": pose.name if pose else "unknown",
        "local_x": local_x,
        "local_y": local_y,
        "a_q14": pose.a if pose else 0,
        "b_q14": pose.b if pose else 0,
        "c_q14": pose.c if pose else 0,
        "d_q14": pose.d if pose else 0,
        "tx_q14": pose.tx if pose else 0,
        "ty_q14": pose.ty if pose else 0,
        "pose_found": result.pose_found,
        "x_acc_q14": result.x_acc_q14,
        "y_acc_q14": result.y_acc_q14,
        "ref_x": result.ref_x,
        "ref_y": result.ref_y,
        "in_range": result.in_range,
        "write_valid": result.write_valid,
    }


def generate_rows(bounds: Bounds) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for name, version, x, y in DIRECTED_CASES:
        rows.append(make_row(len(rows), "directed", name, version, x, y, bounds))
    for pose in POSE_LIST:
        for y in range(SENSOR_SIDE):
            for x in range(SENSOR_SIDE):
                rows.append(
                    make_row(
                        len(rows),
                        "exhaustive",
                        f"{pose.name}_x{x}_y{y}",
                        pose.version,
                        x,
                        y,
                        bounds,
                    )
                )
    return rows


def self_check_model(bounds: Bounds) -> None:
    if len(POSES) != len(POSE_LIST):
        raise AssertionError("pose versions must be unique")
    for pose in POSE_LIST:
        if not 0 <= pose.version <= 255:
            raise AssertionError("pose_version must fit 8 bits")
        for label, value in (("a", pose.a), ("b", pose.b), ("c", pose.c), ("d", pose.d)):
            check_signed(value, COEFF_BITS, f"pose {pose.version} {label}")
        check_signed(pose.tx, OFFSET_BITS, f"pose {pose.version} tx")
        check_signed(pose.ty, OFFSET_BITS, f"pose {pose.version} ty")

    assert round_q14_away_from_zero(HALF) == 1
    assert round_q14_away_from_zero(-HALF) == -1
    assert round_q14_away_from_zero(HALF - 1) == 0
    assert round_q14_away_from_zero(-HALF + 1) == 0

    for y in range(SENSOR_SIDE):
        for x in range(SENSOR_SIDE):
            identity = transform(0, x, y, bounds)
            assert (identity.ref_x, identity.ref_y) == (x, y)
            quarter = transform(1, x, y, bounds)
            assert (quarter.ref_x, quarter.ref_y) == (3 - y, x)
            half_turn = transform(2, x, y, bounds)
            assert (half_turn.ref_x, half_turn.ref_y) == (3 - x, 3 - y)

    def expected_in_range(x: int, y: int) -> int:
        return int(bounds.x_min <= x <= bounds.x_max and bounds.y_min <= y <= bounds.y_max)

    for version, x, y, expected_xy in (
        (3, 2, 3, (7, 6)),
        (3, 3, 3, (8, 6)),
        (4, 2, 1, (0, 0)),
        (4, 1, 0, (-1, -1)),
    ):
        result = transform(version, x, y, bounds)
        assert (result.ref_x, result.ref_y) == expected_xy
        assert result.in_range == expected_in_range(*expected_xy)
        assert result.write_valid == result.in_range
    tie = transform(5, 0, 0, bounds)
    assert (tie.ref_x, tie.ref_y) == (1, -1)
    assert tie.in_range == expected_in_range(1, -1)
    assert tie.write_valid == tie.in_range
    assert transform(255, 0, 0, bounds) == Result(0, 0, 0, 0, 0, 0, 0)


def write_vectors(path: Path, rows: Iterable[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDNAMES, delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)


def self_check_file(path: Path, expected_rows: list[dict[str, object]]) -> None:
    with path.open(newline="", encoding="utf-8") as handle:
        actual_rows = list(csv.DictReader(handle, delimiter="\t"))
    if len(actual_rows) != len(expected_rows):
        raise AssertionError("vector row count changed during serialization")
    for actual, expected in zip(actual_rows, expected_rows):
        for field in FIELDNAMES:
            if actual[field] != str(expected[field]):
                raise AssertionError(
                    f"serialized mismatch case={expected['case_id']} field={field}: "
                    f"{actual[field]!r} != {expected[field]!r}"
                )


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=repo_root / "tb" / "stage2_affine_vectors.tsv",
    )
    parser.add_argument("--x-min", type=int, default=0)
    parser.add_argument("--x-max", type=int, default=7)
    parser.add_argument("--y-min", type=int, default=0)
    parser.add_argument("--y-max", type=int, default=7)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    bounds = Bounds(args.x_min, args.x_max, args.y_min, args.y_max)
    if bounds.x_min > bounds.x_max or bounds.y_min > bounds.y_max:
        raise SystemExit("minimum bounds must not exceed maximum bounds")
    self_check_model(bounds)
    rows = generate_rows(bounds)
    expected_exhaustive = len(POSE_LIST) * SENSOR_SIDE * SENSOR_SIDE
    actual_exhaustive = sum(row["case_kind"] == "exhaustive" for row in rows)
    assert actual_exhaustive == expected_exhaustive
    write_vectors(args.output, rows)
    self_check_file(args.output, rows)
    print(
        "SELF_CHECK_PASS "
        f"poses={len(POSE_LIST)} directed={len(DIRECTED_CASES)} "
        f"exhaustive={expected_exhaustive} total={len(rows)} output={args.output}"
    )


if __name__ == "__main__":
    main()
