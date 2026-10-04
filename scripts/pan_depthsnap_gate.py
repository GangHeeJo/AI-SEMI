#!/usr/bin/env python3
# §183: pan 시차 층 선택 + 신뢰도 게이팅. 40ms 블록을 3그룹(블록 번호 mod 3)으로 나눠 그룹 g의 이벤트는 나머지 두 그룹의 선명도 지도(Va, Vb)로 층을 각각 고른다.
# 두 선택이 +-1층 안에서 일치하면 합산 점수의 포물선 보간 연속 lambda 위치, 아니면 버리지 않고 기준선(lambda=1) 위치에 둔다.
# 사용: pan_depthsnap_gate.py <events.h5> <track.npy> <out_prefix>
import os
import sys

import h5py
import numpy as np

import delta_depthwarp2 as dw2
from delta_depthwarp2 import sharp_of

LAMS = np.round(np.arange(0.70, 1.3001, 0.01), 3); STRIDE, CH = int(os.environ.get("PAN_STRIDE", "4")), 1_000_000


def run(h5p, trk, out):
    dw2.SIGMA_SHARP = 3.0
    f = h5py.File(h5p, "r"); t = f["events/t"][::STRIDE].astype(np.float64); x = f["events/x"][::STRIDE].astype(np.float64); y = f["events/y"][::STRIDE].astype(np.float64)
    tr = np.load(trk); px = np.interp(t, tr[:, 0], tr[:, 1]); py = np.interp(t, tr[:, 0], tr[:, 2]); K = len(LAMS); grp = ((t // 40000).astype(np.int64) % 3)
    x0 = min((x + l * px).min() for l in LAMS[[0, -1]]) - 1; y0 = min((y + l * py).min() for l in LAMS[[0, -1]]) - 1
    Wd = int(max((x + l * px).max() for l in LAMS[[0, -1]]) - x0) + 3; Hd = int(max((y + l * py).max() for l in LAMS[[0, -1]]) - y0) + 3
    pos = lambda sl, l: np.rint(y[sl] + l * py[sl] - y0).astype(np.int64) * Wd + np.rint(x[sl] + l * px[sl] - x0).astype(np.int64)
    print(f"events {len(t)}, layers {K}, canvas {Hd}x{Wd}", flush=True)
    M = np.zeros((3, K, Hd * Wd), np.float32)
    for s0 in range(0, len(t), CH):
        sl = slice(s0, s0 + CH); g = grp[sl]
        for k, l in enumerate(LAMS):
            p = pos(sl, l)
            for j in range(3): M[j, k] += np.bincount(p[g == j], minlength=Hd * Wd)
    S = np.zeros_like(M)
    for j in range(3):
        for k in range(K): S[j, k] = sharp_of(M[j, k].reshape(Hd, Wd)).ravel()
    del M; print("sharpness done", flush=True)
    i1 = int(np.argmin(abs(LAMS - 1.0))); dl = LAMS[1] - LAMS[0]
    Fbase = np.zeros(Hd * Wd, np.float32); Fgate = np.zeros(Hd * Wd, np.float32); Fagree = np.zeros(Hd * Wd, np.float32); Fall = np.zeros(Hd * Wd, np.float32); lam_every = np.ones(len(t), np.float32)
    agree_all = np.zeros(len(t), bool); lam_all = np.ones(len(t), np.float32); xb = (x + px - x0).astype(np.float32)
    for s0 in range(0, len(t), CH):
        sl = slice(s0, s0 + CH); g = grp[sl]; P = np.stack([pos(sl, l) for l in LAMS]); Va = np.empty(P.shape, np.float32); Vb = np.empty(P.shape, np.float32)
        for k in range(K):
            G = np.stack([S[0, k][P[k]], S[1, k][P[k]], S[2, k][P[k]]]); Va[k] = np.take_along_axis(G, ((g + 1) % 3)[None], 0)[0]; Vb[k] = np.take_along_axis(G, ((g + 2) % 3)[None], 0)[0]
        V = Va + Vb; ka = Va.argmax(0); kb = Vb.argmax(0); kc = V.argmax(0); ok = V.max(0) > 0; agree = ok & (np.abs(ka - kb) <= 1)
        km = np.clip(kc, 1, K - 2); vm = np.take_along_axis(V, (km - 1)[None], 0)[0]; v0 = np.take_along_axis(V, km[None], 0)[0]; vp = np.take_along_axis(V, (km + 1)[None], 0)[0]; den = vm - 2 * v0 + vp
        with np.errstate(divide="ignore", invalid="ignore"): off = np.where(np.abs(den) > 1e-30, 0.5 * (vm - vp) / den, 0.0)
        off = np.clip(np.nan_to_num(off), -0.5, 0.5) * ((kc > 0) & (kc < K - 1)); lc_all = LAMS[kc] + off * dl; lc = np.where(agree, lc_all, 1.0)
        pk = np.rint(y[sl] + lc * py[sl] - y0).astype(np.int64) * Wd + np.rint(x[sl] + lc * px[sl] - x0).astype(np.int64)
        pa = np.rint(y[sl] + lc_all * py[sl] - y0).astype(np.int64) * Wd + np.rint(x[sl] + lc_all * px[sl] - x0).astype(np.int64); Fall += np.bincount(pa, minlength=Hd * Wd); lam_every[sl] = lc_all
        Fgate += np.bincount(pk, minlength=Hd * Wd); Fagree += np.bincount(pk[agree], minlength=Hd * Wd); Fbase += np.bincount(P[i1], minlength=Hd * Wd)
        agree_all[sl] = agree; lam_all[sl] = lc
    np.save(out + "_gate.npy", Fgate.reshape(Hd, Wd)); np.save(out + "_agree.npy", Fagree.reshape(Hd, Wd)); np.save(out + "_base.npy", Fbase.reshape(Hd, Wd)); np.save(out + "_all.npy", Fall.reshape(Hd, Wd))
    np.savez(out + "_ev.npz", t=t.astype(np.float32), agree=agree_all, lam=lam_all, lam_every=lam_every, xb=xb, x0y0=np.array([x0, y0]))
    print(f"agreed {agree_all.mean():.3f}; lambda (agreed) median {np.median(lam_all[agree_all]):.3f}, 10-90% {np.percentile(lam_all[agree_all],10):.2f}-{np.percentile(lam_all[agree_all],90):.2f}")


if __name__ == "__main__":
    run(*sys.argv[1:4])
