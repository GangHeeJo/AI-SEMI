#!/usr/bin/env python3
# §169: UZH shapes_rotation(DAVIS240, 모션캡처 정답)에서 우리 ECC θ 추정기를 진짜 정답으로 채점.
# 정답 = 쿼터니언 증분의 광축(z) 둘레 회전 성분 (3축 회전 중 영상 평면 회전만 비교; pan/tilt는 ECC의 병진이 흡수).
# 지표 = 1초 구간별 |Δθ_est - Δθ_gt| (구간마다 기준 재설정; 누적 표류가 아니라 순간 정확도).
import os
import sys

import cv2
import numpy as np
import pandas as pd
from scipy.ndimage import gaussian_filter
from scipy.spatial.transform import Rotation as Rot

W, H = 240, 180
GT_SHIFT = float(os.environ.get("GT_SHIFT", "0"))       # 정답 자세 시간 보정(초): 이벤트 시각 t에는 정답 자세 roll(t + GT_SHIFT)를 대응(uzh_diag_validity.py로 추정, 약 +0.008)


def gt_roll(path):
    g = np.loadtxt(path); t = g[:, 0]; R = Rot.from_quat(g[:, 4:8])           # qx qy qz qw
    dz = (R[:-1].inv() * R[1:]).as_rotvec()                                    # 카메라 좌표계 증분
    return t[1:], np.degrees(np.cumsum(dz[:, 2])), np.degrees(np.linalg.norm(dz, axis=1).cumsum())


def ecc_theta(ev, win_s, min_ev=300):
    t = ev[:, 0]; x = ev[:, 1].astype(int); y = ev[:, 2].astype(int)
    edges = np.arange(t[0], t[-1], win_s); idx = np.searchsorted(t, edges)
    ims = []
    for a, b in zip(idx[:-1], idx[1:]):
        im = np.zeros((H, W), np.float32); np.add.at(im, (y[a:b], x[a:b]), 1.0)
        im = gaussian_filter(np.minimum(im, 4), 1.0); ims.append((im / (im.max() + 1e-6), b - a))
    crit = (cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT, 100, 1e-5); d = np.zeros(len(ims) - 1); ok = np.zeros(len(ims) - 1, bool)
    for i in range(len(ims) - 1):
        if ims[i][1] < min_ev or ims[i + 1][1] < min_ev: continue
        try:
            _, Wm = cv2.findTransformECC(ims[i][0], ims[i + 1][0], np.eye(2, 3, dtype=np.float32), cv2.MOTION_EUCLIDEAN, crit, None, 5)
            d[i] = np.degrees(np.arctan2(Wm[1, 0], Wm[0, 0])); ok[i] = True
        except cv2.error: pass
    return edges[1:len(ims)], d, ok


if __name__ == "__main__":
    ev = pd.read_csv(sys.argv[1] + "/events.txt", sep=" ", header=None, names=["t", "x", "y", "p"], dtype={"t": np.float64}).values
    tg, roll, mag = gt_roll(sys.argv[1] + "/groundtruth.txt")
    for win in (0.005, 0.01, 0.02):
        te, d, ok = ecc_theta(ev, win)
        th = np.cumsum(np.where(ok, d, 0.0))
        for sgn in (1, -1):
            res = []
            for t0 in np.arange(2.0, 58.0, 1.0):
                m = (te >= t0) & (te < t0 + 1.0)
                est = sgn * th[m][-1] - sgn * th[m][0] if m.sum() > 5 else np.nan
                gt = np.interp(t0 + 1 + GT_SHIFT, tg, roll) - np.interp(t0 + GT_SHIFT, tg, roll)
                res.append((est, gt, ok[m].mean() if m.any() else 0))
            r = np.array(res); v = ~np.isnan(r[:, 0]); e = r[v, 0] - r[v, 1]
            print(f"win {win*1e3:4.0f}ms sign {sgn:+d}: 1s-block error RMS {np.sqrt((e**2).mean()):6.2f} deg  (gt roll per-1s RMS {np.sqrt((r[v,1]**2).mean()):5.2f}, corr {np.corrcoef(r[v,0], r[v,1])[0,1]:+.2f}, slope {np.polyfit(r[v,1], r[v,0], 1)[0]:+.2f}, ok-frac {r[v,2].mean():.2f})")
    print(f"GT total |rotation| {mag[-1]:.0f} deg, z-roll net {roll[-1]:.0f} deg")
