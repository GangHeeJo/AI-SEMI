#!/usr/bin/env python3
# 월드맵 분할 일관성(Noise2Inverse 분할 규칙만 차용, CNN 없음): 이벤트를 독립된 두 부분집합으로 나눠 같은 격자에
# 각각 맵을 만들고 두 맵의 상관 r(σ)을 본다. 정답 맵이 없는 데이터에서도 "맵이 얼마나 재현되는가"를 잴 수 있다.
# 한계: 두 부분집합이 같은 자세(pose)를 공유하므로 포아송 계수 잡음만 재고 자세 오차는 재지 못한다.
# 사용: python map_split_consistency.py <shapes_rotation 폴더> T0 T1
import sys

import cv2
import numpy as np
import pandas as pd
from scipy.ndimage import gaussian_filter
from scipy.spatial.transform import Rotation as Rot, Slerp

from uzh_theta_check import H, W, ecc_theta

T0, T1, WIN, BLOCK = float(sys.argv[2]), float(sys.argv[3]), 0.01, 0.001
fx, fy, cx, cy = 199.092366542, 198.82882047, 132.192071378, 110.712660011
dist = np.array([-0.368436311798, 0.150947243557, -0.000296130534385, -0.000759431726241])
ev = pd.read_csv(sys.argv[1] + "/events.txt", sep=" ", header=None, names=["t", "x", "y", "p"]).values
ev = ev[(ev[:, 0] >= T0) & (ev[:, 0] < T1)]; t, x, y = ev[:, 0], ev[:, 1], ev[:, 2]
g = np.loadtxt(sys.argv[1] + "/groundtruth.txt"); m = (g[:, 0] > T0 - 1) & (g[:, 0] < T1 + 1)
rot = Slerp(g[m, 0], Rot.from_quat(g[m, 4:8]))(t); R0 = Rot.from_quat(g[m, 4:8][np.searchsorted(g[m, 0], T0)])
K = np.array([[fx, 0, cx], [0, fy, cy], [0, 0, 1]])

# 이벤트 -> 맵 좌표 (두 방식: 정답 자세 구면투영 / 우리 ECC 연쇄)
xy = cv2.undistortPoints(np.stack([x, y], 1).reshape(-1, 1, 2), K, dist).reshape(-1, 2)
d = (R0.inv() * rot).apply(np.c_[xy, np.ones(len(xy))])
gt_uv = np.c_[np.arctan2(d[:, 0], d[:, 2]) * fx, np.arctan2(d[:, 1], np.hypot(d[:, 0], d[:, 2])) * fy]

edges = np.arange(t[0], t[-1], WIN); idx = np.searchsorted(t, edges)
ims = []
for a, b in zip(idx[:-1], idx[1:]):
    im = np.zeros((H, W), np.float32); np.add.at(im, (y[a:b].astype(int), x[a:b].astype(int)), 1)
    im = gaussian_filter(np.minimum(im, 4), 1.0); ims.append(im / (im.max() + 1e-6))
A = np.eye(3); As = [A.copy()]; crit = (cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT, 100, 1e-5)
for i in range(len(ims) - 1):
    try:
        _, Wm = cv2.findTransformECC(ims[i], ims[i + 1], np.eye(2, 3, dtype=np.float32), cv2.MOTION_EUCLIDEAN, crit, None, 5)
        A = A @ np.linalg.inv(np.vstack([Wm, [0, 0, 1]]))
    except cv2.error: pass
    As.append(A.copy())
As = np.array(As); wi = np.minimum(np.searchsorted(edges, t, side="right") - 1, len(As) - 1)
ecc_uv = np.einsum("nij,nj->ni", As[wi], np.c_[x, y, np.ones(len(x))])[:, :2]

# 두 가지 분할: 1ms 블록 교대(시간 교차) / 무작위 이벤트 단위(순수 포아송 얇게 하기)
rng = np.random.default_rng(0)
splits = {"time-block 1ms": (np.floor((t - t[0]) / BLOCK).astype(int) % 2).astype(bool),
          "random-event": rng.random(len(t)) < 0.5}


def maps(uv, sel):
    lo = np.floor(uv.min(0)).astype(int); hi = np.ceil(uv.max(0)).astype(int) + 1  # 전체 이벤트 기준 공통 격자
    out = []
    for s in (sel, ~sel):
        p = np.rint(uv[s]).astype(int) - lo
        out.append(np.bincount(p[:, 1] * (hi[0] - lo[0]) + p[:, 0], minlength=(hi[1] - lo[1]) * (hi[0] - lo[0]))
                   .reshape(hi[1] - lo[1], hi[0] - lo[0]).astype(np.float32))
    return out


print(f"events {len(t)}  T={T0}-{T1}s")
print(f"{'map':8s} {'split':15s} " + "  ".join(f"r(s={s})" for s in (0, 1, 2, 4)) + "   (r: 두 절반 맵 피어슨 상관, 활성영역만)")
for name, uv in (("GT-pose", gt_uv), ("ECC", ecc_uv)):
    for sname, sel in splits.items():
        a, b = maps(uv, sel); row = []
        for s in (0, 1, 2, 4):
            fa, fb = (gaussian_filter(a, s), gaussian_filter(b, s)) if s else (a, b)
            act = (a + b) > 0  # 어느 한쪽이라도 이벤트가 닿은 픽셀만(공통 0 픽셀이 상관을 부풀리지 않게)
            row.append(np.corrcoef(fa[act], fb[act])[0, 1])
        print(f"{name:8s} {sname:15s} " + "  ".join(f"{r:7.3f}" for r in row))

# 아이디어 #1 점검(SIRT의 C = 1/Aᵀ1): 창마다 센서 전 픽셀의 시선을 같은 자세로 맵에 찍어 "관측 횟수" C를 만든다(GT 자세 기준).
# C가 맵 안에서 거의 평평하면 정규화는 의미 없다. 이벤트 맵 M이 C와 상관되면 체류시간 편향이 있다는 뜻.
px = cv2.undistortPoints(np.stack(np.meshgrid(np.arange(W), np.arange(H)), -1).reshape(-1, 1, 2).astype(np.float32), K, dist).reshape(-1, 2)
ray = np.c_[px, np.ones(len(px))]
gm = (g[:, 0] > T0 - 1) & (g[:, 0] < T1 + 1); sl = Slerp(g[gm, 0], Rot.from_quat(g[gm, 4:8]))
tw = np.arange(T0 + WIN / 2, T1, WIN); Rw = sl(tw)
cov_uv = np.concatenate([np.c_[np.arctan2(dd[:, 0], dd[:, 2]) * fx, np.arctan2(dd[:, 1], np.hypot(dd[:, 0], dd[:, 2])) * fy]
                         for dd in ((R0.inv() * r).apply(ray) for r in Rw)])
lo = np.floor(gt_uv.min(0)).astype(int); hi = np.ceil(gt_uv.max(0)).astype(int) + 1; shp = (hi[1] - lo[1], hi[0] - lo[0])
def grid(uv):
    p = np.rint(uv).astype(int) - lo; ok = (p[:, 0] >= 0) & (p[:, 0] < shp[1]) & (p[:, 1] >= 0) & (p[:, 1] < shp[0])
    p = p[ok]; return np.bincount(p[:, 1] * shp[1] + p[:, 0], minlength=shp[0] * shp[1]).reshape(shp).astype(np.float32)
Mraw, C = grid(gt_uv), grid(cov_uv); seen = C > 0; act = Mraw > 0
Cs = gaussian_filter(C, 2)
print(f"\n[#1 coverage] 맵 {shp[1]}x{shp[0]}  관측된 픽셀 {seen.mean():.2f}  이벤트 있는 픽셀 {act.mean():.2f}")
print(f"  C 변동계수(관측영역, 이벤트영역) = {C[seen].std()/C[seen].mean():.3f}, {C[act].std()/C[act].mean():.3f}")
print(f"  corr(M, C) 이벤트영역: s=0 {np.corrcoef(Mraw[act], C[act])[0,1]:.3f}   s=2 {np.corrcoef(gaussian_filter(Mraw,2)[act], Cs[act])[0,1]:.3f}")
