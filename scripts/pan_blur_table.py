#!/usr/bin/env python3
# §175: pan 맵 번짐 수치화. 장면 고정 타일(TILE px, 기준 궤적 위치)마다 그 타일 이벤트를 시간순 절반으로 나눠
#   shift   = 앞/뒤 절반 지도 사이 위상상관 이동량(px) = 같은 장면점이 시간에 따라 어긋나는 정도(궤적 오차 또는 움직이는 물체)
#   gain    = 뒤 절반을 shift만큼 되돌렸을 때 겹침 점수(sum c^2) 증가 배율 = 이 어긋남이 선명도를 얼마나 깎는가
#   resp    = 위상상관 피크 신뢰도
# 와 함께 원인 후보 변수(관측 시각, 팬 속도, 장면 x/y, 센서 x, 밀도)를 한 표로 저장.
import csv
import sys

import cv2
import h5py
import numpy as np
from scipy.ndimage import gaussian_filter

TILE, MIN_EV, STRIDE = 96, 8000, 2


def img(xi, yi):
    c = np.bincount(yi * TILE + xi, minlength=TILE * TILE).reshape(TILE, TILE).astype(np.float32)
    return gaussian_filter(np.log1p(c), 1.2) * np.outer(np.hanning(TILE), np.hanning(TILE)).astype(np.float32)


def collide(X, Y):
    xi = np.rint(X - X.min()).astype(np.int64); yi = np.rint(Y - Y.min()).astype(np.int64)
    c = np.bincount(yi * (xi.max() + 1) + xi).astype(np.float64); return float((c ** 2).sum() / len(X) ** 2)


if __name__ == "__main__":
    h5p, trk, out = sys.argv[1:4]
    f = h5py.File(h5p, "r"); t = f["events/t"][::STRIDE].astype(np.float64); x = f["events/x"][::STRIDE].astype(np.float64); y = f["events/y"][::STRIDE].astype(np.float64)
    tr = np.load(trk); px = np.interp(t, tr[:, 0], tr[:, 1]); py = np.interp(t, tr[:, 0], tr[:, 2])
    speed_t = np.gradient(tr[:, 1], tr[:, 0]) * 773.0                                        # px / 프레임(773us)
    X1 = x + px; Y1 = y + py; X1 -= X1.min(); Y1 -= Y1.min()
    fr = np.searchsorted(np.unique(t), t)                                                    # 프레임 번호(대조군: 홀/짝 프레임 분할)
    tx = (X1 // TILE).astype(np.int64); ty = (Y1 // TILE).astype(np.int64); nx = tx.max() + 1; tid = ty * nx + tx
    order = np.argsort(tid, kind="stable"); cuts = np.flatnonzero(np.diff(tid[order])) + 1; rows = []
    for g in np.split(order, cuts):
        if len(g) < MIN_EV: continue
        g = g[np.argsort(t[g])]; h = len(g) // 2; a, b = g[:h], g[h:]
        ox, oy = (tid[g[0]] % nx) * TILE, (tid[g[0]] // nx) * TILE
        ia = img(np.clip((X1[a] - ox).astype(int), 0, TILE - 1), np.clip((Y1[a] - oy).astype(int), 0, TILE - 1))
        ib = img(np.clip((X1[b] - ox).astype(int), 0, TILE - 1), np.clip((Y1[b] - oy).astype(int), 0, TILE - 1))
        (dx, dy), resp = cv2.phaseCorrelate(ia, ib)                                           # ib가 ia 대비 (dx,dy) 이동
        ea, eb = g[fr[g] % 2 == 0], g[fr[g] % 2 == 1]
        (cx_, cy_), _ = cv2.phaseCorrelate(img(np.clip((X1[ea] - ox).astype(int), 0, TILE - 1), np.clip((Y1[ea] - oy).astype(int), 0, TILE - 1)),
                                           img(np.clip((X1[eb] - ox).astype(int), 0, TILE - 1), np.clip((Y1[eb] - oy).astype(int), 0, TILE - 1)))
        before = collide(X1[g], Y1[g])
        Xs = np.concatenate([X1[a], X1[b] - dx]); Ys = np.concatenate([Y1[a], Y1[b] - dy]); after = collide(Xs, Ys)
        tm = t[g].mean(); sp_ = np.interp(tm, tr[:, 0], speed_t)
        rows.append(dict(tile_x=int(tid[g[0]] % nx), tile_y=int(tid[g[0]] // nx), x_scene=ox + TILE / 2, y_scene=oy + TILE / 2, n=len(g), density=len(g) / TILE ** 2,
                         t_mean_ms=tm / 1e3, t_span_ms=(t[g].max() - t[g].min()) / 1e3, speed_px_frame=sp_, x_sensor=x[g].mean(), y_sensor=y[g].mean(),
                         shift_x=dx, shift_y=dy, shift=float(np.hypot(dx, dy)), shift_ctrl=float(np.hypot(cx_, cy_)), gain=after / before, resp=float(resp)))
    with open(out, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)
    print("tiles", len(rows), "->", out)
