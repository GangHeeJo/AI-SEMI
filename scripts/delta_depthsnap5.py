#!/usr/bin/env python3
# §167: 일치 필터(snap4)의 약점 보완 -- 모호한(aperture) 이벤트를 버리지 말고, 확실한 이벤트에서 깊이를 전파한다.
#  A) 시간 3등분 독립 두 증거 일치 이벤트(G)를 snap4와 같이 선택.
#  B) G의 (월드 위치, 연속 깊이)로 깊이 지도 D(u)와 지원 마스크를 만든다(정규화 가우시안, sigma=2px).
#  C) G가 아닌 이벤트는 후보 층 k의 투영 위치에서 D가 지원되고 |s_k - D| <= 1.5 층일 때만 인정, 그중 점수합(Va+Vb) 최대 층을 선택.
#     지원이 없으면 기각. 같은 막대의 확실한 이벤트가 알려준 깊이가 같은 막대의 모호한 이벤트를 되살린다.
import json
import sys

import h5py
import numpy as np
from scipy import ndimage as ndi

import delta_depthwarp2 as dw2
from delta_depthsnap import chunks_t
from delta_depthwarp2 import load_cal, sharp_of

W_PX, H_PX = 960, 720
TOL_STEPS = 1.5


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

    def evidence(x, y, a, t):
        it = thirds(t); P = np.stack([canvas(x, y, a, s) for s in ss]); valid = P >= 0; Pc = np.maximum(P, 0)
        Va = np.empty(P.shape, np.float32); Vb = np.empty(P.shape, np.float32)
        for k in range(K):
            G = np.stack([S[0, k][Pc[k]], S[1, k][Pc[k]], S[2, k][Pc[k]]])
            Va[k] = np.take_along_axis(G, ((it + 1) % 3)[None], 0)[0]; Vb[k] = np.take_along_axis(G, ((it + 2) % 3)[None], 0)[0]
        return P, Pc, np.where(valid, Va, -1.0), np.where(valid, Vb, -1.0)

    def subpixel(V, kc):
        km = np.clip(kc, 1, K - 2); vm = np.take_along_axis(V, (km - 1)[None], 0)[0]; v0 = np.take_along_axis(V, km[None], 0)[0]; vp = np.take_along_axis(V, (km + 1)[None], 0)[0]
        den = vm - 2 * v0 + vp
        with np.errstate(divide="ignore", invalid="ignore"):
            off = np.where(np.abs(den) > 1e-30, 0.5 * (vm - vp) / den, 0.0)
        return ss[kc] + np.clip(np.nan_to_num(off), -0.5, 0.5) * ((kc > 0) & (kc < K - 1)) * step

    # B) 일치 이벤트 -> 깊이 지도
    D_sum = np.zeros(C * C, np.float32); D_cnt = np.zeros(C * C, np.float32); F_agree = np.zeros(C * C, np.float32)
    n_ag = n_tot = 0
    for x, y, a, t in chunks_t(f, th, mids):
        P, Pc, Va, Vb = evidence(x, y, a, t); V = Va + Vb
        ka = Va.argmax(0); kb_ = Vb.argmax(0); kc = V.argmax(0); ok = V.max(0) > 0
        s_cont = subpixel(V, kc); pos = canvas(x, y, a, s_cont); ag = ok & (pos >= 0) & (np.abs(ka - kb_) <= 1)
        D_sum += np.bincount(pos[ag], weights=s_cont[ag], minlength=C * C).astype(np.float32); D_cnt += np.bincount(pos[ag], minlength=C * C).astype(np.float32)
        F_agree += np.bincount(pos[ag], minlength=C * C).astype(np.float32); n_ag += int(ag.sum()); n_tot += len(x)
    Dn_num = ndi.gaussian_filter(D_sum.reshape(C, C), 2.0); Dn_den = ndi.gaussian_filter(D_cnt.reshape(C, C), 2.0)
    support = (Dn_den > 0.5).ravel(); Dn = (Dn_num / np.maximum(Dn_den, 1e-6)).ravel().astype(np.float32)
    print(f"agreed {n_ag}/{n_tot} = {n_ag / n_tot:.3f}; depth-map support pixels {int(support.sum())}", flush=True)

    # C) 전파
    F_prop = F_agree.copy(); n_prop = 0; dg_s, dg_flag = [], []
    for x, y, a, t in chunks_t(f, th, mids):
        P, Pc, Va, Vb = evidence(x, y, a, t); V = Va + Vb
        ka = Va.argmax(0); kb_ = Vb.argmax(0); kc = V.argmax(0); ok = V.max(0) > 0
        s_cont = subpixel(V, kc); pos = canvas(x, y, a, s_cont); ag = ok & (pos >= 0) & (np.abs(ka - kb_) <= 1)
        Dk = Dn[Pc]; sup = support[Pc]                                              # K x N
        cons = sup & (P >= 0) & (np.abs(ss[:, None] - Dk) <= TOL_STEPS * step)
        Vc = np.where(cons, V, -1.0); kp = Vc.argmax(0); okp = (Vc.max(0) > 0) & ~ag
        s_p = subpixel(np.where(cons, V, 0.0), kp); pos_p = canvas(x, y, a, s_p); okp &= pos_p >= 0
        F_prop += np.bincount(pos_p[okp], minlength=C * C).astype(np.float32); n_prop += int(okp.sum())
        if save_diag:
            dg_s.append(np.where(ag, s_cont, np.where(okp, s_p, np.nan)).astype(np.float32)); dg_flag.append(np.where(ag, 1, np.where(okp, 2, 0)).astype(np.int8))
    np.save(out_prefix + "_agree.npy", F_agree.reshape(C, C)); np.save(out_prefix + "_prop.npy", F_prop.reshape(C, C))
    if save_diag:
        np.save(out_prefix + "_diag_s.npy", np.concatenate(dg_s)); np.save(out_prefix + "_diag_flag.npy", np.concatenate(dg_flag)); np.save(out_prefix + "_ss.npy", ss)
    print(f"propagated {n_prop} more events -> total kept {(n_ag + n_prop) / n_tot:.3f}")
    print("done", flush=True)


if __name__ == "__main__":
    # usage: delta_depthsnap5.py <events.h5> <theta.npy> <calibration.json> <out_prefix> [save_diag 0/1]
    run(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], save_diag=bool(int(sys.argv[5])) if len(sys.argv) > 5 else False)
