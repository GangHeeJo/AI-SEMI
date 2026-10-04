#!/usr/bin/env python3
# §190: pan 상대 3D 점 구름. 일치 이벤트의 모자이크 좌표 (X,Y) = 시차 층 lambda로 되돌린 위치, 깊이 = lambda(상대 깊이 대용, 부호 미확정).
# 사용: pan_export3d.py <events.h5> <track.npy> <gate_prefix> <out_prefix> [stride]
import sys

import h5py
import numpy as np

from viewer3d import write_viewer

h5p, trk, pre, out = sys.argv[1:5]; stride = int(sys.argv[5]) if len(sys.argv) > 5 else 4
E = np.load(pre + "_ev.npz"); ag = E["agree"]; lam = (E["lam_every"] if "lam_every" in E.files else E["lam"]).astype(np.float64)       # 일치 이벤트의 lam은 두 경우 모두 연속 lambda
f = h5py.File(h5p, "r"); t = f["events/t"][::stride].astype(np.float64)[: len(ag)]; x = f["events/x"][::stride].astype(np.float64)[: len(ag)]; y = f["events/y"][::stride].astype(np.float64)[: len(ag)]; tr = np.load(trk)
px = np.interp(t, tr[:, 0], tr[:, 1]); py = np.interp(t, tr[:, 0], tr[:, 2])
if "x0y0" in E.files: x0, y0 = E["x0y0"]
else: x0 = min((x + l * px).min() for l in (0.70, 1.30)) - 1; y0 = min((y + l * py).min() for l in (0.70, 1.30)) - 1               # pan_depthsnap_gate.py와 같은 캔버스 원점 규칙(격자 양 끝 lambda)
X = x + lam[: len(x)] * px - x0; Y = y + lam[: len(x)] * py - y0
m = ag[: len(x)]; print(f"agreed events {m.sum()} of {len(x)}"); write_viewer(X[m], Y[m], lam[: len(x)][m], out, "Relative 3D world map (pan)", "depth = shift-ratio lambda; sign of nearness not determined")
