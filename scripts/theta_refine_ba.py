#!/usr/bin/env python3
# §192: 깊이 층을 이용한 θ 정밀화. θ'(t) = θ(t) + δ(t), δ는 KNOT_MS 간격 매듭의 모자 함수 보간. 목적함수 = 타일(48px)별 최고 층의 겹침 sum c^2 합
# (delta_calibrate_refine.score와 같은 응집도; 모든 층이 같은 이벤트를 쓰고 회전은 면적을 안 바꿔 편향 없음). 매듭마다 +-step 좌표 하강, 영향받는 이벤트만 증분 갱신.
# 첫 매듭 고정(전체 회전 상수는 목적함수에 영향 없음), |δ| <= CAP. 사용: theta_refine_ba.py <events.h5> <theta.npy> <calib.json> <out.npy> [truth.npz]  (DELTA_RHO: 열 순차 읽기 보정)
import json
import os
import sys

import h5py
import numpy as np

TILE, C = 48, 1680; OFF = C / 2; NT = C // TILE
KNOT_MS, CAP_DEG, STEPS, T_RANGE, STRIDE = 20, 8.0, (1.0, 0.5, 0.25, 0.1), (300, 1500), 8
RHO = float(os.environ.get("DELTA_RHO", "0"))


def run(h5p, th_npy, cal_json, out, truth=None):
    cal = json.load(open(cal_json)); e = np.array(cal["unit_vector"]); c0 = np.array(cal["center_px"]); step = float(cal["layer_step_px"]) / 3.0
    ss = np.arange(cal["s_min_px"] - 20, cal["s_max_px"] + 60, max(step, 12.0)); K = len(ss)
    th = np.load(th_npy); mids = np.arange(len(th)) * 4 + 2.0; f = h5py.File(h5p, "r"); m = f["ms_to_idx"][:].astype(np.int64); s0, s1 = m[T_RANGE[0]], m[T_RANGE[1]]
    x = f["events/x"][s0:s1:STRIDE].astype(np.float64); y = f["events/y"][s0:s1:STRIDE].astype(np.float64); t = f["events/t"][s0:s1:STRIDE].astype(np.float64) / 1e3 + (f["events/x"][s0:s1:STRIDE].astype(np.float64) / 960 - 0.5) * RHO * 0.773
    tk = np.arange(T_RANGE[0], T_RANGE[1] + KNOT_MS, KNOT_MS, dtype=float); nk = len(tk); delta = np.zeros(nk); a = -np.interp(t, mids, th); N = len(x)
    def ids(sel, ang, k):
        px = x[sel] - c0[0] - ss[k] * e[0]; py = y[sel] - c0[1] - ss[k] * e[1]; c, sn = np.cos(ang), np.sin(ang)
        xi = np.rint(c * px - sn * py + OFF).astype(np.int64); yi = np.rint(sn * px + c * py + OFF).astype(np.int64); ok = (xi >= 0) & (xi < C) & (yi >= 0) & (yi < C)
        return np.where(ok, yi * C + xi, -1)
    Cnt = np.zeros((K, C * C), np.float32)
    for k in range(K):
        i = ids(slice(None), a, k); Cnt[k] = np.bincount(i[i >= 0], minlength=C * C)
    tile_of = (np.arange(C * C) // C // TILE) * NT + (np.arange(C * C) % C) // TILE
    Tt = np.stack([np.bincount(tile_of, weights=Cnt[k].astype(np.float64) ** 2, minlength=NT * NT) for k in range(K)])
    obj = lambda T: float(T.max(0).sum() / N ** 2 * 1e6)
    sel_k = [np.nonzero(np.abs(t - tk[j]) < KNOT_MS)[0] for j in range(nk)]; w_k = [1 - np.abs(t[s] - tk[j]) / KNOT_MS for j, s in enumerate(sel_k)]
    print(f"events {N}, layers {K}, knots {nk}, start objective {obj(Tt):.4f}", flush=True)
    for p in range(2):
        moved = 0
        for st in STEPS:
            for j in range(1, nk):
                sel = sel_k[j]
                if len(sel) == 0: continue
                for sgn in (1, -1):
                    if abs(delta[j] + sgn * st) > CAP_DEG: continue
                    dd = np.radians(sgn * st); a_new = a[sel] - w_k[j] * dd; dT = np.zeros((K, NT * NT)); pend = []
                    for k in range(K):
                        o = ids(sel, a[sel], k); n_ = ids(sel, a_new, k); cell = np.concatenate([o[o >= 0], n_[n_ >= 0]]); wt = np.concatenate([-np.ones((o >= 0).sum()), np.ones((n_ >= 0).sum())])
                        u, inv = np.unique(cell, return_inverse=True); d = np.bincount(inv, weights=wt); cu = Cnt[k][u]; dT[k] = np.bincount(tile_of[u], weights=2 * cu * d + d * d, minlength=NT * NT); pend.append((u, d))
                    if obj(Tt + dT) > obj(Tt) * (1 + 1e-9):
                        for k, (u, d) in enumerate(pend): Cnt[k][u] += d.astype(np.float32)
                        Tt += dT; a[sel] = a_new; delta[j] += sgn * st; moved += 1; break
        print(f"pass {p}: moves {moved}, objective {obj(Tt):.4f}, max|delta| {np.abs(delta).max():.2f} deg", flush=True)
    d_win = np.interp(mids, tk, delta, left=0.0, right=delta[-1]); th_new = th + np.radians(d_win); np.save(out, th_new)
    if truth is not None:
        tt = np.load(truth)["theta"]; mm = (mids >= T_RANGE[0]) & (mids <= T_RANGE[1])
        for nm, v in (("start", th), ("refined", th_new)):
            d = np.degrees(v[:len(tt)] - tt[:len(v)]); d = d - d[mm[:len(d)]][0]; print(f"  theta error vs truth, {nm:8s}: rms {np.sqrt((d[mm[:len(d)]] ** 2).mean()):.2f} deg, max {np.abs(d[mm[:len(d)]]).max():.2f} deg")


if __name__ == "__main__":
    run(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5] if len(sys.argv) > 5 else None)
