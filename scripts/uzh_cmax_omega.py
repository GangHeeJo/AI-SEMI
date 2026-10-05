#!/usr/bin/env python3
# §200: UZH shapes_rotation에서 3축 각속도 CMax(대비 최대화) 추정기를 정답(모션캡처, 시간 어긋남 보정)과 비교.
# 창(WIN_S)마다 이벤트를 창 중심 시각으로 순수 회전 흐름(Longuet-Higgins)으로 되돌린 뒤 이벤트 영상의 겹침 점수 sum c^2를 최대화하는 ω를 Nelder-Mead로 구한다(이전 창 값에서 시작).
# 정답 ω = 쿼터니언 유한 차분(5ms, 몸체 좌표). 부호/축 규약은 개발 구간 회귀로 고정(규약이지 상수 조정이 아님). 개발 = 앞 절반, 검증 = 뒤 절반.
# 사용: uzh_cmax_omega.py <uzh_dir> [gt_shift_s=0.008] [win_s=0.01]
import sys

import cv2
import numpy as np
import pandas as pd
from scipy.optimize import minimize
from scipy.spatial.transform import Rotation as Rot

fx, fy, cx, cy = 199.092366542, 198.82882047, 132.192071378, 110.712660011
DIST = np.array([-0.368436311798, 0.150947243557, -0.000296130534385, -0.000759431726241]); K = np.array([[fx, 0, cx], [0, fy, cy], [0, 0, 1]]); W, H = 240, 180
OM_MAX = 600.0           # deg/s, 물리적으로 가능한 각속도 상한(손으로 흔드는 운동 기준의 일반적 범위; 정답 최대값을 보고 정한 것이 아님)
OUT = sys.argv[4] if len(sys.argv) > 4 else "cmax_est"
d = sys.argv[1]; SHIFT = float(sys.argv[2]) if len(sys.argv) > 2 else 0.008; WIN = float(sys.argv[3]) if len(sys.argv) > 3 else 0.01
ev = pd.read_csv(d + "/events.txt", sep=" ", header=None, names=["t", "x", "y", "p"]).values; t = ev[:, 0]
xy = cv2.undistortPoints(np.stack([ev[:, 1], ev[:, 2]], 1).reshape(-1, 1, 2), K, DIST).reshape(-1, 2); xn, yn = xy[:, 0], xy[:, 1]
g = np.loadtxt(d + "/groundtruth.txt"); tg = g[:, 0]; Rg = Rot.from_quat(g[:, 4:8]); k5 = 1                                                      # 정답 200 Hz, 한 샘플 차분(5 ms)
om_gt = np.degrees((Rg[:-k5].inv() * Rg[k5:]).as_rotvec() / np.diff(tg)[:, None]); tgm = 0.5 * (tg[:-1] + tg[1:])                              # 몸체 좌표 각속도(deg/s)


def contrast(om, dt):
    wx, wy, wz = np.radians(om)
    X = xn[sl]; Y = yn[sl]; ux = X * Y * wx - (1 + X * X) * wy + Y * wz; uy = (1 + Y * Y) * wx - X * Y * wy - X * wz
    px = np.rint((X - ux * dt) * fx + cx).astype(np.int64); py = np.rint((Y - uy * dt) * fy + cy).astype(np.int64); ok = (px >= 0) & (px < W) & (py >= 0) & (py < H)
    c = np.bincount(py[ok] * W + px[ok], minlength=W * H).astype(np.float64); return -float((c * c).sum() / len(X) ** 2 * 1e4) + 1e3 * float(np.maximum(np.abs(om) - OM_MAX, 0).sum())          # 창 전체 이벤트 수로 정규화(화면 밖으로 밀어낸 이벤트가 점수를 희석: 퇴화 해법 방지) + 각속도 범위 제한


EVN = int(sys.argv[5]) if len(sys.argv) > 5 else 0                                                                          # 0이면 고정 시간 창, 양수면 고정 이벤트 수 창
if EVN: i0 = np.arange(0, len(t) - EVN, EVN); i1 = i0 + EVN
else: edges = np.arange(t[0], t[-1], WIN); idx = np.searchsorted(t, edges); i0 = idx[:-1]; i1 = idx[1:]
tc = np.array([0.5 * (t[a] + t[b - 1]) if b > a else np.nan for a, b in zip(i0, i1)]); dur = np.array([t[b - 1] - t[a] if b > a else 0.0 for a, b in zip(i0, i1)])
est = np.full((len(i0), 3), np.nan); prev = np.zeros(3)
for i in range(len(i0)):
    sl = slice(i0[i], i1[i])
    if i1[i] - i0[i] < 400: continue
    dt = t[sl] - tc[i]; r = minimize(lambda o: contrast(o, dt), prev, method="Nelder-Mead", options=dict(xatol=0.5, fatol=1e-9, maxiter=160, initial_simplex=prev + np.vstack([np.zeros(3), 40 * np.eye(3)])))
    est[i] = r.x; prev = r.x
ok = ~np.isnan(est[:, 0]); gt = np.stack([np.interp(tc + SHIFT, tgm, om_gt[:, k]) for k in range(3)], 1)                                           # 이벤트 시각 t에 정답 ω(t + SHIFT)
np.savez(OUT + ".npz", tc=tc, est=est, gt=gt); half = tc < (t[0] + t[-1]) / 2; print(f"windows {len(tc)}, estimated {ok.sum()}, window {EVN if EVN else WIN * 1e3:.0f} {'events' if EVN else 'ms'}, median duration {np.median(dur) * 1e3:.1f} ms, GT time shift {SHIFT * 1e3:.0f} ms")
A = np.linalg.lstsq(gt[ok & half], est[ok & half], rcond=None)[0]; print("regression est = GT @ A (development half), A =\n", np.round(A, 2))                                      # 규약(부호/축) 확인
S = np.sign(np.diag(A)); S[S == 0] = 1; print("per-axis sign convention fixed from the development half:", S.astype(int).tolist())
for nm, sel in (("DEVELOPMENT (first half)", ok & half), ("HELD-OUT (second half)", ok & ~half)):
    e = est[sel] * S - gt[sel]; rms = np.sqrt((e ** 2).mean(0)); gr = np.sqrt((gt[sel] ** 2).mean(0)); tot = np.sqrt((e ** 2).sum(1).mean()); gtt = np.sqrt((gt[sel] ** 2).sum(1).mean())
    ae = np.abs(e); print(f"{nm:26s} robust: median |error| x {np.median(ae[:, 0]):5.1f} y {np.median(ae[:, 1]):5.1f} z {np.median(ae[:, 2]):5.1f} deg/s; windows with any axis error > 100 deg/s: {np.mean((ae > 100).any(1)) * 100:.0f}%")
    print(f"{nm:26s} per-axis RMS error (deg/s) x {rms[0]:6.1f} y {rms[1]:6.1f} z {rms[2]:6.1f} | GT RMS x {gr[0]:6.1f} y {gr[1]:6.1f} z {gr[2]:6.1f} | |omega| error {tot:6.1f} of {gtt:6.1f} deg/s ({tot / gtt * 100:.0f}%)")
# 광축 둘레 1초 구간 회전 오차(ECC 채점과 같은 지표): 적분한 omega_z의 1초 증분과 정답 omega_z의 1초 증분 차이
ez = []
for t0 in np.arange(t[0] + 2, t[-1] - 3, 1.0):
    s = ok & (tc >= t0) & (tc < t0 + 1); ez.append((np.nansum(est[s, 2] * dur[s]) * S[2] - np.nansum(gt[s, 2] * dur[s]), t0))
ez = np.array(ez); h = ez[:, 1] < (t[0] + t[-1]) / 2
print(f"optical-axis (z) rotation per 1 s block, error RMS: development {np.sqrt((ez[h, 0] ** 2).mean()):.2f} deg, held-out {np.sqrt((ez[~h, 0] ** 2).mean()):.2f} deg  (ECC with the same GT shift: 2.4-3.2 deg)")
