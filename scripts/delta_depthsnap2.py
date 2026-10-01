#!/usr/bin/env python3
# §158: 교차 검증 층 선택 + 깊이 일관성 조건.
# §157 결과: 자기선택판의 막대 연속성(세로선 길이)은 자기확증으로 부풀려져 있고, 교차검증판은 실제(280px)의
# 절반(144px)으로 끊김. 개선: 상대 시간대 선명도맵에서 픽셀별 깊이 지도 D(층 번호)를 만들어 중앙값 필터로 평활하고,
# 이벤트가 층 k의 위치에 떨어졌을 때 D(그 위치)가 k와 일치(+-1)하는 층만 후보로 인정, 후보 중 선명도 최대를 선택.
# 후보가 없는 이벤트는 버림(잡음 억제). 상대 시간대 정보만 사용하므로 자기확증 없음. 영상 값은 코드에 없음
# (평활 창 = 센서 폭의 1% 상대값, 일치 허용 +-1층).
import json
import sys

import h5py
import numpy as np
from scipy import ndimage as ndi

import delta_depthwarp2 as dw2
from delta_depthsnap import chunks_t
from delta_depthwarp2 import load_cal, sharp_of

W_PX, H_PX = 960, 720
MED_WIN = int(round(0.010 * W_PX))      # 중앙값 필터 창(px)
AGREE = 1                               # 층 번호 일치 허용


def run(h5_path, theta_npy, cal_json, out_prefix, win_ms=4, sigma_sharp=3.0):
    dw2.SIGMA_SHARP = sigma_sharp
    e, c0, _, smax = load_cal(cal_json)
    fwhm = float(json.load(open(cal_json))["fwhm_median_px"])
    step = fwhm / 6.0
    ss = np.arange(0.0, smax + fwhm, step); K = len(ss)
    C = int(2 * (0.5 * np.hypot(W_PX, H_PX) + ss[-1])) // 2 * 2; OFF = C / 2
    th = np.load(theta_npy); mids = (np.arange(len(th)) * win_ms + win_ms / 2) * 1e3
    f = h5py.File(h5_path, "r"); t_half = float(f["events/t"][-1]) / 2
    print(f"step {step:.1f}px layers {K} canvas {C} median window {MED_WIN}px", flush=True)

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

    def depth_index(S):
        cover = S.min(0) > 0                                   # 모든 층에 데이터가 있는 픽셀만(가장자리 인공물 제외)
        d = S.argmax(0).astype(np.int16)
        d = ndi.median_filter(d.reshape(C, C), size=MED_WIN).ravel()
        d[~cover] = -1
        return d
    D_fromB = depth_index(SB)      # 앞 절반(A) 이벤트용(상대=B)
    D_fromA = depth_index(SA)      # 뒤 절반(B) 이벤트용(상대=A)
    np.save(out_prefix + "_depthidx_A.npy", D_fromA.reshape(C, C)); np.save(out_prefix + "_depthidx_B.npy", D_fromB.reshape(C, C))
    print("depth index maps done", flush=True)

    NQ = 4                                                     # 잔상 진단용: 시간 4등분 맵도 같이 저장
    t_end = float(f["events/t"][-1])
    F_cons = np.zeros(C * C, np.float32); F_cross = np.zeros(C * C, np.float32)
    Fq = np.zeros((NQ, C * C), np.float32)
    total = kept = 0
    for x, y, a, t in chunks_t(f, th, mids):
        isB = t >= t_half
        P = np.stack([canvas(x, y, a, s) for s in ss]); valid = P >= 0; Pc = np.maximum(P, 0)
        V = np.empty(P.shape, np.float32); Dk = np.empty(P.shape, np.int16)
        for k in range(K):
            V[k] = np.where(isB, SA[k][Pc[k]], SB[k][Pc[k]])
            Dk[k] = np.where(isB, D_fromA[Pc[k]], D_fromB[Pc[k]])
        V = np.where(valid, V, -1.0)
        kb0 = V.argmax(0); pos0 = np.take_along_axis(P, kb0[None], 0)[0]; ok0 = (pos0 >= 0) & (V.max(0) >= 0)
        F_cross += np.bincount(pos0[ok0], minlength=C * C).astype(np.float32)
        ks = np.arange(K)[:, None]
        cons = valid & (Dk >= 0) & (np.abs(Dk - ks) <= AGREE)
        Vc = np.where(cons, V, -1.0)
        kb = Vc.argmax(0); pos = np.take_along_axis(P, kb[None], 0)[0]; ok = Vc.max(0) >= 0
        F_cons += np.bincount(pos[ok], minlength=C * C).astype(np.float32)
        qi = np.minimum((t / (t_end + 1) * NQ).astype(np.int64), NQ - 1)
        for q in range(NQ):
            Fq[q] += np.bincount(pos[ok & (qi == q)], minlength=C * C).astype(np.float32)
        total += len(x); kept += int(ok.sum())
    np.save(out_prefix + "_cons_quarters.npy", Fq.reshape(NQ, C, C))
    np.save(out_prefix + "_cons.npy", F_cons.reshape(C, C)); np.save(out_prefix + "_cross.npy", F_cross.reshape(C, C))
    print(f"events kept by depth-consistency: {kept}/{total} = {kept / total:.3f}")
    print("done", flush=True)


if __name__ == "__main__":
    # usage: delta_depthsnap2.py <events.h5> <theta.npy> <calibration.json> <out_prefix>
    run(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])
