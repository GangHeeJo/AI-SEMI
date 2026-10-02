#!/usr/bin/env python3
# §164: 합성 정답으로 오차를 원인별로 분해. 이벤트마다 진짜 깊이(s_true)로 투영한 "오라클 맵"을 만들어 층 선택 오차와 분리한다.
#  O1  정확한 보정 + 진짜 깊이 + 진짜 theta                    -> 상한(남는 건 위치 잡음/정수 반올림/배경 잡음/표본 수)
#  O1b O1에서 이벤트 절반만(pipeline의 stride 2와 동일 조건)
#  O2  추정한 보정(방향 127.3도, 중심 (480,360)) + 최적 s     -> 보정 오차의 영향
#  O3  깊이 무시(s=0)                                         -> 깊이 보정이 필요한 정도(하한)
# 파이프라인 결과(층 선택)와 같은 지표(정답 장면과 밴드패스 NCC)로 비교.
import sys

import h5py
import numpy as np

sys.path.insert(0, "scripts")
from synth_evaluate import ncc_shift, prep, render_truth

W_PX, H_PX = 960, 720


def oracle_map(h5_path, theta_npy, e, c0, c0_true, e_true, C, stride=1, use_depth=True, rho=1.0):
    th = np.load(theta_npy); mids = np.arange(len(th)) * 4 + 2.0
    f = h5py.File(h5_path, "r"); n = f["events/t"].shape[0]; OFF = C / 2
    cnt = np.zeros(C * C, np.float32)
    for s0 in range(0, n, 4_000_000):
        sl = slice(s0, min(s0 + 4_000_000, n), stride)
        x = f["events/x"][sl].astype(np.float64); y = f["events/y"][sl].astype(np.float64)
        t = f["events/t"][sl].astype(np.float64) / 1e3; st = f["events/s_true"][sl].astype(np.float64)
        t = t + (x / 960.0 - 0.5) * rho * 0.773
        a = -np.interp(t, mids, th)
        st = np.where(st < 0, 0.0, st)
        if use_depth:
            v = (c0_true - c0)[None, :] + st[:, None] * e_true[None, :]            # 진짜 점이 추정 좌표계에서 가져야 할 오프셋 벡터
            s_e = v @ e                                                              # 추정 방향으로의 최적 투영 s
            off = s_e[:, None] * e[None, :]
        else:
            off = np.zeros((len(x), 2)) + (c0_true - c0)[None, :]                    # 깊이 무시: s=0 (중심 보정만)
        px = x - c0[0] - off[:, 0]; py = y - c0[1] - off[:, 1]
        c, s = np.cos(a), np.sin(a)
        xi = np.rint(c * px - s * py + OFF).astype(np.int64); yi = np.rint(s * px + c * py + OFF).astype(np.int64)
        ok = (xi >= 0) & (xi < C) & (yi >= 0) & (yi < C)
        cnt += np.bincount(yi[ok] * C + xi[ok], minlength=C * C).astype(np.float32)
    return cnt.reshape(C, C)


if __name__ == "__main__":
    sp = sys.argv[1]; h5 = sp + "/syn_rho1s.h5"
    truth = dict(np.load(sp + "/syn_truth.npz")); th_npy = sp + "/trkcal_theta.npy"
    e_true = np.array([np.cos(np.radians(float(truth["e_deg"]))), np.sin(np.radians(float(truth["e_deg"])))]); c0_true = truth["c0"]
    import json
    cal = json.load(open(sp + "/calib_syn_ori.json")); e_est = np.array(cal["unit_vector"]); c0_est = np.array(cal["center_px"])
    C = 1806; T = render_truth(truth, C); PT = prep(T, C)
    runs = [("O1  exact calibration, true depth, all events", e_true, c0_true, 1, True),
            ("O1b exact calibration, true depth, half events (=stride 2)", e_true, c0_true, 2, True),
            ("O2  ESTIMATED calibration, best s per event, half events", e_est, c0_est, 2, True),
            ("O3  no depth (s=0), half events", e_true, c0_true, 2, False)]
    print("oracle maps vs truth scene (band-pass NCC); pipeline (estimated calibration + layer selection, half events): self 0.475 / cross 0.448")
    for nm, e, c0, stride, ud in runs:
        M = oracle_map(h5, th_npy, e, c0, c0_true, e_true, C, stride, ud)
        print(f"  {nm:62s} NCC {ncc_shift(PT, prep(M, C))[0]:.3f}", flush=True)
