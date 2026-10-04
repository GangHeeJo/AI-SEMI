#!/usr/bin/env python3
# §171: 잔상 지표(합성 정답). precision = 맵 질량 중 정답 선 3px 이내 비율(1-precision = 잔상 질량), coverage = 정답 선 픽셀 중 2px 이내에 맵 이벤트가 있는 비율.
import sys
import numpy as np
from scipy import ndimage as ndi
from synth_evaluate import render_truth, prep, ncc_shift


def ghost(X, truth, R=330):
    C = X.shape[0]; T = render_truth(truth, C); PT = prep(T, C); n, dx, dy = ncc_shift(PT, prep(X, C))        # ncc_shift 반환 순서는 (NCC, dx, dy)
    Xs = np.roll(np.roll(X, dy, 0), dx, 1)                                                                     # b를 (dy,dx) 이동해 a와 맞춤 -> 같은 이동 적용
    c = C // 2; sl = (slice(c - R, c + R), slice(c - R, c + R))
    near3 = ndi.binary_dilation(T > 0.05 * T.max(), iterations=3)[sl]; near2 = ndi.binary_dilation(T > 0.05 * T.max(), iterations=2)[sl]
    M = Xs[sl]; prec = M[near3].sum() / M.sum()
    line = (T[sl] > 0.2 * T.max()); sup = ndi.binary_dilation(M > 0, iterations=2)
    return prec, float(sup[line].mean()), n, M.sum()


if __name__ == "__main__":
    truth = dict(np.load(sys.argv[1]))
    print(f"{'map':44s}{'NCC':>6s}{'ghost mass':>12s}{'coverage':>10s}{'events in view':>16s}")
    for p in sys.argv[2:]:
        X = np.load(p); pr, cv, n, m = ghost(X, truth); print(f"{p.split('/')[-1][:43]:44s}{n:6.3f}{(1-pr)*100:11.1f}%{cv*100:9.1f}%{m:16.0f}")
