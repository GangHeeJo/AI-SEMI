#!/usr/bin/env python3
# §148: delta_rotation_cmax.py의 omega 적분(예측, ~20도 드리프트)을 월드맵 정합으로 미세 보정.
# 창마다 theta = theta_prev + omega*dt 를 중심으로 +-SEARCH_DEG를 탐색, 이벤트를 월드맵에 투영해
# "지금까지 쌓인 맵(가우시안 블러)"과 가장 잘 겹치는 각도를 채택(causal, 미래 정보 없음) 후 맵에 누적.
import sys

import h5py
import numpy as np
from scipy import ndimage as ndi

from delta_rotation_cmax import CX, CY, DROP, H5, WIN_MS

CANVAS = 1200
SEARCH_DEG = 1.5
STEP_DEG = 0.25
SUB = 20000
SIGMA = 2.0


def project(x, y, a, off):
    c, s = np.cos(a), np.sin(a)
    xi = np.rint(c * x - s * y + off).astype(np.int64)
    yi = np.rint(s * x + c * y + off).astype(np.int64)
    ok = (xi >= 0) & (xi < CANVAS) & (yi >= 0) & (yi < CANVAS)
    return xi, yi, ok


def track(res, seed=0, center=(CX, CY)):
    rng = np.random.default_rng(seed)
    f = h5py.File(H5, "r")
    m = f["ms_to_idx"][:].astype(np.int64)
    off = CANVAS / 2
    world = np.zeros((CANVAS, CANVAS), np.float32)
    blurred = world.copy()
    cands = np.radians(np.arange(-SEARCH_DEG, SEARCH_DEG + 1e-9, STEP_DEG))
    theta_prev, thetas = 0.0, []  # 창 시작 시각의 theta
    for w, row in enumerate(res):
        s, e = m[w * WIN_MS], m[(w + 1) * WIN_MS]
        om = row[1]
        theta_mid_pred = theta_prev + om * WIN_MS * 1e-3 / 2
        best_d = 0.0
        n = e - s
        if n >= 5000:
            pool = np.flatnonzero(rng.random(n) >= DROP)
            idx = np.sort(rng.choice(pool, min(SUB, len(pool)), replace=False))
            x = f["events/x"][s:e][idx].astype(np.float64) - center[0]
            y = f["events/y"][s:e][idx].astype(np.float64) - center[1]
            t = f["events/t"][s:e][idx].astype(np.float64) * 1e-6
            dt = t - (w * WIN_MS + WIN_MS / 2) * 1e-3
            if blurred.max() > 0:
                best = -1.0
                for d in sorted(cands, key=abs):  # 동점이면 d=0에 가까운 쪽(§145 교훈)
                    xi, yi, ok = project(x, y, -(theta_mid_pred + d + om * dt), off)
                    sc = float(blurred[yi[ok], xi[ok]].sum()) / len(x)
                    if sc > best + 1e-9:
                        best, best_d = sc, d
        theta_mid = theta_mid_pred + best_d
        theta_prev = theta_mid + om * WIN_MS * 1e-3 / 2
        thetas.append(theta_mid)
        if n >= 5000:
            xa = f["events/x"][s:e].astype(np.float64) - center[0]
            ya = f["events/y"][s:e].astype(np.float64) - center[1]
            ta = f["events/t"][s:e].astype(np.float64) * 1e-6
            keep = rng.random(n) >= DROP
            xa, ya, ta = xa[keep], ya[keep], ta[keep]
            dta = ta - (w * WIN_MS + WIN_MS / 2) * 1e-3
            xi, yi, ok = project(xa, ya, -(theta_mid + om * dta), off)
            world += np.bincount(yi[ok] * CANVAS + xi[ok], minlength=CANVAS * CANVAS).reshape(CANVAS, CANVAS).astype(np.float32)
            blurred = ndi.gaussian_filter(np.log1p(world), SIGMA)
    return np.array(thetas), world


if __name__ == "__main__":
    import json
    res = np.load(sys.argv[1])
    center = tuple(json.load(open(sys.argv[3]))["center_px"]) if len(sys.argv) > 3 else (CX, CY)  # 보정 JSON의 회전 중심
    print("rotation center used:", center)
    th, world = track(res, center=center)
    np.save(sys.argv[2] + "_theta.npy", th)
    np.save(sys.argv[2] + "_world.npy", world)
    pred = np.cumsum(res[:, 1] * WIN_MS * 1e-3) - res[:, 1] * WIN_MS * 1e-3 / 2
    print("final theta refined(deg):", np.degrees(th[-1]), " pure-omega-integral(deg):", np.degrees(pred[-1]))
    print("max |refined-pred| deg:", np.degrees(np.abs(th - pred)).max())
