#!/usr/bin/env python3
# §186: 깊이 평활 제약. 이벤트별로 고른 lambda를 같은 시간 창 + 센서 위 이웃 셀(CELL px) 안 이벤트들의 중앙값으로 대체(셀에 MIN_N개 미만이면 자기 값 유지).
# 같은 시각에 이웃한 픽셀은 같은 표면일 가능성이 높다는 일반 가정 -- 지도 좌표를 쓰지 않아 층 선택과 순환하지 않음.
import numpy as np
import pandas as pd


def smooth(x, y, t, lam, cell, win_us, min_n=8):
    key = (np.floor(t / win_us).astype(np.int64) * 100003 + (x // cell).astype(np.int64)) * 1009 + (y // cell).astype(np.int64)
    df = pd.DataFrame({"k": key, "l": lam}); g = df.groupby("k")["l"]
    med = g.transform("median").to_numpy(); n = g.transform("size").to_numpy()
    return np.where(n >= min_n, med, lam)


def place(x, y, px, py, lam, x0, y0, shape):
    Hd, Wd = shape
    p = np.rint(y + lam * py - y0).astype(np.int64) * Wd + np.rint(x + lam * px - x0).astype(np.int64); p = p[(p >= 0) & (p < Hd * Wd)]
    return np.bincount(p, minlength=Hd * Wd).reshape(Hd, Wd).astype(np.float32)
