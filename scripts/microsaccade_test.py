#!/usr/bin/env python3
# §217: 미세 안구운동(microsaccade) 시험. 월드 칸을 s x s 픽셀로 거칠게 하고(메모리 1/s^2), 프레임마다 알려진 부화소 지터(+-s/2, 균등)를 더해 칸에 누적하면 칸의 카운트가 가장자리의 부화소 위치를 담는지.
# 기준 = 1 px 해상도 지도(지터 없음). 복원 = 거친 지도를 s배 업샘플(쌍선형)해 1 px 지도와의 밴드패스 NCC. 카운터 폭은 포화 비트로 제한(4비트 = 15).
# 비교: (a) 지터 없음, (b) 프레임마다 무작위 지터, 둘 다 같은 이벤트. 사용: microsaccade_test.py <events.h5> <theta.npy> <calib.json>
import sys

import h5py
import numpy as np
from scipy import ndimage as ndi

sys.path.insert(0, "scripts")
from delta_depthwarp2 import load_cal  # noqa: E402

C, OFF, R0 = 1200, 600.0, 420
_, c0, _, _ = load_cal(sys.argv[3]); th = np.load(sys.argv[2]); mids = (np.arange(len(th)) * 4 + 2) * 1e3
f = h5py.File(sys.argv[1], "r"); i0 = int(f["events/t"].shape[0] * 0.4); sl = slice(i0, i0 + 8000000)
x = f["events/x"][sl].astype(np.float64); y = f["events/y"][sl].astype(np.float64); t = f["events/t"][sl].astype(np.float64)
a = -np.interp(t, mids, th); px = x - c0[0]; py = y - c0[1]; c, s_ = np.cos(a), np.sin(a)
u = c * px - s_ * py + OFF; v = s_ * px + c * py + OFF; _, fid = np.unique(t, return_inverse=True)
yy, xx = np.mgrid[:C, :C]; mask = np.hypot(xx - OFF, yy - OFF) <= R0
bp = lambda m: ndi.gaussian_filter(m, 1.0) - ndi.gaussian_filter(m, 6.0)


def ncc(a_, b_):
    p = a_[mask] - a_[mask].mean(); q = b_[mask] - b_[mask].mean(); return float((p * q).sum() / (np.linalg.norm(p) * np.linalg.norm(q) + 1e-12))


ref = np.zeros((C, C)); ix = np.rint(u).astype(np.int64); iy = np.rint(v).astype(np.int64); ok = (ix >= 0) & (ix < C) & (iy >= 0) & (iy < C)
np.add.at(ref, (iy[ok], ix[ok]), 1.0); Bref = bp(ref)
rng = np.random.default_rng(1); nfr = fid.max() + 1
print(f"events {len(t)}, frames {nfr}; reference = 1 px map (no jitter)")
print(f"{'cell s':>7s} {'counter':>8s} {'no jitter NCC':>14s} {'jitter NCC':>11s} {'memory vs 1px (2 bit/px)':>26s}")
for s in (2, 4, 8):
    for cap in (1, 15):                                     # 1 = valid 비트만, 15 = 4비트 포화 카운터
        res = []
        for jit in (False, True):
            jx = (rng.random(nfr) - 0.5) * s if jit else np.zeros(nfr); jy = (rng.random(nfr) - 0.5) * s if jit else np.zeros(nfr)
            cx = np.floor((u + jx[fid]) / s).astype(np.int64); cy = np.floor((v + jy[fid]) / s).astype(np.int64); n = C // s
            ok2 = (cx >= 0) & (cx < n) & (cy >= 0) & (cy < n); m = np.zeros((n, n)); np.add.at(m, (cy[ok2], cx[ok2]), 1.0); m = np.minimum(m, cap)
            up = ndi.zoom(m, s, order=1)[:C, :C]; up = np.pad(up, ((0, C - up.shape[0]), (0, C - up.shape[1]))); res.append(ncc(bp(up), Bref))
        bits = 1 if cap == 1 else 4; print(f"{s:7d} {bits:>7d}b {res[0]:14.3f} {res[1]:11.3f} {bits / (s * s) / 2 * 100:22.1f}%")
