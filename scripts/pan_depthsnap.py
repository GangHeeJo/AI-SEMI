#!/usr/bin/env python3
# §180: pan에 이벤트별 시차 층 선택. 층 k = 이동량 배율 lam_k (X = x + lam_k * px(t), Y = y + lam_k * py(t)).
# 시간 앞/뒤 절반으로 층별 지도 MA/MB와 선명도 지도 SA/SB를 만들고, 이벤트는 반대쪽 절반 선명도가 가장 높은 층을 고른다(roll과 동일 방식).
# 출력: 맵(lam=1 기준, 층 선택), 이벤트별 층/위치. 사용: pan_depthsnap.py <events.h5> <track.npy> <out_prefix>
import sys

import h5py
import numpy as np

import delta_depthwarp2 as dw2
from delta_depthwarp2 import sharp_of

LAMS = np.round(np.arange(0.70, 1.3001, 0.01), 3); STRIDE, CH = 4, 1_000_000


def run(h5p, trk, out):
    dw2.SIGMA_SHARP = 3.0
    f = h5py.File(h5p, "r"); t = f["events/t"][::STRIDE].astype(np.float64); x = f["events/x"][::STRIDE].astype(np.float64); y = f["events/y"][::STRIDE].astype(np.float64)
    tr = np.load(trk); px = np.interp(t, tr[:, 0], tr[:, 1]); py = np.interp(t, tr[:, 0], tr[:, 2]); K = len(LAMS); tmid = (t[0] + t[-1]) / 2; isB = t >= tmid
    x0 = min((x + l * px).min() for l in LAMS[[0, -1]]) - 1; y0 = min((y + l * py).min() for l in LAMS[[0, -1]]) - 1
    Wd = int(max((x + l * px).max() for l in LAMS[[0, -1]]) - x0) + 3; Hd = int(max((y + l * py).max() for l in LAMS[[0, -1]]) - y0) + 3
    pos = lambda sl, l: np.rint(y[sl] + l * py[sl] - y0).astype(np.int64) * Wd + np.rint(x[sl] + l * px[sl] - x0).astype(np.int64)
    print(f"events {len(t)}, layers {K}, canvas {Hd}x{Wd}", flush=True)
    MA = np.zeros((K, Hd * Wd), np.float32); MB = np.zeros((K, Hd * Wd), np.float32)
    for s0 in range(0, len(t), CH):
        sl = slice(s0, s0 + CH); b = isB[sl]
        for k, l in enumerate(LAMS):
            p = pos(sl, l); MA[k] += np.bincount(p[~b], minlength=Hd * Wd); MB[k] += np.bincount(p[b], minlength=Hd * Wd)
    SA = np.stack([sharp_of(MA[k].reshape(Hd, Wd)).ravel() for k in range(K)]); SB = np.stack([sharp_of(MB[k].reshape(Hd, Wd)).ravel() for k in range(K)]); del MA, MB
    print("sharpness done", flush=True)
    ks = np.zeros(len(t), np.int16); Fsel = np.zeros(Hd * Wd, np.float32); Fbase = np.zeros(Hd * Wd, np.float32); Xn = np.zeros(len(t), np.float32); Yn = np.zeros(len(t), np.float32)
    i1 = int(np.argmin(abs(LAMS - 1.0)))
    for s0 in range(0, len(t), CH):
        sl = slice(s0, s0 + CH); b = isB[sl]; P = np.stack([pos(sl, l) for l in LAMS])
        V = np.empty(P.shape, np.float32)
        for k in range(K): V[k] = np.where(b, SA[k][P[k]], SB[k][P[k]])
        kb = V.argmax(0); ks[sl] = kb; pk = np.take_along_axis(P, kb[None], 0)[0]
        Fsel += np.bincount(pk, minlength=Hd * Wd); Fbase += np.bincount(P[i1], minlength=Hd * Wd)
        Xn[sl] = (pk % Wd); Yn[sl] = (pk // Wd)
    np.save(out + "_sel.npy", Fsel.reshape(Hd, Wd)); np.save(out + "_base.npy", Fbase.reshape(Hd, Wd)); np.savez(out + "_ev.npz", t=t.astype(np.float32), k=ks, X=Xn, Y=Yn, Xb=(x + px - x0).astype(np.float32), Yb=(y + py - y0).astype(np.float32))
    print("layer histogram (lam: share%):", {float(LAMS[k]): round(float((ks == k).mean() * 100), 1) for k in np.argsort(np.bincount(ks, minlength=K))[::-1][:8]})


if __name__ == "__main__":
    run(*sys.argv[1:4])
