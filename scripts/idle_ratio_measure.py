#!/usr/bin/env python3
# §217: 눈 깜빡임(프레임 사이 전체 클록 차단)의 잠재 이득. 실제 DELTA 프레임별 이벤트 수로 칩이 일하는 사이클 비율(duty)을 클록 주파수별로 추정.
# 가정(데이터에는 프레임 안 도착 시각이 없음): 프레임 주기 = 프레임 시각 간격(약 773 us), 입력단은 프레임의 이벤트를 8개/사이클 버스트로 받음(busy_in = N/8 사이클),
# 쓰기 포트는 1건/사이클이고 FIFO 버퍼링 한도 없이 모두 쓴다면 busy_wr = N 사이클(상한), FIFO가 얕아 버리면 busy_wr은 busy_in + 배출 꼬리 정도(하한 근사 = busy_in).
# 사용: idle_ratio_measure.py <events.h5>
import sys

import h5py
import numpy as np

f = h5py.File(sys.argv[1], "r"); t = f["events/t"][:]
fr_t, cnt = np.unique(t, return_counts=True); period_us = np.median(np.diff(fr_t)); print(f"frames {len(fr_t)}, median frame period {period_us:.0f} us, events/frame: median {np.median(cnt):.0f}, p10 {np.percentile(cnt, 10):.0f}, p90 {np.percentile(cnt, 90):.0f}, max {cnt.max()}")
print(f"{'clock':>8s} {'cycles/frame':>13s} {'duty low (in-bound, N/8)':>26s} {'duty high (writer-bound, N)':>29s}")
for mhz in (200, 100, 50, 25):
    cyc = period_us * mhz
    lo = np.minimum(cnt / 8.0 / cyc, 1.0); hi = np.minimum(cnt / cyc, 1.0)
    print(f"{mhz:5d}MHz {cyc:13.0f} {np.median(lo) * 100:20.1f}% (p90 {np.percentile(lo, 90) * 100:4.1f}%) {np.median(hi) * 100:21.1f}% (p90 {np.percentile(hi, 90) * 100:5.1f}%)")
