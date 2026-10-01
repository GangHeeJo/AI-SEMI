#!/usr/bin/env python3
# §148: DELTA 실측(960x720, 1ms 프레임)에서 ground truth 없이 회전각 theta(t)를 추정.
# 창(W ms)마다 각속도 omega를 contrast maximization으로 탐색: 이벤트를 창 기준시각으로
# 되돌리는 회전(-omega*(t-tref), 회전중심=center)을 걸어 (X,Y)칸 집중도 sum(count^2)가 최대인
# omega를 고르고, omega*W를 누적해 theta(t)를 만든다. (SW 모델 -- RTL 이전 단계)
import sys

import h5py
import numpy as np

H5 = "Q&A/3차/extracted/2026-09-22-16-42-32-DELTA.h5"
W_PX, H_PX = 960, 720
CX, CY = W_PX / 2, H_PX / 2
WIN_MS = 4
OMEGAS = np.radians(np.arange(-2400, 2401, 40))  # rad/s 후보
SUB = 30000


def warp_score(x, y, dt, omega, cx, cy):
    a = -omega * dt
    c, s = np.cos(a), np.sin(a)
    xr = c * (x - cx) - s * (y - cy) + cx
    yr = s * (x - cx) + c * (y - cy) + cy
    xi = np.clip(np.rint(xr).astype(np.int64), 0, W_PX - 1)
    yi = np.clip(np.rint(yr).astype(np.int64), 0, H_PX - 1)
    cnt = np.bincount(yi * W_PX + xi, minlength=W_PX * H_PX)
    return float((cnt.astype(np.float64) ** 2).sum())


def estimate(cx=CX, cy=CY, win_ms=WIN_MS, max_win=None, seed=0):
    rng = np.random.default_rng(seed)
    f = h5py.File(H5, "r")
    m = f["ms_to_idx"][:].astype(np.int64)
    out = []  # (t_ms_start, omega_best, score_best, score_zero, n_events)
    nwin = (len(m) - 1) // win_ms
    for w in range(nwin if max_win is None else min(nwin, max_win)):
        s, e = m[w * win_ms], m[(w + 1) * win_ms]
        n = e - s
        if n < 5000:
            out.append((w * win_ms, 0.0, 0.0, 0.0, n)); continue
        idx = np.sort(rng.choice(n, min(SUB, n), replace=False)) + s
        x = f["events/x"][s:e][idx - s].astype(np.float64)
        y = f["events/y"][s:e][idx - s].astype(np.float64)
        t = f["events/t"][s:e][idx - s].astype(np.float64) * 1e-6
        dt = t - t.mean()
        scores = np.array([warp_score(x, y, dt, om, cx, cy) for om in OMEGAS])
        k = int(scores.argmax())
        out.append((w * win_ms, float(OMEGAS[k]), scores[k], float(scores[len(OMEGAS) // 2]), n))
    return np.array(out)


if __name__ == "__main__":
    res = estimate()
    np.save(sys.argv[1] if len(sys.argv) > 1 else "delta_omega.npy", res)
    om = np.degrees(res[:, 1])
    print("windows", len(res), "omega deg/s: min/med/max", om.min(), np.median(om), om.max())
    gain = np.where(res[:, 3] > 0, res[:, 2] / np.maximum(res[:, 3], 1), 0)
    print("contrast gain best/zero: median", np.median(gain[gain > 0]), "p10", np.percentile(gain[gain > 0], 10))
    print("integrated theta total (deg):", np.degrees((res[:, 1] * WIN_MS * 1e-3).sum()))
