#!/usr/bin/env python3
# §153: 알고리즘과 무관한 회전각 GT 만들기 -- 막대/구조물의 직선 방향(물리 제약: 막대는 월드에서 수직,
# 판 가장자리는 수평)으로 롤각을 직접 측정. 20ms 이벤트 프레임에서 긴 직선을 Hough로 검출, 길이 가중
# 4중대칭 방향 평균(막대=수직, 판=수평이 90도 간격)으로 psi(t) in (-45,45], 시간 연속성으로 unwrap.
import sys

import cv2
import h5py
import numpy as np

H5 = "Q&A/3차/extracted/2026-09-22-16-42-32-DELTA.h5"


def frame(f, m, t0, w=20):
    s, e = m[t0], m[t0 + w]
    x = f["events/x"][s:e]; y = f["events/y"][s:e]; p = f["events/p"][s:e]
    img = np.zeros((720, 960), np.float32)
    np.add.at(img, (y, x), np.where(p == 1, 1.0, -1.0))
    return img, e - s


def lines_of(img):
    g = cv2.GaussianBlur(np.abs(img), (0, 0), 1.2)
    thr = np.percentile(g, 94)
    if thr <= 0:
        return np.zeros((0, 4), int)
    b = (g > thr).astype(np.uint8) * 255
    L = cv2.HoughLinesP(b, 1, np.pi / 360, threshold=80, minLineLength=110, maxLineGap=10)
    return np.zeros((0, 4), int) if L is None else L[:, 0, :]


def psi_of(L):
    if len(L) == 0:
        return None, 0.0
    dx = (L[:, 2] - L[:, 0]).astype(float); dy = (L[:, 3] - L[:, 1]).astype(float)
    w = np.hypot(dx, dy); a = np.arctan2(dy, dx)
    z = (w * np.exp(4j * a)).sum()
    return np.degrees(np.angle(z) / 4), float(abs(z) / w.sum())   # 방향(도), 일관도(0~1)


if __name__ == "__main__":
    f = h5py.File(H5, "r"); m = f["ms_to_idx"][:].astype(np.int64)
    ts = list(range(200, 1560, 20)); rows = []
    for t0 in ts:
        img, n = frame(f, m, t0); L = lines_of(img); psi, coh = psi_of(L)
        rows.append((t0, n, len(L), np.nan if psi is None else psi, coh))
    np.save(sys.argv[1] + "/gt_psi_raw.npy", np.array(rows))
    for r in rows: print("t=%4d events=%8d lines=%4d psi=%7.1f coherence=%.2f" % r)
