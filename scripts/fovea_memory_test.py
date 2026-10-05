#!/usr/bin/env python3
# §208: 중심와(fovea) 월드 메모리 시험. 월드맵 중심(반지름 rf)은 원래 해상도, 바깥은 f x f로 묶어(합 보존) 저장했다가 같은 평균 밀도로 되돌려 정답 장면과의 NCC를 잰다.
# 메모리 칸 수 = (pi rf^2 + pi (R0^2 - rf^2) / f^2) / (pi R0^2), R0 = 420 px(평가 NCC가 보는 반경). 중심은 지도 질량의 무게중심이 아니라 캔버스 중심(회전 중심에 가까운 쪽)으로 고정.
# 사용: fovea_memory_test.py <map.npy> <truth.npz>
import sys

import numpy as np
from scipy import ndimage as ndi

sys.path.insert(0, "scripts")
from ghost_metric import ghost  # noqa: E402

M = np.load(sys.argv[1]); T = dict(np.load(sys.argv[2])); C = M.shape[0]; R0 = 420
yy, xx = np.mgrid[:C, :C]; r = np.hypot(xx - C / 2, yy - C / 2)


def pooled(M, f):
    n = (C // f) * f; P = M[:n, :n].reshape(n // f, f, n // f, f).sum((1, 3)) / (f * f); return np.kron(P, np.ones((f, f)))[:C, :C] if n == C else np.pad(np.kron(P, np.ones((f, f))), ((0, C - n), (0, C - n)))


def foveate(M, rf, f): return np.where(r <= rf, M, pooled(M, f))


base = ghost(M, T)[2]; print(f"full resolution NCC {base:.3f}  (map {M.shape}, evaluation radius {R0})")
print(f"{'fovea radius':>13s}{'periphery pooling':>19s}{'memory cells (rel.)':>21s}{'NCC':>8s}{'delta NCC':>11s}")
good = []
for rf in (120, 210, 300):
    for f in (2, 4, 8):
        mem = (np.pi * rf ** 2 + np.pi * (R0 ** 2 - rf ** 2) / f ** 2) / (np.pi * R0 ** 2); n = ghost(foveate(M, rf, f), T)[2]
        print(f"{rf:13d}{f:>16d}x{f}{mem * 100:20.0f}%{n:8.3f}{n - base:+11.3f}"); good.append((mem, n - base, rf, f))
for f in (2, 4, 8):
    n = ghost(pooled(M, f), T)[2]; print(f"{'none (all)':>13s}{f:>16d}x{f}{100 / f ** 2:20.0f}%{n:8.3f}{n - base:+11.3f}")
ok = [g for g in good if g[0] <= 0.5 and g[1] >= -0.02]
print("promising settings (memory <= 50% and NCC drop <= 0.02):", [(round(m, 2), rf, f) for m, d, rf, f in ok] if ok else "none")
