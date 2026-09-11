# Stage-2 geometry reference contract

This document defines the smallest geometry block that can be translated to RTL without committing the project to a particular sensor size, map size, or application. It deliberately stops at a supplied-pose 2D affine transform; pose estimation and map storage are separate stages.

## Event contract

Each accepted event carries:

- `local_x`, `local_y`: unsigned 2-bit coordinates for one 4x4 sensor tile.
- `sensor_x = tile_origin_x + local_x`, `sensor_y = tile_origin_y + local_y`: parameterized-width coordinates produced by the bitmap adapter. The transform consumes these coordinates; the checked-in vectors use a zero tile origin. Tile/base origins describe fixed physical placement and must remain stable while reset is deasserted. A dynamically moving ROI would require draining/resetting first or adding origin to each occurrence record.
- `polarity`: one bit, transported unchanged by the geometry block.
- `pose_version`: an unsigned, parameterized-width key captured when the event occurs, not when it retires from AER arbitration. The checked-in verification vectors use 8 bits; the first small RTL integration may use fewer entries to keep the pose table measurable.
- `occurrence_timestamp`: an unsigned, parameterized-width event time captured by the same source FIFO entry as polarity and pose. It is transported unchanged through coordinate conversion.

Every event in a row bitmap needs its own `pose_version`. Different columns in one transmitted bitmap may have entered their source FIFOs in different cycles, so one tag per output lane is insufficient.

Inside one coefficient region, the local pose table maps `pose_version` to one
record `(a, b, c, d, tx, ty)`. At full-sensor level the key is therefore
`(region_x, region_y, pose_version)`. A local write may commit only when no
accepted event in that region still references the ID; a busy-ID write is
backpressured. How coefficients are produced is outside this contract.

## Full-sensor coefficient publication

The measured 240x180 design point divides the sensor into 30x23 coefficient
regions of at most 8x8 pixels. Each region keeps a local pose table. The
configuration controller accepts exactly this transaction:

```text
BEGIN(target pose)
WRITE(x=0,y=0) ... WRITE(x=29,y=22)  // strict row-major order
PUBLISH(target pose)
```

`ABORT` may cancel a partial transaction without changing the active pose.
Each WRITE advances only on the selected region's `pose_wr_commit`; a busy old
slot stalls the stream and is not a drop. PUBLISH is legal only after all 690
writes. It changes a registered `active_pose_version`, so an event accepted on
the publication edge receives the previous version and events accepted from
the next cycle receive the new version. BEGIN may never target the active ID.
An out-of-order command, early publication, impossible commit, or regional
pose-accounting failure prevents publication and fail-stops configuration
until reset. The existing active pose remains usable.

The first controller proof defaults to `POSE_W=1`, a two-slot buffer. This is a
correctness point, not yet a freshness result: the producer must tolerate a
stall until every region releases the old inactive slot. At 112 coefficient
bits per region, one complete pose payload is 77,280 bits and takes at least
690 data cycles. At 200 MHz that lower bound is 3.45 microseconds, excluding
BEGIN/PUBLISH and any in-flight-event stalls.

## Fixed-point transform

The authoritative equations are:

```text
x_acc = a * sensor_x + b * sensor_y + tx
y_acc = c * sensor_x + d * sensor_y + ty
```

- `a`, `b`, `c`, `d`: signed 16-bit Q2.14 values, range `[-2, 2 - 2^-14]`.
- `tx`, `ty`: signed 24-bit Q10.14 values, range `[-512, 512 - 2^-14]`.
- `x_acc`, `y_acc`: exact signed Q*.14 intermediate values. For 2-bit coordinates and the widths above, a signed 25-bit accumulator is sufficient. No intermediate saturation or wrapping is allowed.
- Translation is applied after the matrix multiplication.

The matrix values, rather than a clockwise/counter-clockwise label, define the coordinate convention. For example, `(a,b,c,d)=(0,-1,1,0)` means `X=-y+tx`, `Y=x+ty`.

## Rounding

Each accumulator is rounded independently to the nearest integer. Exact half-way cases round away from zero:

```text
round(q) =  ( q + 2^13) >> 14                  when q >= 0
round(q) = -((-q + 2^13) >> 14)                when q < 0
```

The shifts above operate on non-negative magnitudes. This rule is intentionally explicit so Python, RTL, and later software do not disagree on negative values.

## Pose and range validity

- Unknown `pose_version`: `pose_found=0`, `in_range=0`, `write_valid=0`, and deterministic diagnostic coordinates `(0,0)`.
- Known pose: round first, then compare the integer result against configurable inclusive bounds `[x_min,x_max]` and `[y_min,y_max]`.
- Out of range: preserve the computed signed coordinates for debug, set `in_range=0` and `write_valid=0`. Never clamp or wrap an address.
- In range: `pose_found=1`, `in_range=1`, `write_valid=1`.
- `polarity` is not changed by geometry and is meaningful only when `write_valid=1` downstream.
- `event_valid` remains asserted for known, unknown, and out-of-range events so every accepted event has an observable terminal status.
- On a ready/valid stall, coordinates and all metadata remain stable until the consumer accepts the event.

The checked-in vectors use an 8x8 reference window (`0..7` on both axes) only to exercise boundaries. It is a verification fixture, not a product-resolution decision.

## Vector format

`tb/stage2_affine_vectors.tsv` contains directed cases followed by every `(x,y)` in the 4x4 tile for every defined pose. Coefficients, raw accumulators, rounded coordinates, and all validity bits are included in each row so an RTL testbench does not need a hidden copy of the Python pose table.

Generate and self-check it with:

```text
python scripts/gen_stage2_affine_vectors.py
```
