#!/usr/bin/env python3
# §159: theta 배열(4ms 창 중앙)에서 delta_calibrate.py가 읽는 omega 파일(창별 [t_start_ms, omega_rad_s, ., ., n_events])을 만든다.
# n_events는 템플릿 omega 파일(창별 이벤트 수) 또는 h5의 ms_to_idx에서 가져옴.
import sys

import h5py
import numpy as np

if __name__ == "__main__":
    # usage: delta_omega_from_theta.py <theta.npy> <events.h5> <out_omega.npy>
    th = np.load(sys.argv[1]); f = h5py.File(sys.argv[2], "r"); m = f["ms_to_idx"][:].astype(np.int64)
    n = len(th); out = np.zeros((n, 5))
    out[:, 0] = np.arange(n) * 4
    out[:, 1] = np.gradient(th, 0.004)
    for i in range(n):
        a, b = i * 4, i * 4 + 4
        out[i, 4] = (m[b] - m[a]) if b < len(m) else 0
    np.save(sys.argv[3], out)
    print("omega integral %.1f deg" % np.degrees((out[:, 1] * 0.004).sum()))
