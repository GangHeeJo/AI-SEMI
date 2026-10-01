#!/usr/bin/env python3
# §148: delta_rotation_cmax.py가 만든 omega(t)를 적분한 theta(t)로 모든 이벤트를 월드맵(회전중심 기준
# 역회전)에 누적하고, 보정 효과를 정량화한다. 정답이 없으므로 "앞 절반 시간의 맵"과 "뒤 절반 시간의
# 맵"이 서로 같은 장면을 같은 자리에 쌓는지(정규화 상관계수)와, 보정 전/후 맵의 집중도로 평가한다.
import sys

import h5py
import numpy as np

from delta_rotation_cmax import CX, CY, H5, WIN_MS

CANVAS = 1200  # 960x720 대각선(1200) 정사각 캔버스: 회전해도 모서리가 안 잘림
CHUNK = 4_000_000


def theta_of_t(res, t_us):
    """res[:,0]=창 시작ms, res[:,1]=omega(rad/s). 창 안은 선형 보간해 theta 적분."""
    starts = res[:, 0] * 1e3
    om = res[:, 1]
    cum = np.concatenate([[0.0], np.cumsum(om * WIN_MS * 1e-3)])
    w = np.clip(((t_us - starts[0]) // (WIN_MS * 1e3)).astype(np.int64), 0, len(om) - 1)
    frac = (t_us - starts[w]) / (WIN_MS * 1e3)
    return cum[w] + frac * om[w] * WIN_MS * 1e-3


def build_maps(res, correct=True, split_us=None):
    f = h5py.File(H5, "r")
    n = f["events/t"].shape[0]
    maps = [np.zeros(CANVAS * CANVAS, np.int32), np.zeros(CANVAS * CANVAS, np.int32)]
    off = CANVAS / 2
    for s in range(0, n, CHUNK):
        x = f["events/x"][s:s + CHUNK].astype(np.float64) - CX
        y = f["events/y"][s:s + CHUNK].astype(np.float64) - CY
        t = f["events/t"][s:s + CHUNK].astype(np.float64)
        a = -theta_of_t(res, t) if correct else np.zeros_like(t)
        c, sn = np.cos(a), np.sin(a)
        xi = np.rint(c * x - sn * y + off).astype(np.int64)
        yi = np.rint(sn * x + c * y + off).astype(np.int64)
        ok = (xi >= 0) & (xi < CANVAS) & (yi >= 0) & (yi < CANVAS)
        half = (t >= split_us).astype(np.int64)
        for h in (0, 1):
            k = ok & (half == h)
            maps[h] += np.bincount(yi[k] * CANVAS + xi[k], minlength=CANVAS * CANVAS).astype(np.int32)
    return [m.reshape(CANVAS, CANVAS) for m in maps]


def ncc(a, b):
    a = a.astype(np.float64).ravel(); b = b.astype(np.float64).ravel()
    a -= a.mean(); b -= b.mean()
    return float((a * b).sum() / np.sqrt((a * a).sum() * (b * b).sum()))


def blur(m, k=5):  # 간단 박스 블러(1칸 어긋남에 둔감하게)
    from numpy.lib.stride_tricks import sliding_window_view
    p = np.pad(m.astype(np.float32), k // 2)
    return sliding_window_view(p, (k, k)).mean(axis=(2, 3))


if __name__ == "__main__":
    res = np.load(sys.argv[1])
    split = 0.5 * 1.59e6
    for name, corr in (("no-correction", False), ("rotation-corrected", True)):
        a, b = build_maps(res, corr, split)
        print(f"{name}: NCC(first-half map, second-half map) raw={ncc(a, b):.4f} blur5={ncc(blur(a), blur(b)):.4f}"
              f"  events A={int(a.sum())} B={int(b.sum())}")
        np.save(sys.argv[2] + f"_{name}_A.npy", a); np.save(sys.argv[2] + f"_{name}_B.npy", b)
