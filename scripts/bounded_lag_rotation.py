#!/usr/bin/env python3
# §146: bounded-lag(L윈도우 지연) 스무딩을 UZH 20곳 전체에서 검증 (§142는 단일패치(112,87)만).
# 정방향 causal 추적(_cmax_track) 한 번 + 윈도우 i의 출력 = fwd[i-L..i+L]의 원순환 평균.
# 즉 출력 지연 = L윈도우(=16*L 이벤트 FIFO). L=0이면 순수 causal과 동일.
import sys

sys.path.insert(0, "scripts")
from bayes_filter_fixed_model import POSITIONS_20, build_patch_events
from coord_transform_model import N_THETA
from rotation_estimate_model import _circular_mean, _cmax_track, build_transform_table, circular_diff

WINDOW, RADIUS = 16, 30
LS = (0, 4, 8, 16)


def bounded_lag_errs(events, table, L):
    n = len(events)
    chunks = [events[s:s + WINDOW] for s in range(0, n - WINDOW + 1, WINDOW)]
    gts = [c[WINDOW // 2][3] for c in chunks]
    fwd = _cmax_track(chunks, table, RADIUS)
    return [circular_diff(_circular_mean(fwd[max(0, i - L):i + L + 1]), gts[i]) for i in range(len(fwd))]


def main():
    table = build_transform_table(4)
    deg = 360.0 / N_THETA
    means = {L: [] for L in LS}
    worsts = {L: [] for L in LS}
    for pos in POSITIONS_20:
        events = build_patch_events(*pos, 4)
        row = []
        for L in LS:
            e = bounded_lag_errs(events, table, L)
            means[L].append(sum(e) / len(e) * deg)
            worsts[L].append(max(e) * deg)
            row.append(f"L={L}: {means[L][-1]:5.1f}/{worsts[L][-1]:6.1f}")
        print(pos, " | ".join(row), flush=True)
    print("== 20곳 집계 (평균의 평균 / 최악의 최대) ==")
    for L in LS:
        print(f"L={L:2d}: avg={sum(means[L]) / len(means[L]):5.1f}deg max={max(worsts[L]):6.1f}deg")


if __name__ == "__main__":
    main()
