#!/usr/bin/env python3
# §209: 협동 네트워크(뉴로모픽 차용)를 roll 파이프라인에 적용. 1단계 = 극성 증거 P1(depth_polarity_experiment와 동일). 일치한 이벤트가 자기 층의 지도 위치에 투표한
# 층별 부피 V[극성][구간][층][위치]를 만들고 협동 네트워크(같은 층 이웃 흥분 + 같은 위치 다른 층(+-2층 밖) 억제, 정규화 반복)를 적용한 뒤,
# 2단계에서 이벤트는 자기 구간을 뺀 두 구간의 협동 부피(같은 극성)에서 증거를 얻어 층을 다시 고르고 두 선택이 +-1층 안에서 일치한 것만 채택.
# 합성 정답이 있으면 층 정확도/NCC/잔상 질량 보고, truth를 'none'으로 주면(실제 영상) 일치율만 보고.
# 사용: depth_coop_roll.py <events.h5> <theta.npy> <calib.json> <truth.npz|none> [b=0.25] (환경변수 DELTA_RHO, SNAP_STRIDE)
import json
import os
import sys

import h5py
import numpy as np
from scipy import ndimage as ndi

import depth_polarity_experiment as dp
from delta_depthwarp2 import load_cal, sharp_of
import delta_depthwarp2 as dw2
from ghost_metric import ghost

W_PX, H_PX, G = 960, 720, 3


def coop_volume(V, b, a=1.0, sig=2.0, iters=4):                                             # V: (K, C, C)
    K_ = V.shape[0]; pos = V[V > 0]; L0 = V / max(float(np.percentile(pos, 99.5)) if pos.size else 1.0, 1e-9); S = L0.copy()
    for _ in range(iters):
        E = ndi.gaussian_filter(S, (0.7, sig, sig)); near = ndi.uniform_filter1d(S, size=5, axis=0) * 5; I = np.maximum(S.sum(0, keepdims=True) - near, 0) / max(K_ - 5, 1) * 10
        S = np.maximum(L0 + a * E - b * I, 0); pos = S[S > 0]; S = S / max(float(np.percentile(pos, 99.5)) if pos.size else 1.0, 1e-9)
    return S


def run(h5p, th_npy, cal_json, truth_npz, b):
    dw2.SIGMA_SHARP = 3.0; STRIDE = dp.STRIDE
    e, c0, _, smax = load_cal(cal_json); cal = json.load(open(cal_json)); fwhm = float(cal["fwhm_median_px"]); step = fwhm / 6.0
    ss = np.arange(min(0.0, float(cal["s_min_px"])) - step, smax + fwhm, step); K = len(ss)
    C = int(2 * (0.5 * np.hypot(W_PX, H_PX) + max(abs(ss[0]), abs(ss[-1])))) // 2 * 2; OFF = C / 2
    th = np.load(th_npy); mids = (np.arange(len(th)) * 4 + 2) * 1e3; f = h5py.File(h5p, "r"); t_end = float(f["events/t"][-1])
    truth = None if truth_npz == "none" else dict(np.load(truth_npz))
    if truth is not None:
        e_t = np.array([np.cos(np.radians(float(truth["e_deg"]))), np.sin(np.radians(float(truth["e_deg"])))]); c0_t = truth["c0"]; s_all = f["events/s_true"][::STRIDE].astype(np.float64)
    group = lambda t: np.minimum((t / (t_end + 1) * G).astype(np.int64), G - 1)

    def canvas(x, y, a, s):
        px = x - c0[0] - s * e[0]; py = y - c0[1] - s * e[1]; c, sn = np.cos(a), np.sin(a)
        xi = np.rint(c * px - sn * py + OFF).astype(np.int64); yi = np.rint(sn * px + c * py + OFF).astype(np.int64); ok = (xi >= 0) & (xi < C) & (yi >= 0) & (yi < C)
        return np.where(ok, yi * C + xi, -1)

    print(f"layers {K} step {step:.1f}px canvas {C} stride {STRIDE}, coop b={b}", flush=True)
    M = np.zeros((2, G, K, C * C), np.float32)
    for x, y, a, t, p in dp.chunks_tp(f, th, mids):
        ig = group(t)
        for k, s in enumerate(ss):
            q = canvas(x, y, a, s)
            for j in range(G):
                for pol in (0, 1): M[pol, j, k] += np.bincount(q[(q >= 0) & (ig == j) & (p == pol)], minlength=C * C)
    S1 = np.zeros((2, G, K, C * C), np.float32)                                              # 극성별 선명도(1단계 증거)
    for j in range(G):
        for k in range(K):
            for pol in (0, 1): S1[pol, j, k] = sharp_of(M[pol, j, k].reshape(C, C)).ravel()
    del M; print("stage-1 sharpness done", flush=True)

    def select(arrs, x, y, a, ig, p, valid, P):                                              # arrs[pol][g] -> (K, 위치); 같은 극성 증거, 자기 구간 제외 두 증거
        n = len(x); Pc = np.maximum(P, 0); out = []
        for dgap in (1, 2):
            V = np.empty((K, n), np.float32)
            for k in range(K):
                v = np.full(n, -1.0, np.float32)
                for pol in (0, 1):
                    for j in range(G):
                        m = (p == pol) & (((ig + dgap) % G) == j)
                        if m.any(): v[m] = arrs[pol][j][k][Pc[k][m]]
                V[k] = np.where(valid[k], v, -1.0)
            out.append(V)
        Va, Vb = out; Vs = Va + Vb; kc = Vs.argmax(0); agree = (np.abs(Va.argmax(0) - Vb.argmax(0)) <= 1) & (Vs.max(0) > 0); return kc, agree, Vs

    res = {}
    def new_acc(name): res[name] = dict(kept=0, corr=0, den=0, corr_all=0, den_all=0, map=np.zeros(C * C, np.float32), total=0)

    def account(name, x, y, a, kc, agree, Vs, st, s_exp):
        km = np.clip(kc, 1, K - 2); vm = np.take_along_axis(Vs, (km - 1)[None], 0)[0]; v0 = np.take_along_axis(Vs, km[None], 0)[0]; vp = np.take_along_axis(Vs, (km + 1)[None], 0)[0]; den = vm - 2 * v0 + vp
        with np.errstate(divide="ignore", invalid="ignore"): off = np.where(np.abs(den) > 1e-30, 0.5 * (vm - vp) / den, 0.0)
        off = np.clip(np.nan_to_num(off), -0.5, 0.5) * ((kc > 0) & (kc < K - 1)); sc = ss[kc] + off * step; pos = canvas(x, y, a, sc); okp = (pos >= 0) & (Vs.max(0) > 0); ag = agree & okp
        r = res[name]; r["map"] += np.bincount(pos[ag], minlength=C * C); r["kept"] += int(ag.sum()); r["total"] += len(x)
        if st is not None:
            hit = np.abs(sc - s_exp) <= step; vd = st >= 0; r["den"] += int((ag & vd).sum()); r["corr"] += int((hit & ag & vd).sum()); r["den_all"] += int((okp & vd).sum()); r["corr_all"] += int((hit & okp & vd).sum())

    for nm in ("P1 (stage 1)", "P1 + coop (stage 2)"): new_acc(nm)
    Vol = np.zeros((2, G, K, C * C), np.float32); n_off = 0; chunk_cache = []
    for x, y, a, t, p in dp.chunks_tp(f, th, mids):
        n = len(x); ig = group(t); P = np.stack([canvas(x, y, a, s) for s in ss]); valid = P >= 0
        st = s_exp = None
        if truth is not None: st = s_all[n_off:n_off + n]; n_off += n; s_exp = ((c0_t - c0)[None, :] + np.maximum(st, 0)[:, None] * e_t[None, :]) @ e
        kc, agree, Vs = select(S1, x, y, a, ig, p, valid, P); account("P1 (stage 1)", x, y, a, kc, agree, Vs, st, s_exp)
        pos_k = P[kc, np.arange(n)]; m = agree & (pos_k >= 0)                                  # 일치한 이벤트만 자기 층의 지도 위치에 투표
        for pol in (0, 1):
            for j in range(G):
                mm = m & (p == pol) & (ig == j); np.add.at(Vol[pol, j], (kc[mm], pos_k[mm]), 1)           # Vol[pol, j]: (K, C*C), 같은 칸 중복 투표는 add.at로 누적
    del S1; print("stage-1 done; building cooperative volumes", flush=True)
    Vs2 = np.zeros((2, G, K, C * C), np.float32)
    for pol in (0, 1):
        for j in range(G): Vs2[pol, j] = coop_volume(Vol[pol, j].reshape(K, C, C), b).reshape(K, C * C)
    del Vol; print("cooperative volumes done", flush=True); n_off = 0
    for x, y, a, t, p in dp.chunks_tp(f, th, mids):
        n = len(x); ig = group(t); P = np.stack([canvas(x, y, a, s) for s in ss]); valid = P >= 0
        st = s_exp = None
        if truth is not None: st = s_all[n_off:n_off + n]; n_off += n; s_exp = ((c0_t - c0)[None, :] + np.maximum(st, 0)[:, None] * e_t[None, :]) @ e
        kc, agree, Vs = select(Vs2, x, y, a, ig, p, valid, P); account("P1 + coop (stage 2)", x, y, a, kc, agree, Vs, st, s_exp)
    print(f"{'method':22s}{'kept %':>8s}")
    for nm, r in res.items():
        line = f"{nm:22s}{r['kept'] / r['total'] * 100:8.1f}"
        if truth is not None:
            pr, cv, nn, _ = ghost(r["map"].reshape(C, C), truth); line += f"  layer acc (agreed) {r['corr'] / max(r['den'], 1) * 100:5.1f}%  (all events) {r['corr_all'] / max(r['den_all'], 1) * 100:5.1f}%  NCC {nn:.3f}  ghost {(1 - pr) * 100:4.1f}%  coverage {cv * 100:4.1f}%"
        print(line, flush=True)


if __name__ == "__main__":
    run(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], float(sys.argv[5]) if len(sys.argv) > 5 else 0.25)
