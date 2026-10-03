#!/usr/bin/env python3
# §165: 층 선택 개선 (합성 오라클 분해 결과를 반영).
#  - 층 범위를 min(0, s_min)부터 (기준점 s=0은 데이터로 정해지지 않는 모호성 -> 먼 구조가 음수 쪽에 놓일 수 있음)
#  - 층 사이 포물선 보간 -> 이벤트별 연속 깊이 (층 양자화 오차 제거; 점수는 이벤트별 선명도 조회값이라 평활 깊이 지도 방식과 다름)
#  - 확신도 기각: margin = (V1 - V2)/V1 (V2 = 최고 층에서 2층 이상 떨어진 층의 최고값). 위치를 큰 벡터로 옮겨 구조와 무관하게 만든
#    영(null) 분포의 95백분위보다 작으면 "랜덤 배치와 구분 안 됨"으로 기각 (영상 맞춤 값 없음)
#  - 시간 앞/뒤 절반 교차 검증 선택만 사용(자기 확증 방지)
import json
import sys

import h5py
import numpy as np

import delta_depthwarp2 as dw2
from delta_depthsnap import chunks_t
from delta_depthwarp2 import load_cal, sharp_of

W_PX, H_PX = 960, 720
NULL_SHIFT = (300, 170)          # 구조와 무관해지도록 월드 좌표를 옮기는 벡터(px)
NULL_PCT = 95.0


def run(h5_path, theta_npy, cal_json, out_prefix, win_ms=4, sigma_sharp=3.0, save_diag=False):
    dw2.SIGMA_SHARP = sigma_sharp
    e, c0, _, smax = load_cal(cal_json)
    cal = json.load(open(cal_json)); fwhm = float(cal["fwhm_median_px"]); step = fwhm / 6.0
    s_lo = min(0.0, float(cal["s_min_px"])) - step
    ss = np.arange(s_lo, smax + fwhm, step); K = len(ss)
    C = int(2 * (0.5 * np.hypot(W_PX, H_PX) + max(abs(ss[0]), abs(ss[-1])))) // 2 * 2; OFF = C / 2
    th = np.load(theta_npy); mids = (np.arange(len(th)) * win_ms + win_ms / 2) * 1e3
    f = h5py.File(h5_path, "r"); t_half = float(f["events/t"][-1]) / 2
    print(f"step {step:.1f}px, layers {K} (s {ss[0]:.0f}..{ss[-1]:.0f}), canvas {C}", flush=True)

    def canvas(x, y, a, s):
        px = x - c0[0] - s * e[0]; py = y - c0[1] - s * e[1]
        c, sn = np.cos(a), np.sin(a)
        xi = np.rint(c * px - sn * py + OFF).astype(np.int64); yi = np.rint(sn * px + c * py + OFF).astype(np.int64)
        ok = (xi >= 0) & (xi < C) & (yi >= 0) & (yi < C)
        return np.where(ok, yi * C + xi, -1)

    MA = np.zeros((K, C * C), np.float32); MB = np.zeros((K, C * C), np.float32)
    for x, y, a, t in chunks_t(f, th, mids):
        isB = t >= t_half
        for k, s in enumerate(ss):
            p = canvas(x, y, a, s)
            MA[k] += np.bincount(p[(p >= 0) & ~isB], minlength=C * C).astype(np.float32)
            MB[k] += np.bincount(p[(p >= 0) & isB], minlength=C * C).astype(np.float32)
    SA = np.stack([sharp_of(MA[k].reshape(C, C)).ravel() for k in range(K)])
    SB = np.stack([sharp_of(MB[k].reshape(C, C)).ravel() for k in range(K)])
    del MA, MB
    print("sharpness maps done", flush=True)

    def scores(P, isB, shift=None):
        valid = P >= 0; Pc = np.maximum(P, 0)
        if shift is not None:                                       # null: 월드 좌표를 옮겨 구조와 무관하게
            yi, xi = Pc // C, Pc % C
            Pc = ((yi + shift[1]) % C) * C + (xi + shift[0]) % C
        V = np.empty(P.shape, np.float32)
        for k in range(K):
            V[k] = np.where(isB, SA[k][Pc[k]], SB[k][Pc[k]])          # 교차 검증: 반대 절반의 선명도맵 사용
        return np.where(valid, V, -1.0)

    def margin_of(V, kb):
        V2 = V.copy(); ar = np.arange(K)[:, None]
        V2[np.abs(ar - kb[None, :]) <= 1] = -1.0                      # 최고 층 양옆(같은 봉우리)은 제외한 차선
        v1 = np.take_along_axis(V, kb[None], 0)[0]; v2 = V2.max(0)
        return (v1 - np.maximum(v2, 0)) / np.maximum(v1, 1e-30)

    # 영(null) 분포: 처음 몇 청크에서 표본 추출
    null_m = []
    for ci, (x, y, a, t) in enumerate(chunks_t(f, th, mids)):
        if ci >= 3: break
        isB = t >= t_half; P = np.stack([canvas(x, y, a, s) for s in ss])
        V = scores(P, isB, NULL_SHIFT); kb = V.argmax(0); ok = V.max(0) > 0
        null_m.append(margin_of(V, kb)[ok][:200000])
    thr = float(np.percentile(np.concatenate(null_m), NULL_PCT))
    print(f"null margin {NULL_PCT:.0f}th percentile = {thr:.3f}", flush=True)

    F_disc = np.zeros(C * C, np.float32); F_cont = np.zeros(C * C, np.float32); F_rej = np.zeros(C * C, np.float32)
    kept = total = 0; diag_s, diag_m, diag_v1, diag_v2 = [], [], [], []
    for x, y, a, t in chunks_t(f, th, mids):
        isB = t >= t_half; P = np.stack([canvas(x, y, a, s) for s in ss])
        V = scores(P, isB); kb = V.argmax(0); ok = (V.max(0) > 0)
        mg = margin_of(V, kb)
        km = np.clip(kb, 1, K - 2); vm = np.take_along_axis(V, (km - 1)[None], 0)[0]; v0 = np.take_along_axis(V, km[None], 0)[0]; vp = np.take_along_axis(V, (km + 1)[None], 0)[0]
        den = vm - 2 * v0 + vp
        with np.errstate(divide="ignore", invalid="ignore"):
            off = np.where(np.abs(den) > 1e-30, 0.5 * (vm - vp) / den, 0.0)
        off = np.clip(np.nan_to_num(off), -0.5, 0.5) * ((kb > 0) & (kb < K - 1))
        s_cont = ss[kb] + off * step
        pos_d = np.take_along_axis(P, kb[None], 0)[0]; pos_c = canvas(x, y, a, s_cont)
        F_disc += np.bincount(pos_d[ok & (pos_d >= 0)], minlength=C * C).astype(np.float32)
        okc = ok & (pos_c >= 0); F_cont += np.bincount(pos_c[okc], minlength=C * C).astype(np.float32)
        keep = okc & (mg >= thr); F_rej += np.bincount(pos_c[keep], minlength=C * C).astype(np.float32)
        kept += int(keep.sum()); total += len(x)
        if save_diag:
            diag_s.append(np.where(ok, s_cont, np.nan).astype(np.float32)); diag_m.append(mg.astype(np.float16))
            V2c = V.copy(); V2c[np.abs(np.arange(K)[:, None] - kb[None, :]) <= 1] = -1.0
            diag_v1.append(np.take_along_axis(V, kb[None], 0)[0].astype(np.float32)); diag_v2.append(np.maximum(V2c.max(0), 0).astype(np.float32))
    np.save(out_prefix + "_disc.npy", F_disc.reshape(C, C)); np.save(out_prefix + "_cont.npy", F_cont.reshape(C, C)); np.save(out_prefix + "_contrej.npy", F_rej.reshape(C, C))
    if save_diag:
        np.save(out_prefix + "_diag_s.npy", np.concatenate(diag_s)); np.save(out_prefix + "_diag_margin.npy", np.concatenate(diag_m)); np.save(out_prefix + "_diag_v1.npy", np.concatenate(diag_v1)); np.save(out_prefix + "_diag_v2.npy", np.concatenate(diag_v2)); np.save(out_prefix + "_ss.npy", ss)
    print(f"events kept by null-calibrated confidence: {kept}/{total} = {kept / total:.3f}")
    print("done", flush=True)


if __name__ == "__main__":
    # usage: delta_depthsnap3.py <events.h5> <theta.npy> <calibration.json> <out_prefix> [save_diag 0/1]
    run(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], save_diag=bool(int(sys.argv[5])) if len(sys.argv) > 5 else False)
