#!/usr/bin/env python3
# §177: 번짐이 '공통 궤적 오차'인가 '타일 고유(움직이는 물체/시차)'인가. 장면 고정 타일마다 이벤트를 시간순 J조각으로 나눠
# 조각 j의 지도가 조각 0 대비 (dx,dy)만큼 어긋난 정도를 위상상관으로 잰다. 공통 궤적 오차 e(t)(매듭 B개, 모자 함수)가 있으면
#   s_tj = e(tau_tj) - e(tau_t0) + 잡음   (타일 t, 조각 j) 을 모든 타일이 공유한다. 최소제곱으로 e를 풀고 설명 분산 R^2 보고.
# 검증: 타일의 절반(훈련)으로 구한 e(t)가 나머지 절반(시험) 타일의 어긋남을 설명하는가 + 같은 크기 무작위 섞기(대조).
# 사용: pan_common_mode.py <events.h5> <track.npy> <out_e.npy>
import sys

import cv2
import h5py
import numpy as np

from pan_blur_table import TILE, img

J, B, MIN_SL, STRIDE = 5, 24, 1500, 2


def collect(h5p, trk):
    f = h5py.File(h5p, "r"); t = f["events/t"][::STRIDE].astype(np.float64); x = f["events/x"][::STRIDE].astype(np.float64); y = f["events/y"][::STRIDE].astype(np.float64)
    tr = np.load(trk); X1 = x + np.interp(t, tr[:, 0], tr[:, 1]); Y1 = y + np.interp(t, tr[:, 0], tr[:, 2]); X1 -= X1.min(); Y1 -= Y1.min()
    tx = (X1 // TILE).astype(np.int64); ty = (Y1 // TILE).astype(np.int64); nx = tx.max() + 1; tid = ty * nx + tx
    order = np.argsort(tid, kind="stable"); cuts = np.flatnonzero(np.diff(tid[order])) + 1; rows = []
    for g in np.split(order, cuts):
        if len(g) < J * MIN_SL: continue
        g = g[np.argsort(t[g])]; parts = np.array_split(g, J); ox, oy = (tid[g[0]] % nx) * TILE, (tid[g[0]] // nx) * TILE
        I = [img(np.clip((X1[p] - ox).astype(int), 0, TILE - 1), np.clip((Y1[p] - oy).astype(int), 0, TILE - 1)) for p in parts]
        for j in range(1, J):
            (dx, dy), resp = cv2.phaseCorrelate(I[0], I[j]); rows.append((tid[g[0]], t[parts[0]].mean(), t[parts[j]].mean(), dx, dy, resp, tid[g[0]] % nx, tid[g[0]] // nx))
    return np.array(rows), t[0], t[-1]


def design(r, t0, t1):
    tk = np.linspace(t0, t1, B); h = tk[1] - tk[0]
    hat = lambda tt: np.maximum(0, 1 - np.abs(tt[:, None] - tk[None, :]) / h)
    return (hat(r[:, 2]) - hat(r[:, 1]))[:, 1:], tk                                             # 기준(매듭 0) 고정


if __name__ == "__main__":
    R, t0, t1 = collect(sys.argv[1], sys.argv[2]); R = R[R[:, 5] > 0.3]; A, tk = design(R, t0, t1)
    print(f"tile-slice pairs {len(R)} (tiles {len(np.unique(R[:,0]))}), shift |median| x {np.median(abs(R[:,3])):.2f} y {np.median(abs(R[:,4])):.2f} px")
    tiles = np.unique(R[:, 0]); rng = np.random.default_rng(0); res = {}
    for rep in range(1):
        te = set(rng.choice(tiles, len(tiles) // 2, replace=False)); is_te = np.array([v in te for v in R[:, 0]])
        for ax, nm in ((3, "x (pan axis)"), (4, "y")):
            s = R[:, ax]; coef = np.linalg.lstsq(A[~is_te], s[~is_te], rcond=None)[0]
            r2 = lambda m: 1 - ((s[m] - A[m] @ coef) ** 2).sum() / (s[m] ** 2).sum()
            null = []; 
            for k in range(200):                                                                  # 대조: 시험 타일의 어긋남을 섞어서 같은 e(t)로 설명되는 정도
                sp = rng.permutation(s[is_te]); null.append(1 - ((sp - A[is_te] @ coef) ** 2).sum() / (sp ** 2).sum())
            print(f"  {nm:13s} R2 train {r2(~is_te):+.2f}  held-out tiles {r2(is_te):+.2f}   (shuffled-null held-out {np.mean(null):+.2f} +- {np.std(null):.2f})")
    full = [np.linalg.lstsq(A, R[:, ax], rcond=None)[0] for ax in (3, 4)]; e = np.zeros((B, 2)); e[1:, 0] = full[0]; e[1:, 1] = full[1]
    np.save(sys.argv[3], np.c_[tk, e]); print("e(t) x at knots (px): " + " ".join(f"{v:+.1f}" for v in e[::3, 0])); print("e(t) y at knots (px): " + " ".join(f"{v:+.1f}" for v in e[::3, 1]))
