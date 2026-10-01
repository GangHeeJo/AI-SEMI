#!/usr/bin/env python3
# §152: delta_depth_layers.py의 "위치마다 층 하나" 합성은 한 영역에 깊이가 다른 구조가 겹친 곳(선명도 곡선의
# 봉우리가 둘)에서 한쪽이 버려지거나 섞임. 이벤트 단위 깊이 할당으로 교체: 각 이벤트를 모든 층 s의 월드
# 위치에 투영해 그 위치의 층별 선명도맵 값이 최대인 층을 고르고, 그 위치 한 곳에만 한 번 누적(중복 없음).
import sys

import h5py
import numpy as np
from scipy import ndimage as ndi

import delta_depth_layers as dl
from delta_rotation_cmax import CX, CY, H5, WIN_MS

dl.S_VALUES = np.arange(0, 401, 20)  # 가까운 쪽 범위 확장(§151에서 280에 몰림)


def sharpness_maps(layers, sigma=3.0):
    out = np.zeros(layers.shape, np.float32)
    for li, g in enumerate(layers):
        g = ndi.gaussian_filter(np.minimum(g, np.percentile(g[g > 0], 99.5)), 1.0)
        gy, gx = np.gradient(g)
        out[li] = ndi.gaussian_filter(gx * gx + gy * gy, sigma)
    return out


def assign_events(th, mids, sharp):
    C, OFF = dl.C, dl.OFF
    SHIFT = 400                       # 공통 좌표계로 -s*e 이동 후 음수 방지용 여백
    CC = C + 2 * SHIFT
    e = np.array([np.cos(np.radians(dl.ANGLE_DEG)), np.sin(np.radians(dl.ANGLE_DEG))])
    f = h5py.File(H5, "r")
    n = f["events/t"].shape[0]
    comp = np.zeros(CC * CC, np.float32)
    chosen = np.zeros(len(dl.S_VALUES), np.int64)
    for s0 in range(0, n, dl.CHUNK * dl.STRIDE):
        sl = slice(s0, s0 + dl.CHUNK * dl.STRIDE, dl.STRIDE)
        x = f["events/x"][sl].astype(np.float64)
        y = f["events/y"][sl].astype(np.float64)
        t = f["events/t"][sl].astype(np.float64)
        a = -np.interp(t, mids, th)
        c, sn = np.cos(a), np.sin(a)
        best_v = np.full(len(x), -1.0, np.float32)
        best_pos = np.zeros(len(x), np.int64)          # 공통 좌표계 인덱스
        best_l = np.zeros(len(x), np.int64)
        for li, s in enumerate(dl.S_VALUES):
            cx, cy = CX + s * e[0], CY + s * e[1]
            xi = np.rint(cx + c * (x - cx) - sn * (y - cy)).astype(np.int64) + OFF
            yi = np.rint(cy + sn * (x - cx) + c * (y - cy)).astype(np.int64) + OFF
            ok = (xi >= 0) & (xi < C) & (yi >= 0) & (yi < C)
            pos = np.where(ok, yi * C + xi, 0)
            v = np.where(ok, sharp[li].ravel()[pos], -1.0)
            # 층 좌표계 -> 공통 좌표계(시차 원 중심): 층마다 s*e만큼 어긋나 있으므로 되돌림(§152 원인)
            xc = xi - int(round(s * e[0])) + SHIFT
            yc = yi - int(round(s * e[1])) + SHIFT
            posc = np.where(ok & (xc >= 0) & (xc < CC) & (yc >= 0) & (yc < CC), yc * CC + xc, -1)
            v = np.where(posc >= 0, v, -1.0)
            better = v > best_v
            best_v = np.where(better, v, best_v)
            best_pos = np.where(better, posc, best_pos)
            best_l = np.where(better, li, best_l)
        keep = best_v >= 0
        comp += np.bincount(best_pos[keep], minlength=CC * CC).astype(np.float32)
        chosen += np.bincount(best_l[keep], minlength=len(dl.S_VALUES))
    return comp.reshape(CC, CC), chosen


if __name__ == "__main__":
    sp = sys.argv[1]
    th = np.load(sp + "/trk_theta.npy")
    mids = (np.arange(len(th)) * WIN_MS + WIN_MS / 2) * 1e3
    layers = dl.build_layers(th, mids)
    np.save(sp + "/depth_layers21.npy", layers)
    print("layers built", flush=True)
    sharp = sharpness_maps(layers)
    comp, chosen = assign_events(th, mids, sharp)
    np.save(sp + "/depth_comp_events.npy", comp)
    print("events per layer (s=0..400 step 20):", chosen.tolist())
