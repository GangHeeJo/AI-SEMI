#!/usr/bin/env python3
# 원본 NRV DELTA .dvs -> 기존 DVS Viewer h5와 같은 구조(events/{x,y,t,p}, ms_to_idx, t_offset)로 변환.
# 극성: 원본 0=ON -> h5 규약 1=ON. 시각은 첫 이벤트 기준 상대(us). 사용: dvs_to_h5.py <in.dvs> <out.h5>
import os
import sys

import h5py
import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "external"))
from hyunsu_decode_dvs import decode

ev, st = decode(sys.argv[1]); print(st)
ev = ev[ev.t > 1_000_000]                      # 첫 타임스탬프 단어 이전 이벤트(시각 0으로 채워짐, 이 파일에서 39개)는 버림
o = np.lexsort((ev.x, ev.t, ev.frame)); t0 = int(ev.t.min())
t = (ev.t[o] - t0).astype(np.uint32); x = ev.x[o].astype(np.uint16); y = ev.y[o].astype(np.uint16); p = (1 - ev.p[o]).astype(np.uint8)
assert (np.diff(t.astype(np.int64)) >= 0).all(), "time not monotonic"
ms = np.searchsorted(t, np.arange(int(t[-1] // 1000) + 2) * 1000).astype(np.uint64)
with h5py.File(sys.argv[2], "w") as f:
    g = f.create_group("events"); g.attrs["height"] = 720; g.attrs["width"] = 960
    g.attrs["polarity_encoding"] = b"1=ON (brightness increase), 0=OFF"; g.attrs["source"] = b"DELTA(.dvs decoded)"
    for k, v in (("x", x), ("y", y), ("t", t), ("p", p)): g.create_dataset(k, data=v)
    f.create_dataset("ms_to_idx", data=ms); f.create_dataset("t_offset", data=t0)
print("events", len(t), "duration s", t[-1] / 1e6, "distinct timestamps", len(np.unique(t[:2000000])))
