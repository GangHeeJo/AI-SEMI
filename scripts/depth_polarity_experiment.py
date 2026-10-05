#!/usr/bin/env python3
# §197: 극성(ON/OFF) 일관성을 깊이 층 증거에 추가. 에지 하나의 이벤트는 같은 이동 방향에서 같은 극성을 가지므로, 틀린 층으로 옮겨 다른 에지에 겹쳐도 극성이 다르면 걸러진다.
# G=3 시간 구간(구간 g의 이벤트는 나머지 두 구간의 증거로 평가), 두 복제본이 +-1층 안에서 일치하면 채택(기존과 같은 판정). 증거만 바꾼다:
#   A   총 선명도(기존)
#   P1  자기와 같은 극성 지도의 선명도
#   P2  총 선명도 x 극성 순도 S_same/(S_same+S_opp)
# 합성 정답이 있으면 층 정확도/NCC/잔상 질량 보고, truth를 'none'으로 주면(실제 영상) 일치율과 층 분포만 보고.
# 사용: depth_polarity_experiment.py <events.h5> <theta.npy> <calib.json> <truth.npz|none>   (환경변수 DELTA_RHO, SNAP_STRIDE; 극성 규약 p=1이 ON)
import json
import os
import sys

import h5py
import numpy as np

import delta_depthwarp2 as dw2
STRIDE = int(os.environ.get("SNAP_STRIDE", "8")); dw2.STRIDE = STRIDE; RHO = float(os.environ.get("DELTA_RHO", "0"))
from delta_depthwarp2 import load_cal, sharp_of  # noqa: E402
from ghost_metric import ghost  # noqa: E402

W_PX, H_PX, G = 960, 720, 3


def chunks_tp(f, th, mids):
    n = f["events/t"].shape[0]
    for s0 in range(0, n, 1_000_000 * STRIDE):
        sl = slice(s0, s0 + 1_000_000 * STRIDE, STRIDE)
        x = f["events/x"][sl].astype(np.float64); y = f["events/y"][sl].astype(np.float64); t = f["events/t"][sl].astype(np.float64); p = f["events/p"][sl].astype(np.int64)
        t = t + (x / 960.0 - 0.5) * RHO * 773.0
        yield x, y, -np.interp(t, mids, th), t, p


def run(h5p, th_npy, cal_json, truth_npz):
    dw2.SIGMA_SHARP = 3.0
    e, c0, _, smax = load_cal(cal_json); cal = json.load(open(cal_json)); fwhm = float(cal["fwhm_median_px"]); step = fwhm / 6.0
    ss = np.arange(min(0.0, float(cal["s_min_px"])) - step, smax + fwhm, step); K = len(ss)
    C = int(2 * (0.5 * np.hypot(W_PX, H_PX) + max(abs(ss[0]), abs(ss[-1])))) // 2 * 2; OFF = C / 2
    th = np.load(th_npy); mids = (np.arange(len(th)) * 4 + 2) * 1e3; f = h5py.File(h5p, "r"); t_end = float(f["events/t"][-1])
    truth = None if truth_npz == "none" else dict(np.load(truth_npz))
    if truth is not None:
        e_t = np.array([np.cos(np.radians(float(truth["e_deg"]))), np.sin(np.radians(float(truth["e_deg"])))]); c0_t = truth["c0"]; s_all = f["events/s_true"][::STRIDE].astype(np.float64)
    group = lambda t: np.minimum((t / (t_end + 1) * G).astype(np.int64), G - 1)
    print(f"layers {K} step {step:.1f}px canvas {C} stride {STRIDE}", flush=True)
    def canvas(x, y, a, s):
        px = x - c0[0] - s * e[0]; py = y - c0[1] - s * e[1]; c, sn = np.cos(a), np.sin(a)
        xi = np.rint(c * px - sn * py + OFF).astype(np.int64); yi = np.rint(sn * px + c * py + OFF).astype(np.int64); ok = (xi >= 0) & (xi < C) & (yi >= 0) & (yi < C)
        return np.where(ok, yi * C + xi, -1)
    M = np.zeros((2, G, K, C * C), np.float32)                                                  # [극성(0=OFF,1=ON), 구간, 층, 위치]
    for x, y, a, t, p in chunks_tp(f, th, mids):
        ig = group(t)
        for k, s in enumerate(ss):
            q = canvas(x, y, a, s)
            for j in range(G):
                for pol in (0, 1): M[pol, j, k] += np.bincount(q[(q >= 0) & (ig == j) & (p == pol)], minlength=C * C)
    St = np.zeros((G, K, C * C), np.float32); So = np.zeros_like(St); Sf = np.zeros_like(St)
    for j in range(G):
        for k in range(K):
            So[j, k] = sharp_of(M[1, j, k].reshape(C, C)).ravel(); Sf[j, k] = sharp_of(M[0, j, k].reshape(C, C)).ravel(); St[j, k] = sharp_of((M[0, j, k] + M[1, j, k]).reshape(C, C)).ravel()
    del M; print("sharpness done", flush=True)
    methods = ["A", "P1", "P2"]; maps = {m: np.zeros(C * C, np.float32) for m in methods}; mall = {m: np.zeros(C * C, np.float32) for m in methods}
    kept = dict.fromkeys(methods, 0); correct = dict.fromkeys(methods, 0); denom = dict.fromkeys(methods, 0); correct_all = dict.fromkeys(methods, 0); denom_all = dict.fromkeys(methods, 0); total = 0; n_off = 0; hist = {m: np.zeros(K, np.int64) for m in methods}
    for x, y, a, t, p in chunks_tp(f, th, mids):
        n = len(x); total += n; ig = group(t); P = np.stack([canvas(x, y, a, s) for s in ss]); valid = P >= 0; Pc = np.maximum(P, 0)
        Gt = np.empty((G, K, n), np.float32); Gs = np.empty((G, K, n), np.float32); Go = np.empty((G, K, n), np.float32)
        for j in range(G):
            for k in range(K):
                Gt[j, k] = St[j, k][Pc[k]]; so = So[j, k][Pc[k]]; sf = Sf[j, k][Pc[k]]; Gs[j, k] = np.where(p == 1, so, sf); Go[j, k] = np.where(p == 1, sf, so)
        pur = Gt * Gs / (Gs + Go + 1e-12)
        def others(Garr):
            Gn = Garr.transpose(2, 0, 1); out = [np.take_along_axis(Gn, ((ig + d) % G)[:, None, None], 1)[:, 0, :].T for d in (1, 2)]
            return np.where(valid, out[0], -1.0), np.where(valid, out[1], -1.0)
        if truth is not None: st = s_all[n_off:n_off + n]; n_off += n; s_exp = ((c0_t - c0)[None, :] + np.maximum(st, 0)[:, None] * e_t[None, :]) @ e
        for name, arr in (("A", Gt), ("P1", Gs), ("P2", pur)):
            Va, Vb = others(arr); V = Va + Vb; kc = V.argmax(0); agree = np.abs(Va.argmax(0) - Vb.argmax(0)) <= 1
            km = np.clip(kc, 1, K - 2); vm = np.take_along_axis(V, (km - 1)[None], 0)[0]; v0 = np.take_along_axis(V, km[None], 0)[0]; vp = np.take_along_axis(V, (km + 1)[None], 0)[0]; den = vm - 2 * v0 + vp
            with np.errstate(divide="ignore", invalid="ignore"): off = np.where(np.abs(den) > 1e-30, 0.5 * (vm - vp) / den, 0.0)
            off = np.clip(np.nan_to_num(off), -0.5, 0.5) * ((kc > 0) & (kc < K - 1)); sc = ss[kc] + off * step; pos = canvas(x, y, a, sc); okp = (pos >= 0) & (V.max(0) > 0); ag = agree & okp
            maps[name] += np.bincount(pos[ag], minlength=C * C); mall[name] += np.bincount(pos[okp], minlength=C * C); kept[name] += int(ag.sum()); hist[name] += np.bincount(kc[ag], minlength=K)
            if truth is not None:
                hit = np.abs(sc - s_exp) <= step; vd = st >= 0; denom[name] += int((ag & vd).sum()); correct[name] += int((hit & ag & vd).sum()); denom_all[name] += int((okp & vd).sum()); correct_all[name] += int((hit & okp & vd).sum())
    if truth is None:
        print(f"{'method':8s}{'agreed %':>10s}"); [print(f"{m:8s}{kept[m] / total * 100:10.1f}") for m in methods]
    else:
        print(f"{'method':8s}{'kept %':>8s}{'agreed-layer acc %':>20s}{'all-event acc %':>17s}{'NCC (kept)':>12s}{'NCC (all)':>11s}{'ghost % (kept)':>16s}{'cover %':>9s}")
        for m in methods:
            pr, cv, nn, _ = ghost(maps[m].reshape(C, C), truth); pa = ghost(mall[m].reshape(C, C), truth)
            print(f"{m:8s}{kept[m] / total * 100:8.1f}{correct[m] / max(denom[m], 1) * 100:20.1f}{correct_all[m] / max(denom_all[m], 1) * 100:17.1f}{nn:12.3f}{pa[2]:11.3f}{(1 - pr) * 100:16.1f}{cv * 100:9.1f}", flush=True)


if __name__ == "__main__":
    run(*sys.argv[1:5])
