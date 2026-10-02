#!/usr/bin/env python3
# §160: 선 방향 psi(병진 불변, 절대각 정확, 단 가장 빠른/원근선 구간에서 신뢰 불가)를 기준점(anchor)으로 쓰고, 기준점 사이
# 빈 구간은 CMax 누적각의 "모양"을 두 끝점 값에 맞춰 늘려 채운다(국소 배율 하나, 전역 배율 피팅은 노이즈에 과적합해서 폐기).
#  - 기준점 = 직선 >= 10개 & 일관도 >= 0.85 인 프레임(일반 규칙)
#  - psi는 90도 주기: 연속 기준점 사이 증분이 (국소 배율 x CMax 증분)에 가장 가깝도록 순차 감김 풀기
#  - 구간 [a,b]: theta(t) = theta_a + (theta_b - theta_a) * (C(t)-C(a)) / (C(b)-C(a)),  C = CMax 누적각
#    (|C(b)-C(a)| < 1도면 선형), 첫/마지막 기준점 밖은 가장 가까운 구간의 배율로 CMax를 외삽
import sys

import numpy as np

MIN_LINES, MIN_COH = 10, 0.85


def fuse(omega_npy, psi_npy, win_ms=4):
    res = np.load(omega_npy); r = np.load(psi_npy)
    n = len(res); mids = np.arange(n) * win_ms + win_ms / 2.0
    w_c = res[:, 1]
    C = np.cumsum(w_c * win_ms * 1e-3) - 0.5 * w_c * win_ms * 1e-3            # 창 중앙에서의 CMax 누적각(rad)
    tf = r[:, 0] + 10.0; nl = r[:, 2]; psi = np.radians(r[:, 3]); coh = r[:, 4]
    good = np.flatnonzero(np.isfinite(psi) & (nl >= MIN_LINES) & (coh >= MIN_COH))
    Cf = np.interp(tf, mids, C)
    per = np.pi / 2; un = [psi[good[0]]]; g = 1.0
    for a, b in zip(good[:-1], good[1:]):
        pred = g * (Cf[b] - Cf[a])
        un.append(psi[b] + per * np.round((un[-1] + pred - psi[b]) / per))
        if abs(Cf[b] - Cf[good[0]]) > 0.3:
            g = float(np.clip((un[-1] - un[0]) / (Cf[b] - Cf[good[0]]), 0.6, 1.4))
    un = np.array(un); ta = tf[good]; Ca = Cf[good]
    th = np.zeros(n)
    for i, t in enumerate(mids):
        j = np.searchsorted(ta, t)
        if j == 0:                                   # 첫 기준점 이전: 첫 구간 배율로 CMax 외삽
            gg = (un[1] - un[0]) / (Ca[1] - Ca[0]) if len(un) > 1 and abs(Ca[1] - Ca[0]) > 0.02 else 1.0
            th[i] = un[0] + gg * (C[i] - Ca[0]) if abs(C[i] - Ca[0]) > 0 else un[0]
        elif j == len(ta):                           # 마지막 기준점 이후
            gg = (un[-1] - un[-2]) / (Ca[-1] - Ca[-2]) if len(un) > 1 and abs(Ca[-1] - Ca[-2]) > 0.02 else 1.0
            th[i] = un[-1] + gg * (C[i] - Ca[-1])
        else:
            a, b = j - 1, j
            dC = Ca[b] - Ca[a]
            s = (C[i] - Ca[a]) / dC if abs(dC) > np.radians(1.0) else (t - ta[a]) / (ta[b] - ta[a])
            th[i] = un[a] + (un[b] - un[a]) * float(np.clip(s, -0.2, 1.2))
    th -= th[0]
    return th, dict(n_reliable=len(good), n_frames=len(r), anchors_ms=ta.tolist(), gain_last=g)


if __name__ == "__main__":
    # usage: delta_theta_fuse.py <omega_cmax.npy> <gt_psi_raw.npy> <out_theta.npy>
    th, info = fuse(sys.argv[1], sys.argv[2])
    np.save(sys.argv[3], th)
    gaps = [(int(a), int(b)) for a, b in zip(info["anchors_ms"][:-1], info["anchors_ms"][1:]) if b - a > 25]
    print("anchors %d/%d frames; gaps >25ms (ms): %s; final theta %.1f deg" % (info["n_reliable"], info["n_frames"], gaps, np.degrees(th[-1])))
