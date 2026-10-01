#!/usr/bin/env python3
# §150: 번짐(고스팅) 원인 = 시간에 따라 체계적으로 변하는 잔차(회전 수도, 이동 수십px)임을 §149에서 확인.
# 전역 번들조정 방식 정합: 40ms 조각 맵마다 자유 변환(dTheta, dx, dy)을 두고, 각 조각을 "나머지 조각을
# 전부 합친 맵"에 반복 정합(자기 자신 제외 -> 자기참조 방지). 최종 맵은 이벤트 단위로 다시 쌓고
# (이벤트 수 고정이라 충돌확률 지표가 유효: 회전/이동은 면적을 안 바꿈) 기준과 비교한다.
import sys

import h5py
import numpy as np
from scipy import ndimage as ndi

from delta_rotation_cmax import H5, WIN_MS

C = 1000
OFF = C / 2
CHUNK_MS = 40
T0, T1 = 240, 1560
ITERS = 4
yy, xx = np.mgrid[:C, :C]
DISC = ((xx - OFF) ** 2 + (yy - OFF) ** 2) < 340 ** 2


def load_chunk_events(f, m, t0):
    s, e = m[t0], m[t0 + CHUNK_MS]
    return (f["events/x"][s:e].astype(np.float64) - 480, f["events/y"][s:e].astype(np.float64) - 360,
            f["events/t"][s:e].astype(np.float64))


def project(x, y, a, dx=0.0, dy=0.0):
    c, s = np.cos(a), np.sin(a)
    xi = np.rint(c * x - s * y + OFF + dx).astype(np.int64)
    yi = np.rint(s * x + c * y + OFF + dy).astype(np.int64)
    return xi, yi, (xi >= 0) & (xi < C) & (yi >= 0) & (yi < C)


def raw_map(ev, th, mids):
    x, y, t = ev
    xi, yi, ok = project(x, y, -np.interp(t, mids, th))
    return np.bincount(yi[ok] * C + xi[ok], minlength=C * C).reshape(C, C).astype(np.float32)


def bandpass(g):
    g = np.minimum(g, np.percentile(g[g > 0], 99)) if (g > 0).any() else g
    return (ndi.gaussian_filter(g, 1.5) - ndi.gaussian_filter(g, 10)) * DISC


def xcorr(a, b):
    r = np.fft.fftshift(np.fft.irfft2(np.fft.rfft2(a) * np.conj(np.fft.rfft2(b)), s=a.shape))
    k = np.unravel_index(r.argmax(), r.shape)
    return float(r[k] / (np.sqrt((a * a).sum() * (b * b).sum()) + 1e-9)), (k[1] - C // 2, k[0] - C // 2)


def transform(g, dth_deg, dx, dy):
    return ndi.shift(ndi.rotate(g, dth_deg, reshape=False, order=1), (dy, dx), order=1)


def collision(ev_list, th, mids, params, sgn_th, sgn_xy):
    cnt = np.zeros(C * C)
    for (x, y, t), (dth, dx, dy) in zip(ev_list, params):
        xi, yi, ok = project(x, y, -np.interp(t, mids, th) + sgn_th * np.radians(dth), sgn_xy * dx, sgn_xy * dy)
        cnt += np.bincount(yi[ok] * C + xi[ok], minlength=C * C)
    n = cnt.sum()
    return float((cnt * (cnt - 1)).sum() / (n * (n - 1)) * 1e6), cnt.reshape(C, C)


if __name__ == "__main__":
    sp = sys.argv[1]
    th = np.load(sp + "/trk_theta.npy")
    mids = (np.arange(len(th)) * WIN_MS + WIN_MS / 2) * 1e3
    f = h5py.File(H5, "r")
    m = f["ms_to_idx"][:].astype(np.int64)
    starts = list(range(T0, T1, CHUNK_MS))
    evs = [load_chunk_events(f, m, t0) for t0 in starts]
    base = [raw_map(ev, th, mids) for ev in evs]
    bp = [bandpass(g) for g in base]
    params = [(0.0, 0, 0)] * len(starts)
    for it in range(ITERS):
        cur = [transform(b, *p) for b, p in zip(bp, params)]
        total = sum(cur)
        new = []
        for k, b in enumerate(bp):
            ref = total - cur[k]
            best = (-1, params[k])
            for dth in np.arange(params[k][0] - 2, params[k][0] + 2.01, 0.5):
                v, (dx, dy) = xcorr(ndi.rotate(b, dth, reshape=False, order=1) * DISC, ref)
                if v > best[0]:
                    best = (v, (float(dth), dx, dy))
            new.append(best[1])
        params = new
        print(f"iter {it}: mean |dth| {np.mean([abs(p[0]) for p in params]):.2f} mean |shift| {np.mean([np.hypot(p[1], p[2]) for p in params]):.1f}px", flush=True)
    np.save(sp + "/global_params.npy", np.array(params))
    print("starts", starts)
    print("params (dth, dx, dy):", [tuple(round(v, 1) for v in p) for p in params])
    zero = [(0.0, 0, 0)] * len(starts)
    print("baseline collision:", round(collision(evs, th, mids, zero, 1, 1)[0], 3), flush=True)
    best_sign, best_v = None, -1
    for sg_th in (-1, 1):
        for sg_xy in (-1, 1):
            v, _ = collision(evs, th, mids, params, sg_th, sg_xy)
            print(f"  sign_theta={sg_th:+d} sign_shift={sg_xy:+d}: {v:.3f}", flush=True)
            if v > best_v:
                best_v, best_sign = v, (sg_th, sg_xy)
    v, cnt = collision(evs, th, mids, params, *best_sign)
    np.save(sp + "/global_map.npy", cnt)
    print("best signs", best_sign, "collision", round(v, 3))
