#!/usr/bin/env python3
# §166: 독립 증거 일치로 층 선택을 걸러낸다(임계값 불필요). 시간을 3등분해 세 구간의 층별 선명도맵 S0,S1,S2를 만들고, 구간 i의
# 이벤트는 나머지 두 구간의 맵으로 각각 독립적으로 층을 고른다(kb_a, kb_b). 두 선택이 인접 층 이내(|kb_a-kb_b|<=1)로 일치할 때만
# 신뢰한다(두 독립 복제의 합의). 깊이는 두 맵의 합 V=Va+Vb로 포물선 보간한 연속값. §165 결과를 바탕으로: 층 범위 min(0,s_min)부터,
# 연속 깊이. (margin 기반 null 임계값은 포화되어 실패 -> 폐기)
import json
import sys

import h5py
import numpy as np

import delta_depthwarp2 as dw2
from delta_depthsnap import chunks_t
from delta_depthwarp2 import load_cal, sharp_of

W_PX, H_PX = 960, 720


def run(h5_path, theta_npy, cal_json, out_prefix, win_ms=4, sigma_sharp=3.0, save_diag=False):
    dw2.SIGMA_SHARP = sigma_sharp
    e, c0, _, smax = load_cal(cal_json)
    cal = json.load(open(cal_json)); fwhm = float(cal["fwhm_median_px"]); step = fwhm / 6.0
    ss = np.arange(min(0.0, float(cal["s_min_px"])) - step, smax + fwhm, step); K = len(ss)
    C = int(2 * (0.5 * np.hypot(W_PX, H_PX) + max(abs(ss[0]), abs(ss[-1])))) // 2 * 2; OFF = C / 2
    th = np.load(theta_npy); mids = (np.arange(len(th)) * win_ms + win_ms / 2) * 1e3
    f = h5py.File(h5_path, "r"); t_end = float(f["events/t"][-1])
    print(f"step {step:.1f}px, layers {K} (s {ss[0]:.0f}..{ss[-1]:.0f}), canvas {C}", flush=True)

    def canvas(x, y, a, s):
        px = x - c0[0] - s * e[0]; py = y - c0[1] - s * e[1]
        c, sn = np.cos(a), np.sin(a)
        xi = np.rint(c * px - sn * py + OFF).astype(np.int64); yi = np.rint(sn * px + c * py + OFF).astype(np.int64)
        ok = (xi >= 0) & (xi < C) & (yi >= 0) & (yi < C)
        return np.where(ok, yi * C + xi, -1)

    thirds = lambda t: np.minimum((t / (t_end + 1) * 3).astype(np.int64), 2)
    M = np.zeros((3, K, C * C), np.float32)
    for x, y, a, t in chunks_t(f, th, mids):
        it = thirds(t)
        for k, s in enumerate(ss):
            p = canvas(x, y, a, s)
            for j in range(3):
                M[j, k] += np.bincount(p[(p >= 0) & (it == j)], minlength=C * C).astype(np.float32)
    S = np.zeros_like(M)
    for j in range(3):
        for k in range(K):
            S[j, k] = sharp_of(M[j, k].reshape(C, C)).ravel()
    del M
    print("sharpness maps done", flush=True)

    F_all = np.zeros(C * C, np.float32); F_agree = np.zeros(C * C, np.float32); F_gap = np.zeros((3, C * C), np.float32)   # 불일치 |ka-kb| = 2 / 3~4 / 5이상 별 맵(가중 결합용)
    kept = total = 0; dg_s, dg_a = [], []
    for x, y, a, t in chunks_t(f, th, mids):
        it = thirds(t); P = np.stack([canvas(x, y, a, s) for s in ss]); valid = P >= 0; Pc = np.maximum(P, 0)
        Va = np.empty(P.shape, np.float32); Vb = np.empty(P.shape, np.float32)
        for k in range(K):
            G = np.stack([S[0, k][Pc[k]], S[1, k][Pc[k]], S[2, k][Pc[k]]])               # 3 x N
            Va[k] = np.take_along_axis(G, ((it + 1) % 3)[None], 0)[0]; Vb[k] = np.take_along_axis(G, ((it + 2) % 3)[None], 0)[0]
        Va = np.where(valid, Va, -1.0); Vb = np.where(valid, Vb, -1.0); V = Va + Vb
        ka = Va.argmax(0); kb_ = Vb.argmax(0); kc = V.argmax(0); ok = V.max(0) > 0
        km = np.clip(kc, 1, K - 2); vm = np.take_along_axis(V, (km - 1)[None], 0)[0]; v0 = np.take_along_axis(V, km[None], 0)[0]; vp = np.take_along_axis(V, (km + 1)[None], 0)[0]
        den = vm - 2 * v0 + vp
        with np.errstate(divide="ignore", invalid="ignore"):
            off = np.where(np.abs(den) > 1e-30, 0.5 * (vm - vp) / den, 0.0)
        off = np.clip(np.nan_to_num(off), -0.5, 0.5) * ((kc > 0) & (kc < K - 1))
        s_cont = ss[kc] + off * step; pos = canvas(x, y, a, s_cont); okp = ok & (pos >= 0)
        agree = okp & (np.abs(ka - kb_) <= 1)
        F_all += np.bincount(pos[okp], minlength=C * C).astype(np.float32); F_agree += np.bincount(pos[agree], minlength=C * C).astype(np.float32)
        gap = np.abs(ka - kb_)
        for gi, sel in enumerate((gap == 2, (gap >= 3) & (gap <= 4), gap >= 5)):
            F_gap[gi] += np.bincount(pos[okp & sel], minlength=C * C).astype(np.float32)
        kept += int(agree.sum()); total += len(x)
        if save_diag:
            dg_s.append(np.where(okp, s_cont, np.nan).astype(np.float32)); dg_a.append(agree)
    np.save(out_prefix + "_gap.npy", F_gap.reshape(3, C, C)); np.save(out_prefix + "_all.npy", F_all.reshape(C, C)); np.save(out_prefix + "_agree.npy", F_agree.reshape(C, C))
    if save_diag:
        np.save(out_prefix + "_diag_s.npy", np.concatenate(dg_s)); np.save(out_prefix + "_diag_agree.npy", np.concatenate(dg_a)); np.save(out_prefix + "_ss.npy", ss)
    print(f"events kept by two-replicate agreement: {kept}/{total} = {kept / total:.3f}")
    print("done", flush=True)


if __name__ == "__main__":
    # usage: delta_depthsnap4.py <events.h5> <theta.npy> <calibration.json> <out_prefix> [save_diag 0/1]
    run(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], save_diag=bool(int(sys.argv[5])) if len(sys.argv) > 5 else False)
