#!/usr/bin/env python3
# §187: roll 영상의 상대 3D 맵. 이벤트마다 월드 좌표 (u,v)(회전을 되돌린 공통 좌표)와 상대 깊이 s(오프셋 직선 위 위치, px 단위; 절대 거리 아님)를 합쳐 3D 점 (u,v,s)를 만든다.
# + 구조 제약: (u,v,s) 공간에서 순차 RANSAC으로 평면(바닥은 경사 평면, 벽/케이지는 s 일정 평면)을 영상에서 추정하고,
#   평면 허용오차(층 간격 = FWHM/6) 안의 이벤트 깊이를 평면 값으로 맞춘다(그 밖의 이벤트는 그대로).
# 출력: 3D 점(npz), 깊이 색 지도, 깊이-가로(u-s) 단면도, 가상 시점 이동 렌더(상대 시차).
# 사용: roll_relative3d.py <events.h5> <theta.npy> <calib.json> <diag_prefix> <out_prefix> [truth.npz]
import json
import os
import sys

import h5py
import numpy as np

os.environ.setdefault("DELTA_RHO", "0")
from delta_depthsnap import chunks_t  # noqa: E402

W_PX, H_PX = 960, 720


def load(h5p, th_npy, cal_json, diag):
    cal = json.load(open(cal_json)); e = np.array(cal["unit_vector"]); c0 = np.array(cal["center_px"]); step = float(cal["fwhm_median_px"]) / 6.0
    th = np.load(th_npy); mids = (np.arange(len(th)) * 4 + 2) * 1e3; f = h5py.File(h5p, "r")
    X, Y, A = [], [], []
    for x, y, a, t in chunks_t(f, th, mids): X.append(x); Y.append(y); A.append(a)
    ss = np.load(diag + "_ss.npy"); s = np.load(diag + "_diag_s.npy").astype(np.float64); fl = np.load(diag + "_diag_flag.npy")
    C = int(2 * (0.5 * np.hypot(W_PX, H_PX) + max(abs(ss[0]), abs(ss[-1])))) // 2 * 2
    return np.concatenate(X), np.concatenate(Y), np.concatenate(A), s, fl, e, c0, step, C


def uv(x, y, a, s, e, c0):
    px = x - c0[0] - s * e[0]; py = y - c0[1] - s * e[1]; c, sn = np.cos(a), np.sin(a)
    return c * px - sn * py, sn * px + c * py


def ransac_planes(u, v, s, tol, max_planes=8, min_share=0.015, iters=500, seed=0):
    rng = np.random.default_rng(seed); n0 = len(u); planes = []; idx = np.arange(n0)
    for _ in range(max_planes):
        if len(idx) < min_share * n0: break
        sub = idx if len(idx) <= 200000 else rng.choice(idx, 200000, replace=False); best = (0, None)
        for _i in range(iters):
            k = rng.choice(len(sub), 3, replace=False); P = np.c_[np.ones(3), u[sub[k]], v[sub[k]]]
            try: abc = np.linalg.solve(P, s[sub[k]])
            except np.linalg.LinAlgError: continue
            inl = np.abs(s[sub] - (abc[0] + abc[1] * u[sub] + abc[2] * v[sub])) < tol
            if inl.sum() > best[0]: best = (inl.sum(), abc, inl)
        if best[1] is None or best[0] < min_share * n0 * len(sub) / len(idx): break
        sel = sub[best[2]]; A = np.c_[np.ones(len(sel)), u[sel], v[sel]]; abc = np.linalg.lstsq(A, s[sel], rcond=None)[0]          # 내부점으로 최소제곱 재적합
        planes.append(abc); keep = np.abs(s[idx] - (abc[0] + abc[1] * u[idx] + abc[2] * v[idx])) >= tol; idx = idx[keep]
    return planes


def snap(x, y, a, s, e, c0, planes, tol, iters=2):
    s = s.copy()
    for _ in range(iters):
        u, v = uv(x, y, a, s, e, c0); res = np.stack([np.abs(s - (p[0] + p[1] * u + p[2] * v)) for p in planes]); k = res.argmin(0); ok = res[k, np.arange(len(s))] < tol
        pv = np.stack([p[0] + p[1] * u + p[2] * v for p in planes])[k, np.arange(len(s))]; s = np.where(ok, pv, s)
    return s


if __name__ == "__main__":
    h5p, th, cal, diag, out = sys.argv[1:6]; truth = sys.argv[6] if len(sys.argv) > 6 else None
    x, y, a, s, fl, e, c0, tol, C = load(h5p, th, cal, diag); OFF = C / 2; m = np.isfinite(s) & (fl > 0); print(f"events {len(x)}, with depth {m.sum()} (agreed {np.sum(fl == 1)}, propagated {np.sum(fl == 2)}), canvas {C}, tol {tol:.1f}px", flush=True)
    ag = fl == 1; u, v = uv(x, y, a, np.where(ag, s, 0.0), e, c0); planes = ransac_planes(u[ag], v[ag], s[ag], tol)
    print(f"planes found: {len(planes)}"); [print(f"  plane {i}: s = {p[0]:.1f} + {p[1]:+.4f} u + {p[2]:+.4f} v") for i, p in enumerate(planes)]
    s2 = s.copy(); s2[m] = snap(x[m], y[m], a[m], s[m], e, c0, planes, tol) if planes else s[m]
    np.savez(out + "_points.npz", s_raw=s.astype(np.float32), s_plane=s2.astype(np.float32), flag=fl, planes=np.array(planes), tol=tol)
    def place(sv, sel):
        uu, vv = uv(x[sel], y[sel], a[sel], sv[sel], e, c0); p = np.rint(vv + OFF).astype(np.int64) * C + np.rint(uu + OFF).astype(np.int64); p = p[(p >= 0) & (p < C * C)]
        return np.bincount(p, minlength=C * C).reshape(C, C).astype(np.float32)
    Fa = place(s, ag); Fb = place(s2, ag); Fc = place(s, m); Fd = place(s2, m)
    np.save(out + "_map_raw_agree.npy", Fa); np.save(out + "_map_plane_agree.npy", Fb); np.save(out + "_map_raw_all.npy", Fc); np.save(out + "_map_plane_all.npy", Fd)
    changed = m & (np.abs(s2 - s) > 1e-6); print(f"events snapped to a plane: {changed.sum()} ({changed.sum() / m.sum() * 100:.1f}% of depth events)")
    if truth:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); from ghost_metric import ghost
        T = dict(np.load(truth)); st = h5py.File(h5p, "r")["events/s_true"][::2].astype(np.float64)[:len(s)]
        te = np.array([np.cos(np.radians(float(T["e_deg"]))), np.sin(np.radians(float(T["e_deg"])))]); c0t = T["c0"]; s_exp = ((c0t - c0)[None, :] + np.maximum(st, 0)[:, None] * te[None, :]) @ e
        print(f"{'variant':32s}{'NCC':>7s}{'ghost %':>9s}{'cover %':>9s}   depth error |s - s_expected| median / p90 (px), accuracy within 1 layer")
        for nm, M, sv, sel in (("agreed, raw depth", Fa, s, ag), ("agreed, plane-snapped", Fb, s2, ag), ("agreed+propagated, raw", Fc, s, m), ("agreed+propagated, plane-snapped", Fd, s2, m)):
            pr, cv, n, _ = ghost(M, T); ok = sel & (st >= 0); er = np.abs(sv[ok] - s_exp[ok]); print(f"{nm:32s}{n:7.3f}{(1 - pr) * 100:9.1f}{cv * 100:9.1f}   {np.median(er):6.1f} / {np.percentile(er, 90):6.1f}   {np.mean(er <= tol) * 100:5.1f}%")
        fl_ok = ag & (st >= 120) & (st <= 230)
        print(f"floor events (true s 120-230): depth error median raw {np.median(np.abs(s[fl_ok] - s_exp[fl_ok])):.1f}px -> snapped {np.median(np.abs(s2[fl_ok] - s_exp[fl_ok])):.1f}px")
