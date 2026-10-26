#!/usr/bin/env python3
"""생체 모방 후보 1: 원심성 복사(efference copy) / 전정안반사(VOR) -- 로봇팔의 회전각 '지령'을 θ 사전분포로 쓴다.

베이즈 필터(bayes_filter_fixed_model.run_bayes_filter_fixed, RTL과 같은 eps_shift=8, alpha=2)의 확산 직후에
belief[θ] *= prior(|θ - θ_cmd|) 한 번만 추가한다(삼각형 LUT, 바닥 FLOOR로 지령이 틀려도 θ를 죽이지 않음).

*** 사전 등록 기준(결과를 보기 전에 정함, 값은 튜닝하지 않음) ***
  지령 모델: θ_cmd = GT θ + AR(1) 느린 잡음(σ). 정답 그대로를 지령으로 쓰지 않는다(순환 논증 방지).
  사전분포 고정값: D = 48 인덱스(약 ±17°), FLOOR = 32/256.  필터 고정값: eps_shift=8, alpha=2 (RTL과 동일).
  A1. σ=5°에서 평균 오차(꼬리 10% 평균, 위치 평균)가 기준선의 0.7배 이하 -- UZH와 RobotEvt 둘 다.
  A2. σ=5°에서 최악 오차(위치 최대)가 기준선 이하 -- 둘 다.
  A3. 지령이 완전히 틀린(무작위) 경우 평균 오차가 기준선의 1.3배 이하 -- 둘 다.
  셋 다 통과해야 RTL로 넘어간다. 하나라도 실패하면 기각.

사용: (프로젝트 루트에서) python scripts/efference_prior_test.py [--check]
"""
import os
import pickle
import random
import sys
import tempfile
import time

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from coord_transform_model import N_THETA
from rotation_estimate_model import build_transform_table, circular_diff
import bayes_filter_fixed_model as bf

DEG = 360.0 / N_THETA
EPS_SHIFT, ALPHA = 8, 2
D_IDX, FLOOR = 48, 32
CACHE = os.environ.get("EP_CACHE", os.path.join(tempfile.gettempdir(), "ep_cache"))
ROBOT = ("common_traces_robotevt/robotevt_pureRot_slow_off.events.txt", "common_traces_robotevt/robotevt_pureRot_slow_off.groundtruth.txt")
UZH_POS = bf.POSITIONS_20[:8]
ROBOT_POS = [(146, 84), (158, 131), (164, 126), (120, 90), (180, 100)]


def get_events(name, pos, src):
    os.makedirs(CACHE, exist_ok=True)
    f = os.path.join(CACHE, f"{name}_{pos[0]}_{pos[1]}.pkl")
    if os.path.exists(f):
        return pickle.load(open(f, "rb"))
    with tempfile.TemporaryDirectory() as tmp:
        ev = bf.build_patch_events(pos[0], pos[1], 4, tmp, events_txt=src[0], groundtruth_txt=src[1]) if src else bf.build_patch_events(pos[0], pos[1], 4, tmp)
    pickle.dump(ev, open(f, "wb"))
    return ev


def make_tables():
    table = build_transform_table(4)
    X = np.zeros((16, N_THETA), np.int64); Y = np.zeros((16, N_THETA), np.int64)
    for (r, c, t), (x, y) in table.items():
        X[r * 4 + c, t] = x; Y[r * 4 + c, t] = y
    lut = bf.make_like_lut(ALPHA)
    L = np.zeros((bf.CNT_MAX + 1, bf.CNT_MAX + 1, 2), np.int64)
    for (a, b, p), v in lut.items():
        L[a, b, p] = v
    d = np.minimum(np.arange(N_THETA), N_THETA - np.arange(N_THETA))   # 원순환 거리 LUT(0..N/2)
    W = np.maximum(FLOOR, 256 - (256 * d) // D_IDX)
    return X, Y, L, W


def run_np(events, X, Y, L, W, cmd=None):
    """run_bayes_filter_fixed와 같은 정수 연산(numpy). cmd가 None이면 기준선(비트 단위로 같아야 함)."""
    n = N_THETA; idx = np.arange(n)
    world_on = np.zeros((n, n), np.int8); world_off = np.zeros((n, n), np.int8)
    belief = np.zeros(n, np.int64); belief[0] = bf.BELIEF_INIT
    errs = []; thetas = []
    for i, (row, col, pol, gt) in enumerate(events):
        k = row * 4 + col
        s = belief >> EPS_SHIFT
        belief = belief - 2 * s + np.roll(s, 1) + np.roll(s, -1)
        if cmd is not None:
            dd = np.abs(idx - cmd[i]) % n
            belief = (belief * W[np.minimum(dd, n - dd)]) >> 8
        xs, ys = X[k], Y[k]
        like = L[world_on[xs, ys], world_off[xs, ys], pol]
        belief = (belief * like) >> bf.LIKE_BITS
        max_b = int(belief.max())
        if max_b == 0:
            belief[:] = bf.BELIEF_INIT >> 8; max_b = int(belief[0])
        if max_b < bf.RENORM_LOW:
            sh = 0
            while (max_b << (sh + 1)) < bf.BELIEF_INIT:
                sh += 1
            if sh:
                belief = belief << sh
        t = int(belief.argmax())
        xx, yy = int(xs[t]), int(ys[t])
        w = world_on if pol else world_off
        w[xx, yy] = min(int(w[xx, yy]) + 1, bf.CNT_MAX)
        errs.append(circular_diff(t, gt)); thetas.append(t)
    return errs, thetas


def make_cmd(events, sigma_deg, bias_deg=0.0, rho=0.999, seed=1, wrong=False):
    rng = np.random.default_rng(seed); n = len(events); out = np.zeros(n, np.int64)
    if wrong:
        return rng.integers(0, N_THETA, n)
    s = sigma_deg / DEG; a = 0.0
    for i, ev in enumerate(events):
        a = rho * a + np.sqrt(1 - rho * rho) * s * rng.standard_normal()
        out[i] = int(round(ev[3] + a + bias_deg / DEG)) % N_THETA
    return out


def tail_mean(e, frac=0.1):
    k = max(1, int(len(e) * frac)); return float(np.mean(e[-k:]))


def evaluate(name, positions, src, X, Y, L, W, scen):
    rows = {s: [] for s in scen}
    for pos in positions:
        ev = get_events(name, pos, src)
        for s, kw in scen.items():
            cmd = None if kw is None else make_cmd(ev, **kw)
            e, _ = run_np(ev, X, Y, L, W, cmd)
            rows[s].append((tail_mean(e) * DEG, max(e) * DEG))
        print(f"  {name}{pos} n={len(ev)} " + "  ".join(f"{s}:{rows[s][-1][0]:.1f}/{rows[s][-1][1]:.1f}" for s in scen), flush=True)
    return {s: (float(np.mean([m for m, _ in v])), float(max(w for _, w in v))) for s, v in rows.items()}


if __name__ == "__main__":
    X, Y, L, W = make_tables()
    if "--check" in sys.argv:           # numpy판이 원본 정수 오라클과 비트 단위로 같은지
        ev = get_events("uzh", UZH_POS[0], None)[:1500]
        table = build_transform_table(4)
        ref = bf.run_bayes_filter_fixed(ev, table, EPS_SHIFT, ALPHA)
        got, _ = run_np(ev, X, Y, L, W, None)
        print("numpy == oracle:", ref == got, "events", len(ev)); sys.exit(0 if ref == got else 1)
    scen = {"base": None, "s2": dict(sigma_deg=2), "s5": dict(sigma_deg=5), "s10": dict(sigma_deg=10),
            "s5b5": dict(sigma_deg=5, bias_deg=5), "wrong": dict(sigma_deg=0, wrong=True)}
    t0 = time.time(); res = {}
    res["UZH"] = evaluate("uzh", UZH_POS, None, X, Y, L, W, scen)
    res["RobotEvt"] = evaluate("robot", ROBOT_POS, ROBOT, X, Y, L, W, scen)
    print(f"\n(시간 {time.time() - t0:.0f}s)  평균(꼬리10%)° / 최악°")
    for ds, r in res.items():
        print(ds, "  ".join(f"{s}: {m:.1f}/{w:.1f}" for s, (m, w) in r.items()))
    ok = True
    for ds, r in res.items():
        b = r["base"]
        a1 = r["s5"][0] <= 0.7 * b[0]; a2 = r["s5"][1] <= b[1]; a3 = r["wrong"][0] <= 1.3 * b[0]
        print(f"{ds}: A1 평균 {r['s5'][0]:.1f} <= 0.7*{b[0]:.1f} -> {a1} | A2 최악 {r['s5'][1]:.1f} <= {b[1]:.1f} -> {a2} | A3 틀린 지령 {r['wrong'][0]:.1f} <= 1.3*{b[0]:.1f} -> {a3}")
        ok &= a1 and a2 and a3
    print("결과:", "통과(RTL 후보)" if ok else "기각")
