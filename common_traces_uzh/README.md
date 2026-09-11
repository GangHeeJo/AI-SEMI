# UZH event-camera data provenance

The inputs in this directory are derivatives of the University of Zurich
Robotics and Perception Group Event-Camera Dataset and Simulator:

- dataset page: <https://rpg.ifi.uzh.ch/davis_data.html>
- sequence: `shapes_rotation` (DAVIS 240C, 240x180)
- citation: E. Mueggler, H. Rebecq, G. Gallego, T. Delbruck, and
  D. Scaramuzza, "The Event-Camera Dataset and Simulator: Event-based Data for
  Pose Estimation, Visual Odometry, and SLAM," IJRR 36(2), 2017.
- upstream license: CC BY-NC-SA 3.0; the dataset page limits use to the terms
  of that license, including non-commercial use and share-alike obligations.

The original `shapes_rotation` text archive is not committed. Its extracted
`events.txt` is about 510 MB and exceeds ordinary GitHub file limits. Prepare
it separately from the official source under repository-root
`shapes_rotation/events.txt`; that directory is ignored by Git.

The full-sensor traffic tools pin the locally verified original as:

```text
path: shapes_rotation/events.txt
bytes: 509907771
sha256: d0b66503613354d1d274c56c979dfd89ba80b256c31eaba459a52adb7d03ffda
events: 23126288
sensor: 240x180
timestamp range: 0.000000000 .. 59.798386001 s
```

The upstream site does not publish a checksum for the extracted file, so this
SHA-256 is this repository's receipt for the verified local copy, not an
upstream-authenticated digest. Do not commit the original archive, extracted
dataset, or a full per-event derived trace. Small derivatives in this
directory retain the upstream attribution and license obligations.
