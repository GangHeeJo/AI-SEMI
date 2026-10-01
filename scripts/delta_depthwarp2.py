#!/usr/bin/env python3
# §156 v2: 보정 기반 연속 깊이 월드맵 -- 범위 자동 확장 + coarse-to-fine 깊이 정밀화 + 좁은 평활.
# 영상 맞춤 상수 없음(방향/중심/초기 범위/초기 간격은 보정 JSON, 길이 상수는 센서 폭 대비 상대값).
#
# 공통 좌표계: u = R(-theta)(p - c0 - s*e). 참 깊이 s*인 점은 s가 달라도 중심은 그대로(참 위치 q)이고
# 번짐 반경만 |s - s*| 이라, 같은 픽셀에서 여러 s의 선명도를 비교하는 것이 유효하다.
#  A) 성긴 층으로 시작(보정 간격). 마지막 층에 몰리면 층 추가(범위 확장).
#  B) 이벤트별 깊이 s_ev 초기화(가장 선명한 층 위치에서 연속 깊이 읽기)
#  C) 반복 r: h = step/2^r, 맵 3개(s_ev-h, s_ev, s_ev+h) -> 픽셀별 포물선 -> 깊이 갱신 -> s_ev 갱신
#  D) 최종 맵(전체 이벤트) + 신뢰 이벤트 맵(선명도 상위, 잡음 억제)
import json
import sys

import h5py
import numpy as np
from scipy import ndimage as ndi

W_PX, H_PX = 960, 720
STRIDE = 2
CHUNK = 4_000_000
SIGMA_SHARP = 0.008 * W_PX
SIGMA_DEPTH = 0.004 * W_PX
SAT_FRAC = 0.03          # 마지막 층 포화 허용 비율(범위 확장 판정)
K_MAX = 12
N_REFINE = 3


def load_cal(path):
    c = json.load(open(path))
    assert c["valid"], "calibration invalid for this recording"
    return np.array(c["unit_vector"], float), np.array(c["center_px"], float), float(c["layer_step_px"]), float(c["s_max_px"])


def chunks(f, th, mids):
    n = f["events/t"].shape[0]
    for s0 in range(0, n, CHUNK * STRIDE):
        sl = slice(s0, s0 + CHUNK * STRIDE, STRIDE)
        x = f["events/x"][sl].astype(np.float64)
        y = f["events/y"][sl].astype(np.float64)
        t = f["events/t"][sl].astype(np.float64)
        yield x, y, -np.interp(t, mids, th)


def to_canvas(x, y, a, c0, e, s, OFF, C):
    px = x - c0[0] - s * e[0]
    py = y - c0[1] - s * e[1]
    c, sn = np.cos(a), np.sin(a)
    xi = np.rint(c * px - sn * py + OFF).astype(np.int64)
    yi = np.rint(sn * px + c * py + OFF).astype(np.int64)
    ok = (xi >= 0) & (xi < C) & (yi >= 0) & (yi < C)
    return np.where(ok, yi * C + xi, -1)


def sharp_of(M):
    g = ndi.gaussian_filter(np.minimum(M, np.percentile(M[M > 0], 99.5)), 1.0)
    gy, gx = np.gradient(g)
    return ndi.gaussian_filter(gx * gx + gy * gy, SIGMA_SHARP).astype(np.float32)


def parabola(Sm, S0, Sp):
    den = Sm - 2 * S0 + Sp
    with np.errstate(divide="ignore", invalid="ignore"):
        off = np.where(np.abs(den) > 1e-20, 0.5 * (Sm - Sp) / den, 0.0)
    return np.clip(np.nan_to_num(off), -1, 1)


def smooth_depth(d, w):
    num = ndi.gaussian_filter(d * w, SIGMA_DEPTH)
    den = ndi.gaussian_filter(w, SIGMA_DEPTH)
    return np.where(den > 0, num / np.maximum(den, 1e-30), 0.0).astype(np.float32)


def run(h5_path, theta_npy, cal_json, out_prefix, win_ms=4):
    e, c0, step, smax0 = load_cal(cal_json)
    th = np.load(theta_npy)
    mids = (np.arange(len(th)) * win_ms + win_ms / 2) * 1e3
    f = h5py.File(h5_path, "r")
    ss = list(np.arange(0.0, smax0 + 2 * step, step))
    # |u| <= |p - c0| + s 이므로 최대 층까지 포함하는 고정 캔버스
    C = int(2 * (0.5 * np.hypot(W_PX, H_PX) + step * (K_MAX - 1))) // 2 * 2; OFF = C / 2
    print(f"canvas {C}x{C}", flush=True)

    def layer_maps(s_list):
        Ms = {s: np.zeros(C * C, np.float32) for s in s_list}
        for x, y, a in chunks(f, th, mids):
            for s in s_list:
                p = to_canvas(x, y, a, c0, e, s, OFF, C)
                Ms[s] += np.bincount(p[p >= 0], minlength=C * C).astype(np.float32)
        return {s: sharp_of(Ms[s].reshape(C, C)) for s in s_list}

    # A) 성긴 층 + 범위 자동 확장
    S = layer_maps(ss)
    while True:
        stack = np.stack([S[s] for s in ss])
        kb = stack.argmax(0); w = stack.max(0)
        covered = stack.min(0) > 0                      # 모든 층에서 이벤트가 닿는 픽셀만 비교(가장자리 커버리지 인공물 제외)
        conf = covered & (w > np.median(w[covered]))
        frac = float((kb[conf] == len(ss) - 1).mean())
        print(f"layers {len(ss)} (s up to {ss[-1]:.0f}), last-layer fraction {frac:.3f}", flush=True)
        if frac <= SAT_FRAC or len(ss) >= K_MAX:
            break
        new = [ss[-1] + step, ss[-1] + 2 * step]
        S.update(layer_maps(new)); ss += new
    K = len(ss)
    km = np.clip(kb, 1, K - 2)
    off = parabola(np.take_along_axis(stack, (km - 1)[None], 0)[0], np.take_along_axis(stack, km[None], 0)[0],
                   np.take_along_axis(stack, (km + 1)[None], 0)[0])
    depth = np.where((kb == 0) | (kb == K - 1), kb * step, (km + off) * step).astype(np.float32)
    depth = smooth_depth(depth, w)
    del stack

    # B) 이벤트별 깊이 초기화: 성긴 층 중 가장 선명한 위치의 연속 깊이
    s_ev = []
    Sk = S                                                   # 초기화용 선명도(층별, A에서 계산한 것 재사용)
    for x, y, a in chunks(f, th, mids):
        best_v = np.full(len(x), -1.0, np.float32); best_p = np.zeros(len(x), np.int64)
        for s in ss:
            p = to_canvas(x, y, a, c0, e, s, OFF, C)
            v = np.where(p >= 0, Sk[s].ravel()[np.maximum(p, 0)], -1.0)
            better = v > best_v
            best_v = np.where(better, v, best_v); best_p = np.where(better, np.maximum(p, 0), best_p)
        s_ev.append(depth.ravel()[best_p].astype(np.float32))
    del Sk
    print("init per-event depth done", flush=True)

    # C) coarse-to-fine 정밀화
    for r in range(1, N_REFINE + 1):
        h = step / (2 ** r)
        Ms = {d_: np.zeros(C * C, np.float32) for d_ in (-h, 0.0, h)}
        for (x, y, a), se in zip(chunks(f, th, mids), s_ev):
            for d_ in Ms:
                ux_s = se + d_
                px = x - c0[0] - ux_s * e[0]; py = y - c0[1] - ux_s * e[1]
                c, sn = np.cos(a), np.sin(a)
                xi = np.rint(c * px - sn * py + OFF).astype(np.int64); yi = np.rint(sn * px + c * py + OFF).astype(np.int64)
                ok = (xi >= 0) & (xi < C) & (yi >= 0) & (yi < C)
                Ms[d_] += np.bincount(yi[ok] * C + xi[ok], minlength=C * C).astype(np.float32)
        Sm, S0, Sp = (sharp_of(Ms[d_].reshape(C, C)) for d_ in (-h, 0.0, h))
        w = np.maximum(np.maximum(Sm, S0), Sp)
        depth = smooth_depth(depth + parabola(Sm, S0, Sp) * h, w)
        new_se = []
        for (x, y, a), se in zip(chunks(f, th, mids), s_ev):
            p = to_canvas(x, y, a, c0, e, se, OFF, C)
            new_se.append(np.where(p >= 0, depth.ravel()[np.maximum(p, 0)], se).astype(np.float32))
        s_ev = new_se
        print(f"refine {r}: h={h:.1f}px done", flush=True)

    # D) 최종 맵
    F = np.zeros(C * C, np.float32); Fc = np.zeros(C * C, np.float32)
    thr = float(np.percentile(w[w > 0], 50))
    for (x, y, a), se in zip(chunks(f, th, mids), s_ev):
        px = x - c0[0] - se * e[0]; py = y - c0[1] - se * e[1]
        c, sn = np.cos(a), np.sin(a)
        xi = np.rint(c * px - sn * py + OFF).astype(np.int64); yi = np.rint(sn * px + c * py + OFF).astype(np.int64)
        ok = (xi >= 0) & (xi < C) & (yi >= 0) & (yi < C)
        pos = yi[ok] * C + xi[ok]
        F += np.bincount(pos, minlength=C * C).astype(np.float32)
        good = w.ravel()[pos] >= thr                          # 선명도 상위 이벤트만(잡음 억제)
        Fc += np.bincount(pos[good], minlength=C * C).astype(np.float32)
    np.save(out_prefix + "_final.npy", F.reshape(C, C)); np.save(out_prefix + "_final_conf.npy", Fc.reshape(C, C))
    np.save(out_prefix + "_depth.npy", depth); np.save(out_prefix + "_wconf.npy", w)
    print("done", flush=True)


if __name__ == "__main__":
    # usage: delta_depthwarp2.py <events.h5> <theta.npy> <calibration.json> <out_prefix>
    run(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])
