#!/usr/bin/env python3
# §196: 복잡한 장면에서 깊이 층 선택이 무너지는 이유와 대응(합성 정답으로 시험).
# 시간을 G개 연속 구간으로 나눠 구간별 층 지도/선명도 지도를 만들고, 구간 g의 이벤트는 나머지 구간의 선명도로 층을 평가한다(자기 이벤트 불참).
#   A   G=3 두 복제본 일치(+-1층)                           (기존 delta_depthsnap4와 같은 판정)
#   P   G=3 두 복제본 + 지역 증거 합산(같은 프레임 창, 센서 POOL px 셀의 이벤트들의 층 점수를 합친 뒤 argmax)
#   B3  G=6 나머지 5개 증거 중 합산 argmax의 +-1층 이내에 3개 이상          B4  4개 이상
# 지표(정답 장면 대비): NCC, 잔상 질량, 복원율, 남는 이벤트 비율, 일치 이벤트의 층 정확도(|s - 기대 s| <= 층 간격), 전체 이벤트 층 정확도.
# 사용: depth_vote_experiment.py <G> <events.h5> <theta.npy> <calib.json> <truth.npz> [pool_px=8]   (DELTA_RHO, SNAP_STRIDE 환경변수)
import json
import os
import sys

import h5py
import numpy as np

import delta_depthwarp2 as dw2
dw2.STRIDE = int(os.environ.get("SNAP_STRIDE", "8"))
from delta_depthsnap import chunks_t  # noqa: E402
from delta_depthwarp2 import load_cal, sharp_of  # noqa: E402
from ghost_metric import ghost  # noqa: E402

W_PX, H_PX = 960, 720


def run(G, h5p, th_npy, cal_json, truth_npz, pool=8):
    dw2.SIGMA_SHARP = 3.0
    e, c0, _, smax = load_cal(cal_json); cal = json.load(open(cal_json)); fwhm = float(cal["fwhm_median_px"]); step = fwhm / 6.0
    ss = np.arange(min(0.0, float(cal["s_min_px"])) - step, smax + fwhm, step); K = len(ss)
    C = int(2 * (0.5 * np.hypot(W_PX, H_PX) + max(abs(ss[0]), abs(ss[-1])))) // 2 * 2; OFF = C / 2
    th = np.load(th_npy); mids = (np.arange(len(th)) * 4 + 2) * 1e3; f = h5py.File(h5p, "r"); t_end = float(f["events/t"][-1]); T = dict(np.load(truth_npz))
    e_t = np.array([np.cos(np.radians(float(T["e_deg"]))), np.sin(np.radians(float(T["e_deg"])))]); c0_t = T["c0"]; s_all = f["events/s_true"][::dw2.STRIDE].astype(np.float64)
    group = lambda t: np.minimum((t / (t_end + 1) * G).astype(np.int64), G - 1)
    print(f"G={G} layers {K} step {step:.1f}px canvas {C} events/stride {dw2.STRIDE}", flush=True)
    def canvas(x, y, a, s):
        px = x - c0[0] - s * e[0]; py = y - c0[1] - s * e[1]; c, sn = np.cos(a), np.sin(a)
        xi = np.rint(c * px - sn * py + OFF).astype(np.int64); yi = np.rint(sn * px + c * py + OFF).astype(np.int64); ok = (xi >= 0) & (xi < C) & (yi >= 0) & (yi < C)
        return np.where(ok, yi * C + xi, -1)
    M = np.zeros((G, K, C * C), np.float32)
    for x, y, a, t in chunks_t(f, th, mids):
        ig = group(t)
        for k, s in enumerate(ss):
            p = canvas(x, y, a, s)
            for j in range(G): M[j, k] += np.bincount(p[(p >= 0) & (ig == j)], minlength=C * C)
    S = np.zeros_like(M)
    for j in range(G):
        for k in range(K): S[j, k] = sharp_of(M[j, k].reshape(C, C)).ravel()
    del M; print("sharpness done", flush=True)
    methods = ["A", "P"] if G == 3 else ["B3", "B4"]; maps = {m: np.zeros(C * C, np.float32) for m in methods}; mall = {m: np.zeros(C * C, np.float32) for m in methods}
    kept = {m: 0 for m in methods}; correct = {m: 0 for m in methods}; correct_all = {m: 0 for m in methods}; denom = {m: 0 for m in methods}; denom_all = {m: 0 for m in methods}; total = 0; n_off = 0
    for x, y, a, t in chunks_t(f, th, mids):
        n = len(x); st = s_all[n_off:n_off + n]; n_off += n; total += n
        ig = group(t); P = np.stack([canvas(x, y, a, s) for s in ss]); valid = P >= 0; Pc = np.maximum(P, 0); Vg = np.empty((G, K, n), np.float32)
        for j in range(G):
            for k in range(K): Vg[j, k] = S[j, k][Pc[k]]
        Vg = np.where(valid[None], Vg, -1.0); idx = np.arange(n)
        Vo = np.stack([np.take_along_axis(Vg.transpose(2, 0, 1), ((ig + d) % G)[:, None, None], 1)[:, 0, :].T for d in range(1, G)])   # (G-1, K, n) 이벤트가 속하지 않은 구간들의 증거
        s_exp_ok = (st >= 0)
        def finish(name, kc, agree, V):
            km = np.clip(kc, 1, K - 2); vm = np.take_along_axis(V, (km - 1)[None], 0)[0]; v0 = np.take_along_axis(V, km[None], 0)[0]; vp = np.take_along_axis(V, (km + 1)[None], 0)[0]; den = vm - 2 * v0 + vp
            with np.errstate(divide="ignore", invalid="ignore"): off = np.where(np.abs(den) > 1e-30, 0.5 * (vm - vp) / den, 0.0)
            off = np.clip(np.nan_to_num(off), -0.5, 0.5) * ((kc > 0) & (kc < K - 1)); sc = ss[kc] + off * step; pos = canvas(x, y, a, sc); okp = (pos >= 0) & (V.max(0) > 0)
            s_exp = ((c0_t - c0)[None, :] + np.maximum(st, 0)[:, None] * e_t[None, :]) @ e; hit = np.abs(sc - s_exp) <= step
            ag = agree & okp; maps[name] += np.bincount(pos[ag], minlength=C * C); mall[name] += np.bincount(pos[okp], minlength=C * C)
            kept[name] += int(ag.sum()); denom[name] += int((ag & s_exp_ok).sum()); correct[name] += int((hit & ag & s_exp_ok).sum()); correct_all[name] += int((hit & okp & s_exp_ok).sum()); denom_all[name] += int((okp & s_exp_ok).sum())
        if G == 3:
            Va, Vb = Vo[0], Vo[1]
            kc = (Va + Vb).argmax(0); finish("A", kc, np.abs(Va.argmax(0) - Vb.argmax(0)) <= 1, Va + Vb)
            cell = ((t // (4 * 773)).astype(np.int64) * 241 + (y // pool).astype(np.int64)) * 241 + (x // pool).astype(np.int64); _, inv, cnt = np.unique(cell, return_inverse=True, return_counts=True)
            pool_ = lambda V: np.stack([np.bincount(inv, weights=np.maximum(V[k], 0), minlength=len(cnt))[inv] for k in range(K)])
            Pa, Pb = pool_(Va), pool_(Vb); kc2 = (Pa + Pb).argmax(0); finish("P", kc2, np.abs(Pa.argmax(0) - Pb.argmax(0)) <= 1, Pa + Pb)
        else:
            Vs = Vo.sum(0); kc = Vs.argmax(0); votes = sum((np.abs(Vo[i].argmax(0) - kc) <= 1).astype(int) for i in range(G - 1))
            finish("B3", kc, votes >= 3, Vs); finish("B4", kc, votes >= 4, Vs)
    print(f"{'method':8s}{'kept %':>8s}{'agreed-layer acc %':>20s}{'all-event acc %':>17s}{'NCC (kept)':>12s}{'NCC (all)':>11s}{'ghost % (kept)':>16s}{'cover %':>9s}")
    for m in methods:
        pr, cv, nn, _ = ghost(maps[m].reshape(C, C), T); pa = ghost(mall[m].reshape(C, C), T)
        print(f"{m:8s}{kept[m] / total * 100:8.1f}{correct[m] / max(denom[m], 1) * 100:20.1f}{correct_all[m] / max(denom_all[m], 1) * 100:17.1f}{nn:12.3f}{pa[2]:11.3f}{(1 - pr) * 100:16.1f}{cv * 100:9.1f}", flush=True)


if __name__ == "__main__":
    run(int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], int(sys.argv[6]) if len(sys.argv) > 6 else 8)
