#!/usr/bin/env python3
# §199: 정답 있는 실제 데이터(UZH shapes_rotation, DAVIS240, 모션캡처 자세)로 "맵 진단이 θ 오차를 반영하는가" 검증.
# 정답 회전으로 이벤트를 기준 시각의 시점으로 되돌린 맵에 알려진 크기의 매끄러운 회전 오차(3축, 20ms 매듭 3차 스플라인, 전체 각도 RMS = level)를 더하고
# 오차 크기별로 (a) 선명도(겹침 점수 sum c^2 / N^2 x 1e6, 1px 격자), (b) 복제본 일치(40ms 블록 홀/짝 두 맵의 밴드패스 상관), (c) 극성 순도(2px 칸, 칸당 12개 이상; 극성을 섞은 대조 포함)를 잰다.
# 사용: uzh_diag_validity.py <uzh_dir> [t0=5] [t1=15]
import sys

import cv2
import numpy as np
import pandas as pd
from scipy import ndimage as ndi
from scipy.interpolate import CubicSpline
from scipy.spatial.transform import Rotation as Rot, Slerp

fx, fy, cx, cy = 199.092366542, 198.82882047, 132.192071378, 110.712660011
DIST = np.array([-0.368436311798, 0.150947243557, -0.000296130534385, -0.000759431726241]); K = np.array([[fx, 0, cx], [0, fy, cy], [0, 0, 1]])
d = sys.argv[1]; T0 = float(sys.argv[2]) if len(sys.argv) > 2 else 5.0; T1 = float(sys.argv[3]) if len(sys.argv) > 3 else 15.0
ev = pd.read_csv(d + "/events.txt", sep=" ", header=None, names=["t", "x", "y", "p"]).values; ev = ev[(ev[:, 0] >= T0) & (ev[:, 0] < T1)]; t, x, y, p = ev[:, 0], ev[:, 1], ev[:, 2], ev[:, 3].astype(int)
g = np.loadtxt(d + "/groundtruth.txt"); m = (g[:, 0] > T0 - 1) & (g[:, 0] < T1 + 1); rot = Slerp(g[m, 0], Rot.from_quat(g[m, 4:8]))(t); R0 = Rot.from_quat(g[m, 4:8][np.searchsorted(g[m, 0], T0)])
xy = cv2.undistortPoints(np.stack([x, y], 1).reshape(-1, 1, 2), K, DIST).reshape(-1, 2); ray = np.c_[xy, np.ones(len(xy))]
rng = np.random.default_rng(0); knots = np.arange(T0, T1 + 0.02, 0.02); base_noise = rng.normal(0, 1, (len(knots), 3)); print(f"events {len(t)} in [{T0},{T1}) s; GT segment angular speed median {np.degrees(np.median(np.linalg.norm(np.gradient(Rot.from_quat(g[m,4:8]).as_rotvec(),axis=0),axis=1)*200)):.0f} deg/s (rough)")


def world(level):
    if level == 0: r = rot
    else:
        sp = CubicSpline(knots, base_noise); dv = sp(t); dv = dv / np.sqrt((dv ** 2).sum(1).mean()) * np.radians(level)                   # 전체 각도 RMS = level
        r = Rot.from_rotvec(dv) * rot
    dd = (R0.inv() * r).apply(ray); az = np.arctan2(dd[:, 0], dd[:, 2]); el = np.arctan2(dd[:, 1], np.hypot(dd[:, 0], dd[:, 2])); return az * fx, el * fy


def counts(u, v, sel=None, binpx=1.0, shape=None):
    if sel is None: sel = np.ones(len(u), bool)
    ui = np.floor((u[sel] - U0) / binpx).astype(np.int64); vi = np.floor((v[sel] - V0) / binpx).astype(np.int64); W = int((UM - U0) / binpx) + 2; Hh = int((VM - V0) / binpx) + 2
    return np.bincount(np.clip(vi, 0, Hh - 1) * W + np.clip(ui, 0, W - 1), minlength=W * Hh).reshape(Hh, W).astype(np.float64)


u, v = world(0); U0, UM, V0, VM = u.min() - 30, u.max() + 30, v.min() - 30, v.max() + 30
blk = (np.floor(t / 0.04).astype(int) % 2 == 1)
def band(M): z = np.log1p(M); return ndi.gaussian_filter(z, 1.2) - ndi.gaussian_filter(z, 10)
def ncc(a, b): a = a - a.mean(); b = b - b.mean(); return float((a * b).sum() / np.sqrt((a * a).sum() * (b * b).sum()))
def purity(u, v, pp):
    ui = np.floor((u - U0) / 2).astype(np.int64); vi = np.floor((v - V0) / 2).astype(np.int64); W = int((UM - U0) / 2) + 2; key = vi * W + ui; _, inv, cnt = np.unique(key, return_inverse=True, return_counts=True)
    on = np.bincount(inv, weights=pp); mm = cnt >= 12; pur = np.maximum(on[mm] / cnt[mm], 1 - on[mm] / cnt[mm]); on2 = np.bincount(inv, weights=np.random.default_rng(1).permutation(pp)); pur2 = np.maximum(on2[mm] / cnt[mm], 1 - on2[mm] / cnt[mm])
    return np.average(pur, weights=cnt[mm]), np.average(pur2, weights=cnt[mm]), mm.sum()
print(f"{'rotation error (deg RMS)':26s}{'sharpness':>11s}{'replicate NCC':>15s}{'polarity purity':>17s}{'shuffled ctrl':>15s}")
for level in (0, 0.25, 0.5, 1, 2, 4):
    u, v = world(level); M = counts(u, v); sharp = float((M ** 2).sum() / len(u) ** 2 * 1e6); A = counts(u, v, ~blk); B = counts(u, v, blk); pu, pc, nc = purity(u, v, p)
    print(f"{level:<26.2f}{sharp:11.2f}{ncc(band(A), band(B)):15.3f}{pu:17.3f}{pc:15.3f}", flush=True)


# 정답 자세의 시간 어긋남 시험: rot(t + dt)로 되돌렸을 때 진단이 어디서 최대인가(정답에 지연/오프셋이 있으면 0이 아닌 곳에서 최대)
SL = Slerp(g[m, 0], Rot.from_quat(g[m, 4:8])); print(f"\n{'GT time offset (ms)':22s}{'sharpness':>11s}{'replicate NCC':>15s}{'polarity purity':>17s}")
for dt in (0.0, 0.008, 0.012, 0.016, 0.020, 0.025, 0.030, 0.040, 0.060):
    r2 = SL(np.clip(t + dt, g[m, 0][0], g[m, 0][-1])); dd = (R0.inv() * r2).apply(ray); az = np.arctan2(dd[:, 0], dd[:, 2]); el = np.arctan2(dd[:, 1], np.hypot(dd[:, 0], dd[:, 2])); u, v = az * fx, el * fy
    M = counts(u, v); sharp = float((M ** 2).sum() / len(u) ** 2 * 1e6); A = counts(u, v, ~blk); B = counts(u, v, blk); pu, pc, nc = purity(u, v, p)
    print(f"{dt * 1000:<22.1f}{sharp:11.2f}{ncc(band(A), band(B)):15.3f}{pu:17.3f}", flush=True)
