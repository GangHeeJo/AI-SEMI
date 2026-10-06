#!/usr/bin/env python3
# §214: 원심성 복사(efference copy) 쓰기 억제의 잠재 이득 측정. 월드 칸이 {valid, 마지막 극성}을 들고 있을 때, 이벤트가 칸의 현재 값과 같은 극성이면 쓰기를 생략할 수 있다.
# 실제 DELTA 롤 이벤트의 연속 구간(stride 1)을 같은 θ로 월드 칸(칸 크기 s px)에 보내, 칸의 직전 이벤트와 극성이 같은 비율(= 생략 가능한 쓰기)을 센다.
# 사용: redundant_write_measure.py <events.h5> <theta.npy> <calib.json> [frac_start=0.4] [n_events=8000000]
import sys

import h5py
import numpy as np

sys.path.insert(0, "scripts")
from delta_depthwarp2 import load_cal  # noqa: E402

C, OFF = 1200, 600.0


def main(h5p, th_npy, cal_json, start, n):
    _, c0, _, _ = load_cal(cal_json); th = np.load(th_npy); mids = (np.arange(len(th)) * 4 + 2) * 1e3
    f = h5py.File(h5p, "r"); n_all = f["events/t"].shape[0]; i0 = int(n_all * start); sl = slice(i0, i0 + n)
    x = f["events/x"][sl].astype(np.float64); y = f["events/y"][sl].astype(np.float64); t = f["events/t"][sl].astype(np.float64); p = f["events/p"][sl].astype(np.int8)
    a = -np.interp(t, mids, th); px = x - c0[0]; py = y - c0[1]; c, s_ = np.cos(a), np.sin(a)
    xi = np.rint(c * px - s_ * py + OFF).astype(np.int64); yi = np.rint(s_ * px + c * py + OFF).astype(np.int64); ok = (xi >= 0) & (xi < C) & (yi >= 0) & (yi < C)
    xi, yi, p, t = xi[ok], yi[ok], p[ok], t[ok]
    print(f"events {len(xi)} over {(t[-1] - t[0]) / 1e3:.0f} ms, theta change {np.degrees(abs(np.interp(t[-1], mids, th) - np.interp(t[0], mids, th))):.0f} deg")
    print(f"{'cell px':>8s} {'cells touched':>14s} {'redundant writes %':>20s} {'first-touch %':>14s} {'polarity-flip %':>16s}")
    for sz in (1, 2, 4, 8, 16, 32):
        cell = (yi // sz) * (C // sz + 1) + (xi // sz); o = np.lexsort((t, cell)); cs, ps = cell[o], p[o]
        first = np.r_[True, cs[1:] != cs[:-1]]; same = np.r_[False, ps[1:] == ps[:-1]] & ~first
        n_ev = len(cs); print(f"{sz:8d} {first.sum():14d} {same.sum() / n_ev * 100:20.1f} {first.sum() / n_ev * 100:14.1f} {(~first & ~same).sum() / n_ev * 100:16.1f}")




def cache_sweep(h5p, th_npy, cal_json, start=0.4, n=8000000):
    """작은 직접사상 캐시(항목 = 칸 번호 + 마지막으로 쓴 극성)로 중복 쓰기를 거르는 무손실 방식: 캐시에 같은 칸·같은 극성이 있으면 메모리에도 같은 값이 있으므로 쓰기 생략 가능."""
    import numba
    _, c0, _, _ = load_cal(cal_json); th = np.load(th_npy); mids = (np.arange(len(th)) * 4 + 2) * 1e3
    f = h5py.File(h5p, "r"); n_all = f["events/t"].shape[0]; i0 = int(n_all * start); sl = slice(i0, i0 + n)
    x = f["events/x"][sl].astype(np.float64); y = f["events/y"][sl].astype(np.float64); t = f["events/t"][sl].astype(np.float64); p = f["events/p"][sl].astype(np.int64)
    a = -np.interp(t, mids, th); px = x - c0[0]; py = y - c0[1]; c, s_ = np.cos(a), np.sin(a)
    xi = np.rint(c * px - s_ * py + OFF).astype(np.int64); yi = np.rint(s_ * px + c * py + OFF).astype(np.int64); ok = (xi >= 0) & (xi < C) & (yi >= 0) & (yi < C)
    xi, yi, p = xi[ok], yi[ok], p[ok]

    @numba.njit
    def run(cell, pol, nent):
        tag = -np.ones(nent, np.int64); pl = np.zeros(nent, np.int64); hit = 0
        for i in range(len(cell)):
            e = cell[i] % nent
            if tag[e] == cell[i] and pl[e] == pol[i]: hit += 1
            else: tag[e] = cell[i]; pl[e] = pol[i]
        return hit
    print(f"{'cell px':>8s} " + " ".join(f"{('cache ' + str(k)):>11s}" for k in (4, 16, 64, 256, 1024, 4096)) + "   (걸러진 쓰기 %)")
    for sz in (4, 8, 16, 32):
        cell = (yi // sz) * (C // sz + 1) + (xi // sz)
        print(f"{sz:8d} " + " ".join(f"{run(cell, p, k) / len(cell) * 100:11.1f}" for k in (4, 16, 64, 256, 1024, 4096)), flush=True)


if len(sys.argv) > 1 and sys.argv[-1] == "cache":
    cache_sweep(sys.argv[1], sys.argv[2], sys.argv[3])


if __name__ == "__main__" and sys.argv[-1] != "cache":
    main(sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4]) if len(sys.argv) > 4 else 0.4, int(sys.argv[5]) if len(sys.argv) > 5 else 8000000)
