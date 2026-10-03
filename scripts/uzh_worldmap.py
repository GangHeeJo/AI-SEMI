#!/usr/bin/env python3
# §170: UZH shapes_rotation 월드맵 -- (좌) 모션캡처 정답 자세로 구면 투영한 정답 맵, (우) 우리 ECC(회전+병진) 궤적으로 쌓은 맵.
import sys

import cv2
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from scipy.spatial.transform import Rotation as Rot, Slerp

from uzh_theta_check import H, W, ecc_theta

T0, T1, WIN = float(sys.argv[2]), float(sys.argv[3]), 0.01
fx, fy, cx, cy = 199.092366542, 198.82882047, 132.192071378, 110.712660011
dist = np.array([-0.368436311798, 0.150947243557, -0.000296130534385, -0.000759431726241])
ev = pd.read_csv(sys.argv[1] + "/events.txt", sep=" ", header=None, names=["t", "x", "y", "p"]).values
ev = ev[(ev[:, 0] >= T0) & (ev[:, 0] < T1)]; t, x, y = ev[:, 0], ev[:, 1], ev[:, 2]
g = np.loadtxt(sys.argv[1] + "/groundtruth.txt"); m = (g[:, 0] > T0 - 1) & (g[:, 0] < T1 + 1)
rot = Slerp(g[m, 0], Rot.from_quat(g[m, 4:8]))(t); R0 = Rot.from_quat(g[m, 4:8][np.searchsorted(g[m, 0], T0)])
K = np.array([[fx, 0, cx], [0, fy, cy], [0, 0, 1]])

# 정답 맵: 왜곡 보정 -> 광선 -> (R0^-1 R(t)) 회전 -> 방위/고도 평면(픽셀 = f*각)
xy = cv2.undistortPoints(np.stack([x, y], 1).reshape(-1, 1, 2), K, dist).reshape(-1, 2)
ray = np.c_[xy, np.ones(len(xy))]; d = (R0.inv() * rot).apply(ray)
az = np.arctan2(d[:, 0], d[:, 2]); el = np.arctan2(d[:, 1], np.hypot(d[:, 0], d[:, 2]))
def splat(u, v, S=1.0):
    u = np.rint((u - u.min()) * S).astype(int); v = np.rint((v - v.min()) * S).astype(int)
    return np.bincount(v * (u.max() + 1) + u, minlength=(v.max() + 1) * (u.max() + 1)).reshape(v.max() + 1, u.max() + 1).astype(np.float32)
Mg = splat(az * fx, el * fy)

# 우리 맵: 창마다 ECC(회전+병진) 연쇄 -> 이벤트를 기준 창 좌표로
te, dth, ok = ecc_theta(np.c_[t, x, y, ev[:, 3]], WIN)
edges = np.arange(t[0], t[-1], WIN); idx = np.searchsorted(t, edges)
ims = []
from scipy.ndimage import gaussian_filter
for a, b in zip(idx[:-1], idx[1:]):
    im = np.zeros((H, W), np.float32); np.add.at(im, (y[a:b].astype(int), x[a:b].astype(int)), 1); im = gaussian_filter(np.minimum(im, 4), 1.0); ims.append(im / (im.max() + 1e-6))
A = np.eye(3); As = [A.copy()]; crit = (cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT, 100, 1e-5)
for i in range(len(ims) - 1):
    try:
        _, Wm = cv2.findTransformECC(ims[i], ims[i + 1], np.eye(2, 3, dtype=np.float32), cv2.MOTION_EUCLIDEAN, crit, None, 5)
        A = A @ np.linalg.inv(np.vstack([Wm, [0, 0, 1]]))
    except cv2.error: pass
    As.append(A.copy())
As = np.array(As); wi = np.minimum(np.searchsorted(edges, t, side="right") - 1, len(As) - 1)
P = np.einsum("nij,nj->ni", As[wi], np.c_[x, y, np.ones(len(x))])
Mo = splat(P[:, 0], P[:, 1])
fig, ax = plt.subplots(1, 2, figsize=(22, 9))
for a, M, ttl in ((ax[0], Mg, "GROUND-TRUTH-pose map (mocap, undistorted, spherical)"), (ax[1], Mo, "OUR ECC map (rotation+translation chain, no GT)")):
    a.imshow(np.clip(M, 0, np.percentile(M[M > 0], 99.5)) ** 0.6, cmap="gray"); a.set_title(ttl, fontsize=15); a.axis("off")
plt.tight_layout(); plt.savefig("../results_delta/UZH_worldmap.png", dpi=70)
print("GT map", Mg.shape, "ours", Mo.shape, "events", len(t))
