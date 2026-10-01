#!/usr/bin/env python3
# §156: 보정(calibration) 기반 연속 깊이 월드맵. 영상 맞춤 상수 없음 -- 방향/중심/범위/층 간격은 전부
# delta_calibrate.py가 낸 JSON에서 읽고, 나머지 길이는 센서 크기에 대한 상대값.
#
# 핵심 식: 중심이 c0+s*e인 회전 == 이벤트를 센서좌표에서 s*e만큼 옮긴 뒤 c0 기준 회전(공통 좌표계)
#   u = R(-theta(t)) (p - c0 - s*e)     (s = 깊이를 나타내는 오프셋, 연속값)
# 1) 성긴 층(s_k = k*step, 보정이 준 간격)마다 맵 M_k를 공통 좌표계에 누적, 선명도맵 S_k
# 2) 픽셀별 깊이 s*(u) = argmax_k S_k 의 포물선 보간(연속값), 신뢰도 가중 가우시안 평활(normalized convolution)
# 3) 이벤트마다 성긴 층 중 가장 선명한 층 위치에서 s*를 읽어 연속 s로 한 번만 투영(복사본 없음)
import json
import sys

import h5py
import numpy as np
from scipy import ndimage as ndi

H5 = "Q&A/3차/extracted/2026-09-22-16-42-32-DELTA.h5"
W_PX, H_PX = 960, 720
STRIDE = 2
CHUNK = 4_000_000
SIGMA_SHARP = 0.008 * W_PX     # 센서 폭 대비 상대값
SIGMA_DEPTH = 0.010 * W_PX


def load_cal(path):
    c = json.load(open(path))
    assert c["valid"], "calibration invalid for this recording"
    e = np.array(c["unit_vector"], float)
    c0 = np.array(c["center_px"], float)
    step = float(c["layer_step_px"])
    smax = float(c["s_max_px"])
    ss = np.arange(0.0, smax + 2 * step, step)           # 마지막 층 너머 한 층(보간 여유)
    return e, c0, ss


def project(x, y, a, c0, e, s):
    """공통 좌표계 (c0 기준) 좌표 u = R(a)(p - c0 - s*e), a = -theta."""
    px = x - c0[0] - s * e[0]
    py = y - c0[1] - s * e[1]
    c, sn = np.cos(a), np.sin(a)
    return c * px - sn * py, sn * px + c * py


def events_iter(f, th, mids):
    n = f["events/t"].shape[0]
    for s0 in range(0, n, CHUNK * STRIDE):
        sl = slice(s0, s0 + CHUNK * STRIDE, STRIDE)
        x = f["events/x"][sl].astype(np.float64)
        y = f["events/y"][sl].astype(np.float64)
        t = f["events/t"][sl].astype(np.float64)
        yield x, y, -np.interp(t, mids, th)


def run(h5_path, theta_npy, cal_json, out_prefix, win_ms=4):
    e, c0, ss = load_cal(cal_json)
    th = np.load(theta_npy)
    mids = (np.arange(len(th)) * win_ms + win_ms / 2) * 1e3
    smax = ss[-1]
    C = int(2 * (0.5 * np.hypot(W_PX, H_PX) + 1.3 * smax)) // 2 * 2
    OFF = C / 2
    K = len(ss)
    print(f"layers s_k = {np.round(ss, 1).tolist()}  canvas {C}x{C}", flush=True)
    f = h5py.File(h5_path, "r")

    # 1) 성긴 층 맵
    M = np.zeros((K, C, C), np.float32)
    for x, y, a in events_iter(f, th, mids):
        for k, s in enumerate(ss):
            ux, uy = project(x, y, a, c0, e, s)
            xi = np.rint(ux + OFF).astype(np.int64); yi = np.rint(uy + OFF).astype(np.int64)
            ok = (xi >= 0) & (xi < C) & (yi >= 0) & (yi < C)
            M[k] += np.bincount(yi[ok] * C + xi[ok], minlength=C * C).reshape(C, C).astype(np.float32)
    print("pass1 maps done", flush=True)

    # 2) 선명도맵 + 연속 깊이 지도
    S = np.zeros_like(M)
    for k in range(K):
        g = ndi.gaussian_filter(np.minimum(M[k], np.percentile(M[k][M[k] > 0], 99.5)), 1.0)
        gy, gx = np.gradient(g)
        S[k] = ndi.gaussian_filter(gx * gx + gy * gy, SIGMA_SHARP)
    kb = S.argmax(0)
    km = np.clip(kb, 1, K - 2)
    sm1 = np.take_along_axis(S, (km - 1)[None], 0)[0]
    s0 = np.take_along_axis(S, km[None], 0)[0]
    sp1 = np.take_along_axis(S, (km + 1)[None], 0)[0]
    den = sm1 - 2 * s0 + sp1
    off = np.where(np.abs(den) > 1e-12, 0.5 * (sm1 - sp1) / den, 0.0)
    off = np.clip(off, -1, 1)
    step = ss[1] - ss[0]
    depth_raw = (km + off) * step
    depth_raw = np.where((kb == 0) | (kb == K - 1), kb * step, depth_raw)    # 끝층은 보간 안 함
    w = S.max(0)
    num = ndi.gaussian_filter(depth_raw * w, SIGMA_DEPTH)
    dd = ndi.gaussian_filter(w, SIGMA_DEPTH)
    depth = np.where(dd > 0, num / np.maximum(dd, 1e-20), 0.0).astype(np.float32)
    np.save(out_prefix + "_depth.npy", depth); np.save(out_prefix + "_conf.npy", w.astype(np.float32))
    print("depth map done; s range", float(depth[w > np.percentile(w, 50)].min()), float(depth[w > np.percentile(w, 50)].max()), flush=True)

    # 3) 이벤트별 연속 깊이로 한 번만 투영
    F = np.zeros(C * C, np.float32)
    for x, y, a in events_iter(f, th, mids):
        best_v = np.full(len(x), -1.0, np.float32)
        best_pos = np.zeros(len(x), np.int64)
        for k, s in enumerate(ss):
            ux, uy = project(x, y, a, c0, e, s)
            xi = np.rint(ux + OFF).astype(np.int64); yi = np.rint(uy + OFF).astype(np.int64)
            ok = (xi >= 0) & (xi < C) & (yi >= 0) & (yi < C)
            pos = np.where(ok, yi * C + xi, 0)
            v = np.where(ok, S[k].ravel()[pos], -1.0)
            better = v > best_v
            best_v = np.where(better, v, best_v)
            best_pos = np.where(better, pos, best_pos)
        keep = best_v >= 0
        s_ev = depth.ravel()[best_pos]                      # 가장 선명한 층 위치에서 읽은 연속 깊이
        ux, uy = project(x, y, a, c0, e, s_ev)
        xi = np.rint(ux + OFF).astype(np.int64); yi = np.rint(uy + OFF).astype(np.int64)
        ok = keep & (xi >= 0) & (xi < C) & (yi >= 0) & (yi < C)
        F += np.bincount(yi[ok] * C + xi[ok], minlength=C * C).astype(np.float32)
    np.save(out_prefix + "_final.npy", F.reshape(C, C))
    print("final map done", flush=True)


if __name__ == "__main__":
    # usage: delta_depthwarp.py <events.h5> <theta.npy> <calibration.json> <out_prefix>
    run(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])
