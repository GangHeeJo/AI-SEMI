#!/usr/bin/env python3
# §159: 선 방향 기반 theta(t) (delta_gt_orientation.py의 psi 측정값) -> 4ms 창 중앙 시각의 theta 배열.
# 직선 방향은 병진/깊이에 불변이라 시차 편향이 없다(합성 정답 검증: RMS 0.9도, CMax 적분은 -21% 편향).
# 일관도가 낮은 프레임은 이웃에서 보간. 영상 값은 코드에 없음(일관도 임계값 0.6은 일반 규칙).
import sys

import numpy as np

COH_MIN = 0.6


def theta_from_psi(psi_raw_npy, n_win, win_ms=4):
    r = np.load(psi_raw_npy)
    t = r[:, 0] + 10.0; psi = r[:, 3].copy(); coh = r[:, 4]
    good = np.isfinite(psi) & (coh >= COH_MIN)
    # 감김 풀기는 신뢰 프레임만으로(시간 연속성), 저신뢰 프레임은 보간
    un = np.full(len(psi), np.nan); prev = None
    for i in np.flatnonzero(good):
        v = psi[i]
        if prev is not None: v += -90 * np.round((v - prev) / 90)
        un[i] = v; prev = v
    un = np.interp(t, t[good], un[good])
    th = np.radians(un - un[0])
    mids = np.arange(n_win) * win_ms + win_ms / 2
    return np.interp(mids, t, th), float(good.mean())


if __name__ == "__main__":
    # usage: delta_theta_from_orientation.py <gt_psi_raw.npy> <n_windows> <out_theta.npy>
    th, frac = theta_from_psi(sys.argv[1], int(sys.argv[2]))
    np.save(sys.argv[3], th)
    print(f"theta from orientation: final {np.degrees(th[-1]):.1f} deg, reliable frames {frac:.2f}")
