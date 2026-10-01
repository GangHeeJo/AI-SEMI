#!/usr/bin/env python3
# §157: §154(이벤트별 이산 층 선택, 육안으로 가장 실제에 가까움)를 보정 기반으로 재구성 + 자기확증 검증.
# 영상 맞춤 상수 없음: 방향/중심/범위/폭은 delta_calibrate.py JSON, 층 간격 = FWHM/6(봉우리 하나를 6점 이상으로
# 샘플링하는 일반 규칙), 범위 = s 98분위 + FWHM 1개(보정 불확실성 여유), 나머지 길이는 센서 폭 상대값.
#
# 이벤트별로 "가장 선명한 층"을 고르면 이미 선명한 선 위로 이벤트가 몰리는 자기확증(없던 선 생성)이 생길 수 있다.
# 교차 검증판: 시간 앞/뒤 절반으로 선명도맵을 따로 만들고, 앞 절반 이벤트는 뒤 절반 맵으로, 뒤 절반 이벤트는
# 앞 절반 맵으로 층을 고른다(자기 이벤트가 자기 선택에 기여하지 않음). 교차판에서도 선명하면 진짜 구조.
import json
import sys

import h5py
import numpy as np

from delta_depthwarp2 import chunks, load_cal, sharp_of

W_PX, H_PX = 960, 720


def run(h5_path, theta_npy, cal_json, out_prefix, win_ms=4, sigma_sharp=None):
    import delta_depthwarp2 as dw2
    if sigma_sharp is not None:
        dw2.SIGMA_SHARP = sigma_sharp                      # 선명도 평활 폭(px) 민감도 시험용
    e, c0, _, smax = load_cal(cal_json)
    cal = json.load(open(cal_json))
    fwhm = float(cal["fwhm_median_px"])
    step = fwhm / 6.0
    ss = np.arange(0.0, smax + fwhm, step)
    K = len(ss)
    C = int(2 * (0.5 * np.hypot(W_PX, H_PX) + ss[-1])) // 2 * 2
    OFF = C / 2
    th = np.load(theta_npy)
    mids = (np.arange(len(th)) * win_ms + win_ms / 2) * 1e3
    f = h5py.File(h5_path, "r")
    t_half = float(f["events/t"][-1]) / 2
    print(f"step {step:.1f}px, layers {K} (s up to {ss[-1]:.0f}), canvas {C}", flush=True)

    def canvas(x, y, a, s):
        px = x - c0[0] - s * e[0]; py = y - c0[1] - s * e[1]
        c, sn = np.cos(a), np.sin(a)
        xi = np.rint(c * px - sn * py + OFF).astype(np.int64); yi = np.rint(sn * px + c * py + OFF).astype(np.int64)
        ok = (xi >= 0) & (xi < C) & (yi >= 0) & (yi < C)
        return np.where(ok, yi * C + xi, -1)

    def times(slc):
        return f["events/t"][slc].astype(np.float64)

    # 1) 층별 선명도맵: 앞 절반(A), 뒤 절반(B)
    MA = np.zeros((K, C * C), np.float32); MB = np.zeros((K, C * C), np.float32)
    n = f["events/t"].shape[0]
    for x, y, a, t in chunks_t(f, th, mids):
        isB = t >= t_half
        for k, s in enumerate(ss):
            p = canvas(x, y, a, s)
            MA[k] += np.bincount(p[(p >= 0) & ~isB], minlength=C * C).astype(np.float32)
            MB[k] += np.bincount(p[(p >= 0) & isB], minlength=C * C).astype(np.float32)
    print("pass1 (layer maps) done", flush=True)
    SA = np.stack([sharp_of(MA[k].reshape(C, C)).ravel() for k in range(K)])
    SB = np.stack([sharp_of(MB[k].reshape(C, C)).ravel() for k in range(K)])
    SAll = np.stack([sharp_of((MA[k] + MB[k]).reshape(C, C)).ravel() for k in range(K)])
    del MA, MB
    print("sharpness maps done", flush=True)

    # 2) 이벤트별 층 선택: 자기(SAll) vs 교차(상대 절반 맵)
    F_self = np.zeros(C * C, np.float32); F_cross = np.zeros(C * C, np.float32)
    hist_self = np.zeros(K, np.int64); hist_cross = np.zeros(K, np.int64)
    for x, y, a, t in chunks_t(f, th, mids):
        isB = t >= t_half
        P = np.stack([canvas(x, y, a, s) for s in ss])            # K x N
        valid = P >= 0
        Pc = np.maximum(P, 0)
        for name, F, hist in (("self", F_self, hist_self), ("cross", F_cross, hist_cross)):
            V = np.empty(P.shape, np.float32)
            for k in range(K):
                if name == "self":
                    V[k] = SAll[k][Pc[k]]
                else:
                    V[k] = np.where(isB, SA[k][Pc[k]], SB[k][Pc[k]])     # 뒤 절반 이벤트는 앞 절반 맵으로, 앞 절반은 뒤 절반 맵으로
            V = np.where(valid, V, -1.0)
            kb = V.argmax(0)
            pos = np.take_along_axis(P, kb[None], 0)[0]
            ok = (pos >= 0) & (V.max(0) >= 0)
            F += np.bincount(pos[ok], minlength=C * C).astype(np.float32)
            hist += np.bincount(kb[ok], minlength=K)
    np.save(out_prefix + "_self.npy", F_self.reshape(C, C)); np.save(out_prefix + "_cross.npy", F_cross.reshape(C, C))
    print("events per layer (self) :", hist_self.tolist())
    print("events per layer (cross):", hist_cross.tolist())
    print("done", flush=True)


def chunks_t(f, th, mids):
    from delta_depthwarp2 import STRIDE
    CHUNK = 1_000_000                                     # 층 K개를 한 번에 올리므로 청크를 작게
    n = f["events/t"].shape[0]
    for s0 in range(0, n, CHUNK * STRIDE):
        sl = slice(s0, s0 + CHUNK * STRIDE, STRIDE)
        x = f["events/x"][sl].astype(np.float64); y = f["events/y"][sl].astype(np.float64)
        t = f["events/t"][sl].astype(np.float64)
        yield x, y, -np.interp(t, mids, th), t


if __name__ == "__main__":
    # usage: delta_depthsnap.py <events.h5> <theta.npy> <calibration.json> <out_prefix>
    run(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sigma_sharp=float(sys.argv[5]) if len(sys.argv) > 5 else None)
