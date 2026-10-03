#!/usr/bin/env python3
# §174: pan(가로 이동) 영상용 월드맵. 4프레임 창의 카운트 영상을 연속 창끼리 ECC(이동)로 정합해 누적 (tx,ty)(t)를 구하고,
# 이벤트를 자기 시각의 (tx,ty)만큼 되돌려 쌓는다. 시차(깊이별 이동량 차이)는 아직 반영하지 않음(단일 이동량).
# 사용: delta_pan_mosaic.py <events.h5> <out_prefix>
import sys

import cv2
import h5py
import numpy as np
from scipy.ndimage import gaussian_filter

WIN, DS = 4, 2


def track(t, x, y):
    first = np.concatenate([[0], np.flatnonzero(np.diff(t)) + 1, [len(t)]]); nf = len(first) - 1
    tf = t[first[:-1]].astype(np.float64)

    def img(k):
        s, e = first[k], first[min(k + WIN, nf)]; im = np.zeros((720 // DS, 960 // DS), np.float32)
        np.add.at(im, (y[s:e] // DS, x[s:e] // DS), 1.0); im = gaussian_filter(np.minimum(im, 4), 1.2); return im / (im.max() + 1e-6)
    starts = list(range(0, nf - WIN, WIN)); pos = np.zeros((len(starts), 2)); okk = np.zeros(len(starts), bool); okk[0] = True
    prev = img(starts[0]); crit = (cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT, 100, 1e-5)
    for i in range(1, len(starts)):
        cur = img(starts[i]); pos[i] = pos[i - 1]
        try:
            cc, W = cv2.findTransformECC(prev, cur, np.eye(2, 3, dtype=np.float32), cv2.MOTION_TRANSLATION, crit, None, 5)
            pos[i] = pos[i - 1] - np.array([W[0, 2], W[1, 2]]) * DS; okk[i] = True      # 워프 W: prev좌표 -> cur좌표, 장면이 W만큼 이동 = 카메라 -W
        except cv2.error: pass
        prev = cur
    return tf[starts], pos, okk, first, nf


if __name__ == "__main__":
    f = h5py.File(sys.argv[1], "r"); t = f["events/t"][:]; x = f["events/x"][:]; y = f["events/y"][:]
    ts, pos, ok, first, nf = track(t, x, y); np.save(sys.argv[2] + "_track.npy", np.c_[ts, pos, ok])
    print(f"windows {len(ts)}, registered {ok.sum()}, total shift ({pos[-1,0]:.0f}, {pos[-1,1]:.0f}) px")
    px = np.interp(t, ts, pos[:, 0]); py = np.interp(t, ts, pos[:, 1])
    X = x + px; Y = y + py; X -= X.min(); Y -= Y.min()                                  # 이벤트를 기준 좌표로(장면 고정)
    M = np.bincount((np.rint(Y).astype(np.int64) * (int(X.max()) + 2) + np.rint(X).astype(np.int64)), minlength=(int(Y.max()) + 2) * (int(X.max()) + 2)).reshape(int(Y.max()) + 2, int(X.max()) + 2).astype(np.float32)
    np.save(sys.argv[2] + "_map.npy", M); print("map", M.shape)
