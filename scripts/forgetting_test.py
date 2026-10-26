#!/usr/bin/env python3
"""생체 모방 후보 3: 기억의 소멸(forgetting) -- 추정기의 월드 메모리 카운터를 K개 이벤트마다 절반으로 감쇠.

베이즈 필터(eps_shift=8, alpha=2, RTL과 같은 고정소수점)의 월드 메모리(on/off 카운터)는 오래된 관측이 영원히 남는다.
자세 오차로 틀린 칸에 쌓인 흔적(잔상)이 이후 우도 계산을 오염시킬 수 있으므로, K 이벤트마다 모든 카운터를 >>1 한다.

*** 사전 등록 기준(실행 전에 정함) ***
  K 후보: {256, 1024, 4096} (이 셋만 시험, 추가 탐색 없음). 기준선 = 감쇠 없음.
  C1. K는 UZH 8곳 결과만으로 고른다(평균 오차 최소인 K).
  C2. 고른 K가 UZH와 RobotEvt 둘 다에서 평균 오차(꼬리 10% 평균)를 기준선의 0.8배 이하로 줄인다.
  C3. 고른 K에서 최악 오차(위치 최대)가 기준선 이하(두 데이터셋 모두).
  셋 다 통과해야 RTL로 넘어간다. 하나라도 실패하면 기각.
사용: (프로젝트 루트에서) python scripts/forgetting_test.py
"""
import os
import sys
import time

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from coord_transform_model import N_THETA
from rotation_estimate_model import circular_diff
import bayes_filter_fixed_model as bf
import efference_prior_test as ep

DEG = 360.0 / N_THETA


def run_decay(events, X, Y, L, K):
    n = N_THETA
    world_on = np.zeros((n, n), np.int8); world_off = np.zeros((n, n), np.int8)
    belief = np.zeros(n, np.int64); belief[0] = bf.BELIEF_INIT
    errs = []
    for i, (row, col, pol, gt) in enumerate(events):
        if K and i and i % K == 0:
            world_on >>= 1; world_off >>= 1
        k = row * 4 + col
        s = belief >> ep.EPS_SHIFT
        belief = belief - 2 * s + np.roll(s, 1) + np.roll(s, -1)
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
        errs.append(circular_diff(t, gt))
    return errs


def evaluate(name, positions, src, X, Y, L, Ks):
    rows = {k: [] for k in Ks}
    for pos in positions:
        ev = ep.get_events(name, pos, src)
        for k in Ks:
            e = run_decay(ev, X, Y, L, k)
            rows[k].append((ep.tail_mean(e) * DEG, max(e) * DEG))
        print(f"  {name}{pos} n={len(ev)} " + "  ".join(f"K={k}:{rows[k][-1][0]:.1f}/{rows[k][-1][1]:.1f}" for k in Ks), flush=True)
    return {k: (float(np.mean([m for m, _ in v])), float(max(w for _, w in v))) for k, v in rows.items()}


if __name__ == "__main__":
    X, Y, L, _ = ep.make_tables()
    Ks = [0, 256, 1024, 4096]
    t0 = time.time(); res = {}
    res["UZH"] = evaluate("uzh", ep.UZH_POS, None, X, Y, L, Ks)
    res["RobotEvt"] = evaluate("robot", ep.ROBOT_POS, ep.ROBOT, X, Y, L, Ks)
    print(f"\n(시간 {time.time() - t0:.0f}s)  평균(꼬리10%)° / 최악°")
    for ds, r in res.items():
        print(ds, "  ".join(f"K={k}: {m:.1f}/{w:.1f}" for k, (m, w) in r.items()))
    kbest = min([256, 1024, 4096], key=lambda k: res["UZH"][k][0])
    print("C1: UZH 기준 선택 K =", kbest)
    ok = True
    for ds, r in res.items():
        b = r[0]; c2 = r[kbest][0] <= 0.8 * b[0]; c3 = r[kbest][1] <= b[1]
        print(f"{ds}: C2 평균 {r[kbest][0]:.1f} <= 0.8*{b[0]:.1f} -> {c2} | C3 최악 {r[kbest][1]:.1f} <= {b[1]:.1f} -> {c3}")
        ok &= c2 and c3
    print("결과:", "통과(RTL 후보)" if ok else "기각")
