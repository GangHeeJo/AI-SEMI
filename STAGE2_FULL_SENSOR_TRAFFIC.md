# Stage-2 full-sensor traffic checkpoint

## Scope

This checkpoint answers one architecture question before replicating RTL:
how much shared transform capacity is required by the complete 240x180 UZH
`shapes_rotation` event stream at a 200 MHz design clock?

It is a measured workload characterization, not a universal automotive sensor
specification. The recording is a DAVIS 240C viewing simple wall shapes under
rotation. Its timestamps have roughly 1 us granularity, so placing them on a
5 ns grid preserves order and equal timestamps but does not create 5 ns sensor
measurement precision.

## Input receipt

The original file is prepared separately at `shapes_rotation/events.txt` and
is not committed:

```text
bytes     509907771
sha256    d0b66503613354d1d274c56c979dfd89ba80b256c31eaba459a52adb7d03ffda
events    23126288
time      0.000000000 .. 59.798386001 s
format    timestamp_seconds x y polarity
sensor    240x180
```

`common_traces_uzh/README.md` records the official UZH source, citation, and
CC BY-NC-SA 3.0 license. The official page does not publish an extracted-file
checksum; this digest pins the verified local copy rather than claiming an
upstream-authenticated hash.

## Measured arrival envelope

The analyzer parses decimal timestamps exactly as integer nanoseconds and
checks monotonic time, coordinate/polarity range, raw SHA-256, and count
conservation.

| metric | full 240x180 | old central 4x4 crop |
|---|---:|---:|
| events | 23,126,288 | 8,503 |
| fraction of full traffic | 100% | 0.03677% |
| mean event rate | 386,738/s | 142.2/s |
| active 5 ns bins | 18,119,595 | 8,461 |
| bins with simultaneous events | 4,273,348 | 41 |
| maximum events in one bin | 8 | 3 |
| same-pixel events in one bin | 0 | 0 |

The full/crop event ratio is 2,719.78, close to the 2,700 pixel-count ratio.
The crop represents mean spatial density reasonably, but it does not represent
the full sensor's simultaneous multi-region traffic.

Across the first through last 1 ms bin, including 21 empty bins, the nearest-
rank p99 is 803 events and the maximum is 1,100 events in the bin beginning at
41.321 s. The source's minimum positive timestamp separation is 999 ns; equal
timestamps form the simultaneous batches used below.

## Spatial partition envelope

| partition | count | max events in one partition/5 ns bin | per-partition total min/p50/p99/max |
|---|---:|---:|---:|
| 4x4 AER leaf | 60x45 = 2,700 | 4 | 1,701 / 8,388 / 16,505 / 17,736 |
| 8x8 coefficient region | 30x23 = 690 | 5 | 7,243 / 32,816 / 65,431 / 68,511 |

The last 30 coefficient regions are 8x4 because the sensor height is 180.
Only 744 leaf/bin pairs contain more than two events: 737 contain three and
seven contain four. At 8x8 granularity, 3,005 region/bin pairs exceed two and
only two exceed four. No same-pixel 5 ns collision occurs. Together with the
roughly 200-cycle minimum gap between distinct timestamp batches, this gives the
existing depth-2-per-source 4x4 leaf ample time to drain on this recording;
it is not a proof for a different sensor or scene.

## Shared-transform capacity

The event-driven queue model enqueues an equal-timestamp batch in file order.
If idle, one event starts in that same cycle; subsequent starts are separated
by a fixed initiation interval (II). Queue occupancy is measured after that
same-cycle start and excludes the event in service.

| shared server II | p99 start latency | max start latency | peak waiting | depth 8/16/32 loss |
|---:|---:|---:|---:|---:|
| 1 | 2 cycles / 10 ns | 7 / 35 ns | 7 | 0 / 0 / 0 |
| 2 | 4 / 20 ns | 14 / 70 ns | 7 | 0 / 0 / 0 |
| 4 | 8 / 40 ns | 28 / 140 ns | 7 | 0 / 0 / 0 |
| 8 | 16 / 80 ns | 56 / 280 ns | 7 | 0 / 0 / 0 |

No II point overlaps the following timestamp batch. Thus this recording does
not justify 690 replicated affine datapaths: one shared K=1 transform and
eight total waiting slots are sufficient before external-memory backpressure
is considered. K is still parameterized, but K>1 should be added only when a
broader workload, downstream stalls, or timing closure demonstrates need.

## Architecture consequence

For a sensor chip whose internal pixels present parallel pulses, the next
scalable path is:

```text
2,700 x 4x4 occurrence-aware AER leaf
  -> 690 x 8x8 region stream carrying region_id
  -> stall-safe four-way merge tree
  -> shared FIFO depth 8
  -> central two-epoch region coefficient table
  -> one affine transform
  -> existing four-bank world-time surface
```

The event record retains global sensor coordinates for the first proof:

```text
{region_id, sensor_x, sensor_y, polarity, pose_version,
 occurrence_timestamp}
```

The 690 local affine engines in the earlier scale-out sketch are therefore not
the implementation target. The region loader's atomic `BEGIN -> 690 WRITE ->
PUBLISH` protocol remains useful, but it writes two central `690 x 112-bit`
coefficient epochs. A count-based two-epoch guard must cover accepted events
from occurrence until coefficient/event capture; a pose slot cannot be
overwritten on its last-retire edge.

For a 5 ns cycle timestamp, the measured 59.798386001 s span requires at
least 35 bits under the map writer's stricter half-range modular-order rule;
34 bits can encode the absolute span but its half-range is only about 42.95 s.
Verification may keep 64 bits, but a narrower product counter must preserve
this ordering contract.

The minimum integrated RTL proof is four real 8x8 regions (16x16, 256 sources)
feeding one shared affine lane and the existing banked memory boundary. A
separate synthetic 16-input, two-level merge test can prove hierarchy without
replicating real sensor datapaths merely for simulation.

If the product instead receives an already serialized `(x,y,polarity,time)`
stream from a commercial DAVIS-like sensor, the 2,700 AER leaves are not part
of the accelerator at all. It should derive `region_id` from the incoming
address and enter at the shared queue. These are distinct product boundaries
and their PPA must not be mixed.

## Reproduce

```text
python scripts/test_analyze_uzh_full_sensor_traffic.py
python scripts/analyze_uzh_full_sensor_traffic.py \
  --events shapes_rotation/events.txt \
  --output full_sensor_traffic.json
```

The full JSON receipt is generated locally and is intentionally not tracked.
The analyzer uses only the Python standard library.
