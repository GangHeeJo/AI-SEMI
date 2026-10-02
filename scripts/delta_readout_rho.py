#!/usr/bin/env python3
# §164: 프레임 안 읽기 시각 모델 t_e = t_frame + (x/960 - 0.5) * rho * T 의 rho(읽기 지속 비율)를 데이터에서 추정.
# 같은 프레임 안에서 오른쪽 열이 왼쪽 열보다 0.5*rho*T 늦게 읽힌다. 프레임 스탬프만으로 월드맵을 만들면 왼쪽 절반 이벤트는
# +0.25*rho*T*omega, 오른쪽 절반은 -0.25*rho*T*omega 만큼 회전각이 어긋나므로, 두 절반으로 만든 월드맵 사이에 회전 차이
# dtheta = omega*0.5*rho*T 가 생긴다 -> 유클리드 ECC로 두 월드맵의 회전 차이를 재서 rho = dtheta / (0.5*T*omega).
# (병진은 ECC가 흡수 -> 시차 영향 작음). 빠른 구간 여러 개의 중앙값/분산으로 신뢰도 평가.
import sys

import cv2
import h5py
import numpy as np
from scipy.ndimage import gaussian_filter

T_US = 773.0
C = 1400
OFF = C / 2


def world_map(x, y, a, c0, sel):
    px = x[sel] - c0[0]; py = y[sel] - c0[1]
    c, s = np.cos(a[sel]), np.sin(a[sel])
    xi = np.rint(c * px - s * py + OFF).astype(np.int64); yi = np.rint(s * px + c * py + OFF).astype(np.int64)
    ok = (xi >= 0) & (xi < C) & (yi >= 0) & (yi < C)
    return np.bincount(yi[ok] * C + xi[ok], minlength=C * C).reshape(C, C).astype(np.float32)


def prep(m):
    m = gaussian_filter(np.minimum(m, np.percentile(m[m > 0], 99.5)), 1.5)
    m = m[int(OFF) - 400:int(OFF) + 400, int(OFF) - 400:int(OFF) + 400]
    return (m / (m.max() + 1e-6)).astype(np.float32)


def estimate(h5_path, theta_npy, segs, c0=(480.0, 360.0), win_ms=4, split=480):
    th = np.load(theta_npy); mids = np.arange(len(th)) * win_ms + win_ms / 2.0
    om_t = np.gradient(th, win_ms * 1e-3)
    f = h5py.File(h5_path, "r"); m = f["ms_to_idx"][:].astype(np.int64)
    out = []
    for t0, t1 in segs:
        s, e = m[t0], m[t1]
        x = f["events/x"][s:e].astype(np.float64); y = f["events/y"][s:e].astype(np.float64)
        t = f["events/t"][s:e].astype(np.float64) / 1e3                # ms
        a = -np.interp(t, mids, th)
        w_ev = np.interp(t, mids, om_t)
        L = x < split
        mL = prep(world_map(x, y, a, c0, L)); mR = prep(world_map(x, y, a, c0, ~L))
        crit = (cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT, 200, 1e-6)
        try:
            cc, W = cv2.findTransformECC(mL, mR, np.eye(2, 3, dtype=np.float32), cv2.MOTION_EUCLIDEAN, crit, None, 5)
        except cv2.error:
            continue
        dth = np.arctan2(W[1, 0], W[0, 0])
        om = float(np.mean(w_ev))                                       # 구간 평균 각속도(rad/s)
        xr = float(x[~L].mean() - x[L].mean())                          # 두 절반의 평균 열 차이(px)
        dt_expected_per_rho = (xr / 960.0) * T_US * 1e-6               # rho=1일 때 두 절반 평균 시각 차이(s)
        out.append(dict(seg=(t0, t1), dth_deg=float(np.degrees(dth)), omega_deg_s=float(np.degrees(om)), cc=float(cc),
                        rho_raw=float(dth / (om * dt_expected_per_rho))))
    return out


if __name__ == "__main__":
    # usage: delta_readout_rho.py <events.h5> <theta.npy (rad, 4ms mids)> [c0x c0y]
    segs = [(460, 520), (520, 580), (580, 640), (640, 700), (700, 740), (1100, 1160), (1160, 1220), (1220, 1280)]
    res = estimate(sys.argv[1], sys.argv[2], segs)
    for r in res:
        print("seg %s  omega %6.1f deg/s  L-R rotation %+7.4f deg  cc %.3f  rho_raw %+6.2f" % (r["seg"], r["omega_deg_s"], r["dth_deg"], r["cc"], r["rho_raw"]))
    rr = np.array([r["rho_raw"] for r in res])
    print("rho_raw: median %+.2f  mean %+.2f  std %.2f  (n=%d)" % (np.median(rr), rr.mean(), rr.std(), len(rr)))
