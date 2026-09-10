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
4x4 patch. It is not yet evidence for every tile of a 240x180 sensor. The next
geometry exit condition is a full-sensor tile sweep across held-out poses; only
if its p99/max error misses the chosen cell budget should a homography or more
general projective unit be added. A tile that crosses the periodic longitude
seam also needs an explicit modulo-X stage or a chosen panorama seam that stays
outside the active field; the current affine block intentionally does neither.

The RTL replay injects one fitted coefficient set per event directly into the
transform. It therefore proves the transform arithmetic, not the feasibility
of updating pose history at that rate. A later integration test must choose a
real pose update cadence, quantize versions, and handle events within one cycle
whose ns timestamps map to different poses.

## Run

```text
python scripts/run_stage2_regression.py --physical
```

The vector TSV is generated in a temporary directory and is intentionally not
committed. This avoids storing a second 8,503-row derivative of the three
hashed source files.
