# Stage-2 measured-pose mapping checkpoint

## What this proves

This checkpoint tests whether the existing fixed-point 2-D affine RTL can
approximate the calibrated direction mapping of one 4x4 UZH event-camera
patch. It does not estimate pose, infer depth, or claim full SLAM. Translation
is present in the motion-capture trace but is ignored because a pixel and pose
alone do not determine a 3-D world point.

The 512x256 equirectangular grid is a verification coordinate system. Its 2:1
shape gives equal angular longitude/latitude sampling at the equator and fits
the existing Q10.14 offset range. It is not a final product image-size or map
resolution decision.

## Reproducible inputs

| File | Meaning | SHA-256 |
|---|---|---|
| `common_traces_uzh/uzh_shapes_rotation_patch.eventmeta.tsv` | 8,503 patch events with per-event ns timestamp | `af8fffc3a5f4de04c298f15fdce1ef9fa487f936001d99436a567d3c24443830` |
| `common_traces_uzh/uzh_shapes_rotation_groundtruth.txt` | 11,883 motion-capture samples, `t tx ty tz qx qy qz qw` | `bb62c320a51c1be412e17065eb86cfffa9041841290d439c23e447f1991aabdb` |
| `common_traces_uzh/uzh_shapes_rotation_calib.txt` | `fx fy cx cy k1 k2 p1 p2 k3` radtan calibration | `ab797c55a990c03656fbddac2473d3eace2a22f87fea4ca3b0497862b50545cd` |

The ground-truth file is the tracked input reviewed from
`origin/main@d39e457`. The calibration is copied byte-for-byte from the local
UZH `shapes_rotation/calib.txt` download; it was not tracked on `main`, so its
hash is recorded here. Receipts hash UTF-8 text after canonical LF newline
normalization, so Git's Windows CRLF checkout policy does not invalidate them.

## Geometry and fixed-point contract

For every event `(u,v,t)` the generator:

1. normalizes adjacent quaternions, resolves their sign ambiguity, and SLERPs
   at the event's ns timestamp;
2. inverts the Brown-Conrady/radtan camera distortion;
3. rotates the normalized camera ray into the motion-capture world frame;
4. projects the ray to a 512x256 equirectangular direction cell;
5. maps all 16 pixels of the same 4x4 patch at that pose and least-squares fits
   `X=a*u+b*v+tx`, `Y=c*u+d*v+ty` after longitude-seam unwrapping;
6. quantizes the matrix to signed Q2.14 and offsets to signed Q10.14, then uses
   the RTL's exact half-away-from-zero rounding rule.

The original ns timestamp reaches about 59.4 billion and therefore requires
64 bits in this geometry test. A product may use a separate, narrower modular
map-age counter, but it must not silently truncate physical ns timestamps into
32 bits.

## Quaternion-direction check

The direction was checked independently with 120 adjacent intensity-frame
pairs, each 44.065 ms apart, restricted to at most 3 mm of translation. Warping
with the ground-truth columns interpreted as `(qx,qy,qz,qw)` and the standard
Hamilton active camera-to-world matrix clearly beat its inverse:

| metric | camera-to-world | inverse |
|---|---:|---:|
| mean ZNCC | 0.94295 | 0.85427 |
| mean gradient cosine | 0.77470 | 0.35710 |
| normalized robust MAE | 0.10738 | 0.14549 |
| photo inliers | 97.885% | 95.395% |

The correct direction won 116/120 pairs by ZNCC and 118/120 by gradient
agreement. Reinterpreting the file as `qw,qx,qy,qz` was also much worse. A
pixel-center offset of 0 versus 0.5 was empirically indistinguishable at this
resolution, so the generator uses the standard integer OpenCV pixel coordinate
`(u,v)` and records that choice explicitly.

## Measured result

With `camera-to-world`, integer pixel centers, and the complete 8,503-event
patch:

| comparison | mean | p99 | max |
|---|---:|---:|---:|
| float affine vs exact spherical coordinate | 0.000474 px | 0.001512 px | 0.002428 px |
| Q14 RTL cell vs exact rounded cell | 0.003984 cell | 0 cell | 1 cell |

The geometry statistics cover all 16 patch pixels at every event pose:
136,048 pose-pixel samples. Q14 matches 135,506/136,048 exact rounded cells
(99.6016%); every mismatch is one cell at a rounding boundary. At the 8,503
actual event pixels the exact rate is 8,479/8,503 (99.7177%). There are no
coefficient overflows, longitude seam crossings, or out-of-range results. The
affine RTL matches all 8,503 generated fixed-point event results bit-for-bit
and preserves 64-bit timestamp and polarity metadata. The regression pins all
three input hashes and fails if float max error exceeds 0.01 px, Q14 max error
exceeds one cell, or exact-cell rate falls below 99%.

This is strong evidence that affine arithmetic is sufficient for this central
4x4 patch. A tile that crosses the periodic longitude seam still needs an
explicit modulo-X stage or a chosen panorama seam that stays outside the active
field; the current affine block intentionally does neither.

## Full-sensor local-region characterization

The sweep starts with 32 uniformly spaced poses, then adds high pole-risk poses
and the endpoints of the largest adjacent quaternion jumps. For this trace that
is 55 selected poses and 2,376,000 checked pose-pixel samples for each region
size. The risk prescan uses only nine precomputed sensor rays and all
ground-truth poses, so it is cheap while still finding the narrow 53.7 s error
peak missed by uniform sampling alone.

| comparison | mean | p99 | max |
|---|---:|---:|---:|
| per-region 4x4 float affine vs exact spherical coordinate | 0.000955 px | 0.005660 px | 0.025968 px |
| Q14 continuous coordinate vs exact spherical coordinate | 0.003937 cell | 0.010347 cell | 0.030991 cell |
| integer RTL cell vs exact rounded cell | 0.005074 cell | 0 cell | 1.414214 cells |

The continuous Q14 result measures quantized coefficients before the final
integer output rounding; its Euclidean maximum is 0.030991 cell (maximum on one
axis 0.030318), satisfying the pre-existing 0.5-cell geometry budget. After
integer rounding,
Q14 is exact for 2,363,952/2,376,000 samples (99.4929%). The maximum error on
either integer axis is one cell; only 21 samples miss by one cell on both axes,
which gives the Euclidean `sqrt(2)` maximum. There are no coefficient
overflows, seam adjustments, X wraps, or Y range failures in the selected
poses. The enforced gates are continuous-Q14 Euclidean error at most 0.5 cell,
integer per-axis error at most one cell, exact-cell rate at least 99%, and zero
coefficient/boundary failures. Unquantized float error is reported separately
and is not substituted for the fixed-point gate.

The 8x8 hierarchy is one coefficient region: its four 4x4 AER leaves correctly
share one affine record. The same sampled sweep at the implemented 8x8 sharing
granularity also passes, with continuous-Q14 maximum 0.132046 cell and
2,358,565/2,376,000 exact integer cells (99.2662%). Region-size
characterization locates the current accuracy boundary:

| square coefficient region | regions per pose | continuous-Q14 max | exact integer cells | gates |
|---:|---:|---:|---:|---|
| 4x4 | 2,700 | 0.030991 | 99.4929% | pass |
| 8x8 | 690 | 0.132046 | 99.2662% | pass |
| 12x12 | 300 | 0.333611 | 98.7188% | fail exact-rate |
| 16x16 | 180 | 0.555265 | 97.9292% | fail continuous/error rate |
| 24x24 | 80 | 1.102444 | 95.6706% | fail |
| 32x32 | 48 | 1.645995 | 92.8128% | fail |

Thus the current 8x8 arithmetic granularity is the largest tested size that
meets both gates. A full 240x180 sensor would use 30x23 = 690 such regions (the
last row covers four active rows), and still needs a coefficient
distribution/update mechanism that selects the region as well as the pose
version. It does **not** require shrinking the existing hierarchy back to 4x4.
Fitting one affine over the complete sensor remains a useful rejected baseline:
float mean/p99/max is `1.356383/7.711730/24.654806 px` and only
301,659/1,382,400 Q14 cells are exact (21.8214%). A calibrated-ray projection
stage remains an alternative if distributing region-local coefficients costs
more than computing the projection.

The 55-pose risk-augmented sweep is a measured-range characterization, not an
exhaustive guarantee for arbitrary camera trajectories or panorama-seam
crossings. An independent vectorized audit over all 10,990 ground-truth poses
in the event span confirmed zero seam crossings and the same 4x4 0.025968 px
float maximum, but that audit is not part of the dependency-free checked-in
runner.

The original 8,503-event replay injects one fitted coefficient set per event
directly into the transform. It therefore proves transform arithmetic, not the
feasibility of updating pose history at that rate.

The follow-on dual-region integration probe uses the actual loader, local pose
history/guards, and two complete tx64 datapaths. It places adjacent regions at
`(32,168)` and `(40,168)`, fits each region independently at the first event
pose and at the sweep's worst 8x8 float-error pose (`53.732373158 s`), then
probes every pixel. All 256 events match the generated Q14 RTL coordinates and
preserve region, pose version, 64-bit occurrence timestamp, and polarity with
no drop. The calibrated spherical comparison is 251/256 exact integer cells;
the other five are one-cell rounding-boundary differences, with 0.130578-cell
maximum continuous-Q14 error and no seam or range failure. This is deliberately
a measured-pose/calibration synthetic full-pixel probe: the checked-in real
event crop only covers `x=110..113, y=85..88`, so it is not described as an
actual two-region traffic replay. Real pose cadence and same-cycle pose bucketing
remain system-level choices.

## Run

```text
python scripts/run_stage2_regression.py --physical
python scripts/run_stage2_regression.py --full-sensor-sweep
```

The full-sensor option enforces both the 4x4 reference and the implemented 8x8
coefficient-sharing granularity. Larger sizes in the table are characterization
runs of the same script using `--tile-side`.

The vector TSVs are generated in a temporary directory and are intentionally
not committed. This avoids storing duplicate derivatives of the three hashed
source files.
