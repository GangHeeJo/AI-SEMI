#!/usr/bin/env python3
# §194: 일치율(두 독립 증거가 +-1층 안에서 일치한 이벤트 비율)이 이벤트 성질에 따라 어떻게 달라지는지. 합성(76%)과 실제(45%)의 차이 원인 탐색.
# 특성: 국소 밀도 = 같은 프레임 안 4x4 셀의 이벤트 수(1이면 고립), 센서 y/x 위치, 시각. flag: 1 일치, 2 전파(일치 아님), 0 기각 (delta_depthsnap5 --diag).
# 사용: agreement_factors.py <events.h5> <diag_flag.npy> <label> [n_events=6000000]
import sys

import h5py
import numpy as np

h5p, flp, label = sys.argv[1:4]; n = int(sys.argv[4]) if len(sys.argv) > 4 else 6_000_000
fl_all = np.load(flp); N = len(fl_all); i0 = (N // 2 - n // 2)                                        # 가운데 구간의 연속 n개(프레임 보존)
f = h5py.File(h5p, "r"); sl = slice(2 * i0, 2 * (i0 + n), 2)
x = f["events/x"][sl].astype(np.int64); y = f["events/y"][sl].astype(np.int64); t = f["events/t"][sl].astype(np.int64); fl = fl_all[i0:i0 + n]
frame = np.cumsum(np.concatenate([[0], np.diff(t) != 0])); key = (frame * 241 + (y // 4)) * 241 + (x // 4)
_, inv, cnt = np.unique(key, return_inverse=True, return_counts=True); loc = cnt[inv]; ag = (fl == 1)
print(f"[{label}] events {n}, agreed {ag.mean()*100:.1f}%, propagated {np.mean(fl==2)*100:.1f}%, rejected {np.mean(fl==0)*100:.1f}%")
print("  by local density (events in same 4x4 cell of the same frame): share of events | agreement %")
for lo, hi, nm in ((1, 1, "1 (isolated)"), (2, 2, "2"), (3, 4, "3-4"), (5, 8, "5-8"), (9, 16, "9-16")):
    s = (loc >= lo) & (loc <= hi); print(f"    {nm:14s} {s.mean()*100:5.1f}% | {ag[s].mean()*100:5.1f}%")
s = loc >= 17; print(f"    {'17+':14s} {s.mean()*100:5.1f}% | {ag[s].mean()*100:5.1f}%")
print("  by sensor row y (6 bands, top->bottom): agreement % | " + " ".join(f"{ag[(y >= a) & (y < a + 120)].mean()*100:5.1f}" for a in range(0, 720, 120)))
print("  by sensor column x (6 bands, left->right): agreement % | " + " ".join(f"{ag[(x >= a) & (x < a + 160)].mean()*100:5.1f}" for a in range(0, 960, 160)))
q = np.quantile(frame, [0, .2, .4, .6, .8, 1]); print("  by time (5 equal slices of the window): agreement % | " + " ".join(f"{ag[(frame >= q[k]) & (frame <= q[k+1])].mean()*100:5.1f}" for k in range(5)))
print("  by polarity: ON/OFF agreement % | " + " ".join(f"{ag[f['events/p'][sl] == v].mean()*100:5.1f}" for v in (1, 0)))
