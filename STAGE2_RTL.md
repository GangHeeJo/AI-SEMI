# Stage-2 RTL integration guide

## Scope

The implemented path accepts events from the verified Stage-1 AER leaf, keeps the pose version and timestamp captured at occurrence, applies an externally supplied fixed-point transform, and emits or stores a reference-coordinate event. It does not estimate pose, depth, or SLAM state.

## Top-level choices

| Top | Sensor proof size | Transform lanes | Output contract | Intended use |
|---|---:|---:|---|---|
| `aer_tx16_pose_affine2d` | 4x4 | 8 | eight always-draining event slots | correctness/PPA upper endpoint |
| `aer_tx16_pose_affine2d_serial` | 4x4 | 1 | one ready/valid event | K=1 throughput/PPA endpoint |
| `aer_tx16_pose_affine2d_banked` | 4x4 | parameterized 1/2/4/8 | K independent ready/valid events | measured intermediate K endpoints |
| `aer_tx16_pose_affine2d_k4_serial` | 4x4 | 4, merged to 1 | one ready/valid event | apples-to-apples single-port K=4 PPA endpoint |
| `aer_tx64_pose_affine2d_serial` | 8x8 (four leaves) | 1 shared | one ready/valid event | tile hierarchy and upper-merge proof |
| `aer_tx64_pose_time_surface` | 8x8 (four leaves) | 1 shared | internal always-ready map writer plus read port | closed sensor-to-map proof |
| `aer_tx64_pose_sram_surface` | 8x8 (four leaves) | 1 shared | external-memory read/modify/write handshake | large-map integration proof |

The 4x4 size is a leaf, not a 4x4 window that scans a larger image. Larger physical sensors replicate leaves and assign tile origins. World-grid size is an independent parameter determined by physical coverage and cell resolution. Tile/base origins are static physical configuration and must remain unchanged while reset is deasserted; unlike pose and timestamp, they are not captured per event.

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
- `pose_accounting_error=1`: sticky underflow/overflow indicator. The affected pose ID is fail-safe poisoned and cannot be overwritten until reset, because a saturated count no longer proves that all references drained. Treat this as a contract failure and reset/debug it.

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

The reference time surface keeps the newest occurrence timestamp per cell. Equal-time ON/OFF events OR into a two-bit polarity set; an older event that retires later is reported as stale and cannot roll the cell back. Timestamp order uses modulo subtraction, so wrap is handled without clearing the map when the maximum occurrence-time separation for events compared at one cell is strictly less than half the timestamp range. An exact half-range difference is ambiguous and is conservatively reported as stale. `TIMESTAMP_W` must be at least 2. Reset the map if the timestamp source itself is reset or that half-range contract cannot be guaranteed.

For a large grid, `world_time_surface_sram_writer` stores no cell array internally. It issues one ready/valid read request, waits for the matching response, and issues a write only for a newer or equal-time event. The external memory cell is `{valid, timestamp, polarity_seen[1:0]}`. Request valid/address/data remain stable until ready. The current writer deliberately allows only one outstanding event, so it is a correctness-oriented macro boundary rather than a high-throughput memory engine; banking or a hazard-aware pipeline is required if measured traffic cannot tolerate its backpressure.

## Verification

Run the normal suite from the repository root:

```text
python scripts/run_stage2_regression.py
```

Add the original UZH trace and official 50-workload baseline:

```text
python scripts/run_stage2_regression.py --extended
```

Sweep the K=1 FIFO against K=8 while preserving every cycle in the checked-in UZH trace:

```text
python scripts/run_stage2_regression.py --trace-sweep
```

Sweep the banked K=2/K=4 endpoints and the single-output K=4 endpoint on the same timing:

```text
python scripts/run_stage2_regression.py --lane-sweep
```

The banked endpoint assigns adapter lane `L` to bank `L mod K`. Each bank has its own FIFO and transform, preserves order within that bank, and can be independently backpressured. There is intentionally no total retirement order across banks; consumers use occurrence timestamps for map conflict resolution. The K=4 serialized endpoint adds a stall-safe round-robin merge so its area and loss can be compared fairly with K=1 when the map has only one input port. On the checked-in UZH timing, it first becomes lossless at depth 32 per bank; K=4 depth 8 is lossless only when all four transform outputs can retire independently.

On a host where `python` is not on `PATH`, invoke any Python 3 interpreter explicitly. The runner requires `iverilog` and `vvp`, creates simulation artifacts only in the OS temporary directory, and returns nonzero if any test fails. Every invocation also elaborates the seven PPA candidate tops below in synthesis-facing Verilog-2005 mode; this catches source-list and parameter regressions but is not a substitute for Genus synthesis.

The default suite includes a same-stimulus K=1/K=8 comparison. Its light profile must be lossless for both endpoints; its deliberately overloaded profile reports the finite K=1 FIFO loss and latency instead of treating them as hidden backpressure. The 10,000-cycle 8x8 random stress is part of `--extended` because it is substantially slower under Icarus.

## PPA entry points

Use the same 5 ns constraint and 45 nm library as Stage 1:

```text
genus -batch -files syn/run_genus_stage2_tx16_parallel.tcl
genus -batch -files syn/run_genus_stage2_tx16_serial.tcl
genus -batch -files syn/run_genus_stage2_tx16_serial_d128.tcl
genus -batch -files syn/run_genus_stage2_tx16_banked_k2_d32.tcl
genus -batch -files syn/run_genus_stage2_tx16_banked_k4_d8.tcl
genus -batch -files syn/run_genus_stage2_tx16_k4_serial_d32.tcl
genus -batch -files syn/run_genus_stage2_tx64_serial.tcl
```

Map storage is deliberately excluded from the logic comparisons. Report a real SRAM/BRAM macro separately instead of presenting a large resettable flip-flop array as a product memory implementation. Do not compare the four-output K=4-d8 area directly with a one-port K=1 endpoint as though the downstream map interface were identical; use K4-serial-d32 for a one-port comparison, or include the complete banked map fabric for a multi-port comparison.

These scripts produce area/timing reports and a file explicitly named `*_power_vectorless.rpt`. That power number is only a smoke estimate because the scripts do not read switching activity. Final K selection requires a separate trace-driven VCD/SAIF power run and inspection of the mapped FIFO cells; the multi-write batch FIFO is not expected to infer a single-port SRAM.
