#!/usr/bin/env python3
# §151: 번짐의 정체 = 깊이별로 다른 "회전 중심 오프셋"(센서가 회전축에서 벗어나 돌아서 생기는 시차).
# 지역별 회전중심 탐색(§151)에서 오프셋 방향이 시간과 무관하게 일정(약 95~108도)이고 크기만 깊이별로
# 0~200px로 달라짐을 확인. 그래서 오프셋 s(px)를 일정 방향 e를 따라 바꿔가며 층별 월드맵을 만들고,
# 위치마다 국소 선명도가 최대인 층을 골라 합성(focus stack). 층 번호 = 상대 깊이(깊이 지도).
import sys

import h5py
import numpy as np
from scipy import ndimage as ndi

from delta_rotation_cmax import CX, CY, H5, WIN_MS

C = 1400
OFF = 200
ANGLE_DEG = 103.0
S_VALUES = np.arange(0, 281, 20)
STRIDE = 2
CHUNK = 4_000_000


def build_layers(th, mids):
    f = h5py.File(H5, "r")
    n = f["events/t"].shape[0]
    e = np.array([np.cos(np.radians(ANGLE_DEG)), np.sin(np.radians(ANGLE_DEG))])
    layers = np.zeros((len(S_VALUES), C, C), np.float32)
    for s0 in range(0, n, CHUNK * STRIDE):
        sl = slice(s0, s0 + CHUNK * STRIDE, STRIDE)
        x = f["events/x"][sl].astype(np.float64)
        y = f["events/y"][sl].astype(np.float64)
        t = f["events/t"][sl].astype(np.float64)
        a = -np.interp(t, mids, th)
        c, sn = np.cos(a), np.sin(a)
        for li, s in enumerate(S_VALUES):
            cx, cy = CX + s * e[0], CY + s * e[1]
            xr = cx + c * (x - cx) - sn * (y - cy)
            yr = cy + sn * (x - cx) + c * (y - cy)
            xi = np.rint(xr).astype(np.int64) + OFF
            yi = np.rint(yr).astype(np.int64) + OFF
            ok = (xi >= 0) & (xi < C) & (yi >= 0) & (yi < C)
            layers[li] += np.bincount(yi[ok] * C + xi[ok], minlength=C * C).reshape(C, C).astype(np.float32)
    return layers


def focus_stack(layers, sigma=8.0):
    sharp = np.zeros((len(layers), C, C), np.float32)
    for li, g in enumerate(layers):
        g = ndi.gaussian_filter(np.minimum(g, np.percentile(g[g > 0], 99.5)), 1.0)
        gy, gx = np.gradient(g)
        sharp[li] = ndi.gaussian_filter(gx * gx + gy * gy, sigma)
    best = sharp.argmax(0)
    comp = np.take_along_axis(layers, best[None], 0)[0]
    return comp, best, sharp.max(0)


if __name__ == "__main__":
    sp = sys.argv[1]
    th = np.load(sp + "/trk_theta.npy")
    mids = (np.arange(len(th)) * WIN_MS + WIN_MS / 2) * 1e3
    layers = build_layers(th, mids)
    np.save(sp + "/depth_layers.npy", layers)
    comp, best, _ = focus_stack(layers)
    np.save(sp + "/depth_comp.npy", comp)
    np.save(sp + "/depth_best.npy", best.astype(np.int8))
    print("layers done; offsets s:", list(S_VALUES))
    print("layer histogram (pixels with events):", np.bincount(best[comp > 0], minlength=len(S_VALUES)).tolist())
