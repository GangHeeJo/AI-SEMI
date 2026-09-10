# Stage-2 RTL integration guide

## Scope

The implemented path accepts events from the verified Stage-1 AER leaf, keeps the pose version and timestamp captured at occurrence, applies an externally supplied fixed-point transform, and emits or stores a reference-coordinate event. It does not estimate pose, depth, or SLAM state.

## Top-level choices

| Top | Sensor proof size | Transform lanes | Output contract | Intended use |
|---|---:|---:|---|---|
| `aer_tx16_pose_affine2d` | 4x4 | 8 | eight always-draining event slots | correctness/PPA upper endpoint |
| `aer_tx16_pose_affine2d_serial` | 4x4 | 1 | one ready/valid event | K=1 throughput/PPA endpoint |
| `aer_tx64_pose_affine2d_serial` | 8x8 (four leaves) | 1 shared | one ready/valid event | tile hierarchy and upper-merge proof |
| `aer_tx64_pose_time_surface` | 8x8 (four leaves) | 1 shared | internal always-ready map writer plus read port | closed sensor-to-map proof |

The 4x4 size is a leaf, not a 4x4 window that scans a larger image. Larger physical sensors replicate leaves and assign tile origins. World-grid size is an independent parameter determined by physical coverage and cell resolution.

## Event lifetime

An accepted leaf record is:

```text
{polarity, pose_version, occurrence_timestamp}
```

The row bitmap carries independent pose and timestamp tags for every active column. After unpacking, a stream record is:

```text
{sensor_x, sensor_y, polarity, pose_version, occurrence_timestamp}
```

`sensor_x/y` already include the tile origin. The affine block preserves every event at its output. `mapped_valid=0` distinguishes an unknown pose or out-of-range result without silently deleting the event.

## Pose write protocol

Drive the requested pose ID and all six coefficients with `pose_wr_req`. A write occurs only when `pose_wr_commit=1`.

- `pose_wr_ready=1`: no accepted event still needs that ID.
- `pose_wr_rejected=1`: the requested ID is busy; keep the old record and retry later or use another free ID.
- `pose_accounting_error=1`: sticky underflow/overflow indicator; treat this as a contract failure and reset/debug it.

The last transform lookup and a rewrite of the same ID are not allowed on the same edge. The rewrite becomes ready on the following cycle. This prevents a retiring event from observing new coefficients.

## Fixed-point transform

Defaults are a signed 16-bit Q2.14 matrix and signed 24-bit Q10.14 offsets:

```text
world_x = round(m00*sensor_x + m01*sensor_y + tx)
world_y = round(m10*sensor_x + m11*sensor_y + ty)
```

Rounding is nearest with exact halves away from zero. Unknown pose produces diagnostic `(0,0)`. A known but out-of-range result is preserved as a signed diagnostic coordinate and is never clamped or wrapped into the map.

This affine stage is the first measurable RTL subset. A vehicle road-plane implementation still needs either calibrated plane coordinates before this stage or a projective calibration/homography stage; depth-free arbitrary 3-D reconstruction is not claimed.

## Explicit accounting

For a fully drained 4x4 serial top:

```text
generated = aer_overrun + fifo_overflow + delivered
```

For the 8x8 top, apply the same equation across all four tiles. AER overrun and upper FIFO overflow are separate signals because they describe different capacity limits. Events with missing pose or out-of-range coordinates still count as delivered stream events, though they do not update map memory.

The reference time surface keeps the greatest occurrence timestamp per cell. Equal-time ON/OFF events OR into a two-bit polarity set; an older event that retires later is reported as stale and cannot roll the cell back. Timestamp comparison assumes no counter wrap within one map epoch.

## Verification

Run the normal suite from the repository root:

```text
python scripts/run_stage2_regression.py
```

Add the original UZH trace and official 50-workload baseline:

```text
python scripts/run_stage2_regression.py --extended
```

On a host where `python` is not on `PATH`, invoke any Python 3 interpreter explicitly. The runner requires `iverilog` and `vvp`, creates simulation artifacts only in the OS temporary directory, and returns nonzero if any test fails.

The default suite includes a same-stimulus K=1/K=8 comparison. Its light profile must be lossless for both endpoints; its deliberately overloaded profile reports the finite K=1 FIFO loss and latency instead of treating them as hidden backpressure. The 10,000-cycle 8x8 random stress is part of `--extended` because it is substantially slower under Icarus.

## PPA entry points

Use the same 5 ns constraint and 45 nm library as Stage 1:

```text
genus -batch -files syn/run_genus_stage2_tx16_parallel.tcl
genus -batch -files syn/run_genus_stage2_tx16_serial.tcl
genus -batch -files syn/run_genus_stage2_tx64_serial.tcl
```

Map storage is deliberately excluded from the three logic comparisons. Report a real SRAM/BRAM macro separately instead of presenting a large resettable flip-flop array as a product memory implementation.
