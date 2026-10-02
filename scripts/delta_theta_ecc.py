#!/usr/bin/env python3
# §161: 현수(hyunsu_round2/code/register_roll.py)의 기준 궤적 방법을 우리 h5에 재현 -- 4프레임 창의 이벤트 카운트 영상을
# 연속 창끼리 유클리드 ECC로 정합, 회전각 누적. 유클리드 워프의 회전각은 회전 중심 위치와 무관하므로(병진 tx,ty가
# 센서-축 오프셋과 시차를 흡수) 선 방향/CMax와 독립인 theta(t)를 준다. 프레임 경계 = 같은 타임스탬프 묶음.
import sys

import cv2
import h5py
import numpy as np
from scipy.ndimage import gaussian_filter

WIN, DS = 4, 2
MIN_EV = int(__import__("os").environ.get("ECC_MIN_EV", "15000"))     # 실제 영상 기준 15000(합성은 이벤트 30%라서 낮춤)


def run(h5_path, out_npy, time_window_us=None):
    f = h5py.File(h5_path, "r")
    t = f["events/t"][:]; x = f["events/x"][:]; y = f["events/y"][:]
    if time_window_us:                                           # 타임스탬프가 프레임 단위가 아닌 데이터(합성 등): 고정 시간 창을 '프레임'으로 취급
        edges = np.arange(float(t[0]), float(t[-1]), time_window_us / WIN)
        first = np.concatenate([np.searchsorted(t, edges), [len(t)]])
    else:
        first = np.concatenate([[0], np.flatnonzero(np.diff(t)) + 1, [len(t)]])        # 프레임별 첫 이벤트 인덱스
    nf = len(first) - 1; t_frame = t[np.minimum(first[:-1], len(t) - 1)].astype(np.int64)
    print("frames", nf, flush=True)

    def img_of(k):
        s, e = first[k], first[min(k + WIN, nf)]
        im = np.zeros((720 // DS, 960 // DS), np.float32)
        np.add.at(im, (y[s:e] // DS, x[s:e] // DS), 1.0)
        im = gaussian_filter(np.minimum(im, 4), 1.2)
        return (im / (im.max() + 1e-6)).astype(np.float32), e - s

    starts = list(range(1, nf - WIN, WIN)); rows = []
    prev, pn = img_of(starts[0]); warp = np.eye(2, 3, dtype=np.float32)
    crit = (cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT, 100, 1e-5)
    for k in starts[1:]:
        im, n = img_of(k); ok, dth, cc = False, np.nan, np.nan
        if n >= MIN_EV and pn >= MIN_EV:
            try:
                cc, W = cv2.findTransformECC(prev, im, warp.copy(), cv2.MOTION_EUCLIDEAN, crit, None, 5)
                dth = np.degrees(np.arctan2(W[1, 0], W[0, 0])); ok = True; warp = W
            except cv2.error:
                warp = np.eye(2, 3, dtype=np.float32)
        rows.append((t_frame[k] / 1e3, n, ok, dth, cc)); prev, pn = im, n
    a = np.array(rows, dtype=float); np.save(out_npy, a)
    ok = a[:, 2].astype(bool); th = np.cumsum(np.where(ok, a[:, 3], 0.0))
    print(f"windows {len(a)}, registered {ok.sum()}, total roll {th[-1]:.1f} deg")


if __name__ == "__main__":
    run(sys.argv[1], sys.argv[2], float(sys.argv[3]) if len(sys.argv) > 3 else None)
