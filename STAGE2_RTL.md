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
| `aer_tx16_pose_affine2d_k4_sram_surface` | 4x4 | 4 | four address-striped external SRAM banks | complete K=4 map-control endpoint |
| `aer_tx64_pose_affine2d_serial` | 8x8 (four leaves) | 1 shared | one ready/valid event | tile hierarchy and upper-merge proof |
| `aer_tx64_pose_time_surface` | 8x8 (four leaves) | 1 shared | internal always-ready map writer plus read port | closed sensor-to-map proof |
| `aer_tx64_pose_sram_surface` | 8x8 (four leaves) | 1 shared | external-memory read/modify/write handshake | large-map integration proof |
| `affine_region_pose_loader` | 30x23 coefficient regions | control only | ordered region write plus atomic pose publish | full-sensor configuration-plane proof |
| `aer_tx128_region_pose_affine2d_dual` | 16x8 (two regions) | 1 per region | two independent ready/valid events | real multi-region coefficient/publication proof |

The 4x4 size is a leaf, not a 4x4 window that scans a larger image. Larger physical sensors replicate leaves and assign tile origins. World-grid size is an independent parameter determined by physical coverage and cell resolution. Tile/base origins are static physical configuration and must remain unchanged while reset is deasserted; unlike pose and timestamp, they are not captured per event.

The current 8x8 hierarchy shares one affine coefficient set across its four
4x4 leaves. That is the intended coefficient region, not an accidental
full-sensor-global approximation: the measured physical sweep passes the
geometry gates at 8x8 and first fails the exact-cell-rate gate at 12x12. A
240x180 implementation therefore needs 30x23 independently addressed 8x8
coefficient regions (with a four-row partial edge), plus pose-version-safe
distribution or a calibrated-ray projection stage. The missing piece is that
distribution/update fabric, not smaller AER leaves.

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

For a full sensor, `affine_region_pose_loader` sequences these same local write
ports in strict `(y,x)` raster order. Its ready/valid command operations are
`BEGIN=0`, `WRITE=1`, `PUBLISH=2`, and `ABORT=3`. BEGIN latches a non-active
target pose, 690 committed WRITEs complete the default 30x23 raster, and only a
subsequent PUBLISH changes `active_pose_version`. ABORT discards the incomplete
transaction while keeping the current active pose. Protocol or regional
accounting failures are fail-stop until reset; partially written inactive data
is never published. The wrapper using this controller must own occurrence pose
tagging and block sensor acceptance while `active_pose_valid=0`.

The loader emits one region address and one local pose-write pulse rather than
a 690-bit request vector. `aer_tx128_region_pose_affine2d_dual` proves the
address decode and selected response mux against two real tx64 regions. The
controller-only RTL still does not include the full 690 AER datapaths,
coefficient memories, or routing and must not be presented as their PPA.

The dual wrapper owns occurrence pose tagging. Its pulse-source AER input has
no backpressure pin, so `sensor_ready=0` before the first complete publication
or after any regional accounting error, and `arrival_blocked` reports pulses
presented while not ready. Configuration protocol errors leave an already
published active pose usable. Base X/Y are static; region 1 derives X+8, so the
base plus 15 must fit `SENSOR_W`.

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

`world_time_surface_sram_banked4` stripes valid mapped cells by
`bank=world_x mod 4`, with bank-local `x=floor(world_x/4)`. Four round-robin
arbiters resolve same-bank collisions and four independent writers preserve
parallel progress across different banks. Routing by world coordinate—not by
transform lane—is required so every update to one cell reaches the same
timestamp authority. `GRID_W` must be at least four and divisible by four.
Both grid dimensions must fit signed `COORD_W`, `TIMESTAMP_W` must be at least
two, and an overridden `ADDR_W` must cover `(GRID_W/4)*GRID_H` cells per bank.
There is no hidden router drop or ingress FIFO: a busy destination propagates
backpressure to the affected transform. The current writer still takes a
multi-cycle read/modify/write transaction, so four banks provide concurrency,
not an unconditional sustained four events per cycle.

## Verification

Run the normal suite from the repository root:

```text
python scripts/run_stage2_regression.py
```

Add the original UZH trace and official 50-workload baseline:

```text
python scripts/run_stage2_regression.py --extended
```

Sweep the K=1 FIFO against K=8 while preserving every 1 ms bin in the
checked-in UZH stress trace:

```text
python scripts/run_stage2_regression.py --trace-sweep
```

Sweep the banked K=2/K=4 endpoints and the single-output K=4 endpoint on the
same 1 ms-bin timing:

```text
python scripts/run_stage2_regression.py --lane-sweep
```

Regenerate the measured UZH pose/calibration oracle, compare all 8,503 patch
coordinates with the transform RTL, and probe two adjacent real 8x8 region
datapaths with independently fitted coefficients:

```text
python scripts/run_stage2_regression.py --physical
```

Characterize independent 4x4 and implemented-granularity 8x8 affine regions
over the complete 240x180 image plane at uniform plus trajectory-risk poses,
while also reporting a deliberately rejected full-sensor-global affine
baseline:

```text
python scripts/run_stage2_regression.py --full-sensor-sweep
```

Rebuild the central-patch traffic from the checked-in per-event nanosecond
timestamps, quantize it onto a 5 ns clock, and sweep added external-memory read
response delay through the complete K=4 banked surface:

```text
python scripts/run_stage2_regression.py --memory-sweep
```

`STAGE2_PHYSICAL_MAPPING.md` records the input hashes, quaternion-direction
validation, exact spherical model, measured affine error, and limitations.

The default suite also drives the complete 4x4 K=4 path through identity
mapping and a four-bank SRAM model. It checks concurrent bank progress,
same-cell newer/equal/stale handling, unknown-pose suppression, and final
AER/FIFO/pose-reference drain accounting. The standalone router test adds
same-bank four-way contention plus independent read/write-port stalls.

The older `*.addrpol.txt` UZH inputs were made by binning events at 1 ms. A
runner cycle in the trace/lane sweeps therefore represents one 1 ms bin; when
clocked directly by the RTL it is a useful 200,000-times-compressed burst
stress, not a claim about physical 200 MHz arrival timing. `--memory-sweep`
instead regenerates the schedule from the hashed `eventmeta.tsv`: timestamps
are floored on the absolute 5 ns grid and the first occupied bin is then
rebased to cycle zero. The 8,503 events occupy 8,461 active cycles over
11,064,653,800 hardware cycles; 41
cycles contain simultaneous events and the maximum is three.

The real-time test fast-forwards a long idle interval only after the AER,
FIFO, transforms, pose references, SRAM writers, and memory response model are
all empty. This is cycle-equivalent for the current RTL because it has no
state that advances during a completely idle interval. With a depth-8 FIFO,
identity mapping, always-ready requests, and four independent bank ports, the
measured commit latency in 5 ns cycles is:

| added read-response wait | generated/committed | AER/FIFO loss | mean | p50 | p99 | max |
|---:|---:|---:|---:|---:|---:|---:|
| 0 | 8,503/8,503 | 0/0 | 7 | 7 | 7 | 11 |
| 2 | 8,503/8,503 | 0/0 | 9 | 9 | 9 | 15 |
| 8 | 8,503/8,503 | 0/0 | 15 | 15 | 15 | 27 |
| 32 | 8,503/8,503 | 0/0 | 39 | 39 | 39 | 75 |

All four runs commit `2,080/2,113/2,297/2,013` events to banks 0..3. The
delay parameter is additional wait after the minimum synchronous read
response; request-ready stalls and post-accept write completion are outside
this sweep. The writer interface defines a write handshake as commit. The
latency percentiles cover committed events and must always be read alongside
the loss counters; the test's PASS condition enforces complete accounting, not
zero loss for arbitrary future workloads.

This result is a 200 MHz cycle-level functional workload test, not STA proof
that the synthesized design meets 200 MHz. It also covers only the measured
central 4x4 crop. Identity mapping distributes its X columns across the four
banks favorably, so it does not establish full-240x180 throughput or performance
for a shared-port memory implementation.

The banked endpoint assigns adapter lane `L` to bank `L mod K`. Each bank has its own FIFO and transform, preserves order within that bank, and can be independently backpressured. There is intentionally no total retirement order across banks; consumers use occurrence timestamps for map conflict resolution. The K=4 serialized endpoint adds a stall-safe round-robin merge so its area and loss can be compared fairly with K=1 when the map has only one input port. On the checked-in 1 ms-bin UZH burst stress, it first becomes lossless at depth 32 per bank; K=4 depth 8 is lossless only when all four transform outputs can retire independently.

On a host where `python` is not on `PATH`, invoke any Python 3 interpreter explicitly. The runner requires `iverilog` and `vvp`, creates simulation artifacts only in the OS temporary directory, and returns nonzero if any test fails. Every invocation also elaborates the ten PPA candidate tops below in synthesis-facing Verilog-2005 mode; this catches source-list and parameter regressions but is not a substitute for Genus synthesis.

The default suite includes the region loader at both a 3x2 directed size and
the full 30x23=690 control count. It checks regional stalls, exact write count,
row rollover, complete-generation shadow state, ABORT/restart, early publish,
out-of-order writes, accounting fail-stop, active-ID reuse rejection, and the
old/new event tag boundary on PUBLISH. It also includes a same-stimulus K=1/K=8
comparison. Its light profile must be lossless for both endpoints; its
deliberately overloaded profile reports the finite K=1 FIFO loss and latency
instead of treating them as hidden backpressure. The 10,000-cycle 8x8 random
stress is part of `--extended` because it is substantially slower under
Icarus.

The dual-region end-to-end test loads different coefficients into two real
8x8 regions, rejects pre-publication arrivals explicitly, then checks six
events. An event accepted on the second PUBLISH edge retains pose 0 and its
region-local transform; the following event carries pose 1 and the newly
published transform. Both independent streams must drain without AER/FIFO loss
or pose-accounting error.

The physical dual-region test places those datapaths at sensor coordinates
`x=32..47, y=168..175`. It uses the first checked-in event pose and the
trajectory-risk pose at 53.732373158 s where the full-sensor sweep found its
worst 8x8 float error. Every pixel in both regions is probed at both poses:
256 events match the generated Q14 result bit-for-bit with no AER/FIFO loss.
Against the exact calibrated spherical oracle, 251/256 land in the identical
integer cell and the other five differ by one cell; continuous-Q14 maximum is
0.130578 cell. This is a measured-pose/calibration synthetic pixel probe, not
a claim that the checked-in 4x4 event crop contains traffic at these regions.

## PPA entry points

Use the same 5 ns constraint and 45 nm library as Stage 1:

```text
genus -batch -files syn/run_genus_stage2_tx16_parallel.tcl
genus -batch -files syn/run_genus_stage2_tx16_serial.tcl
genus -batch -files syn/run_genus_stage2_tx16_serial_d128.tcl
genus -batch -files syn/run_genus_stage2_tx16_banked_k2_d32.tcl
genus -batch -files syn/run_genus_stage2_tx16_banked_k4_d8.tcl
genus -batch -files syn/run_genus_stage2_tx16_k4_serial_d32.tcl
genus -batch -files syn/run_genus_stage2_tx16_k4_banked_surface.tcl
genus -batch -files syn/run_genus_stage2_tx64_serial.tcl
genus -batch -files syn/run_genus_stage2_region_pose_loader.tcl
genus -batch -files syn/run_genus_stage2_tx128_dual_region.tcl
```

Map storage is deliberately excluded from the logic comparisons. Report a real SRAM/BRAM macro separately instead of presenting a large resettable flip-flop array as a product memory implementation. Do not compare the four-output K=4-d8 area directly with a one-port K=1 endpoint as though the downstream map interface were identical; use K4-serial-d32 for a one-port comparison, or include the complete banked map fabric for a multi-port comparison.

These scripts produce area/timing reports and a file explicitly named `*_power_vectorless.rpt`. That power number is only a smoke estimate because the scripts do not read switching activity. Final K selection requires a separate trace-driven VCD/SAIF power run and inspection of the mapped FIFO cells; the multi-write batch FIFO is not expected to infer a single-port SRAM. The region-loader script measures only the sequencer, excluding coefficient storage, 690-way routing, and every region datapath. The tx128 script includes two real region datapaths and their local tables, but still excludes a world map and full-sensor merge/routing.
