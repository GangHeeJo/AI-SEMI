#!/usr/bin/env python3
# §215: 실제 DELTA 이벤트를 θ로 월드 캔버스(1200x1200, s=0)에 보낸 뒤 64x64 칸으로 나눠 "x y pol" 텍스트로 내보낸다(RTL 테스트벤치 입력).
# 사용: export_delta_cells.py <events.h5> <theta.npy> <calib.json> <out.txt> [n=128000] [start_frac=0.4]
import sys

import h5py
import numpy as np

sys.path.insert(0, "scripts")
from delta_depthwarp2 import load_cal  # noqa: E402

C, OFF = 1200, 600.0
h5p, th_npy, cal_json, out = sys.argv[1:5]; n = int(sys.argv[5]) if len(sys.argv) > 5 else 128000; start = float(sys.argv[6]) if len(sys.argv) > 6 else 0.4
_, c0, _, _ = load_cal(cal_json); th = np.load(th_npy); mids = (np.arange(len(th)) * 4 + 2) * 1e3
f = h5py.File(h5p, "r"); i0 = int(f["events/t"].shape[0] * start); sl = slice(i0, i0 + 4 * n)
x = f["events/x"][sl].astype(np.float64); y = f["events/y"][sl].astype(np.float64); t = f["events/t"][sl].astype(np.float64); p = f["events/p"][sl].astype(np.int64)
a = -np.interp(t, mids, th); px = x - c0[0]; py = y - c0[1]; c, s_ = np.cos(a), np.sin(a)
xi = np.rint(c * px - s_ * py + OFF).astype(np.int64); yi = np.rint(s_ * px + c * py + OFF).astype(np.int64); ok = (xi >= 0) & (xi < C) & (yi >= 0) & (yi < C)
xc = (xi[ok] * 64 // C)[:n]; yc = (yi[ok] * 64 // C)[:n]; pp = p[ok][:n]
np.savetxt(out, np.stack([xc, yc, pp], 1), fmt="%d"); print(f"wrote {len(xc)} events, {len(np.unique(yc * 64 + xc))} distinct cells -> {out}")
