#!/usr/bin/env python3
# 여러 패치 크기(N)에 대해 build_uzh_eventmeta_nxn -> build_uzh_pose_theta ->
# rotation_estimate_model을 자동으로 돌려서 "시야를 넓히면 회전추정 정확도가 실제로
# 나아지는가"를 한 번에 표로 보여주는 드라이버(§117~119). N=4는 기존 4x4 베이스라인과
# 정확히 같은 결과가 나와야 함(있어야 할 sanity check 겸용, 같은 중심 좌표 재사용).
#
# 사용법(shapes_rotation.zip을 프로젝트 루트에 압축해제한 뒤): python scripts/sweep_patch_size_estimate.py [N1 N2 ...]
import os
import sys

from build_uzh_eventmeta_nxn import build as build_eventmeta
from build_uzh_pose_theta import augment_eventmeta
from rotation_estimate_model import N_THETA, build_transform_table, load_events, run_bayes_filter

GROUNDTRUTH = "common_traces_uzh/uzh_shapes_rotation_groundtruth.txt"
EVENTS_TXT = "shapes_rotation/events.txt"
OUT_DIR = "common_traces_uzh"
CENTER_X, CENTER_Y = 112, 87  # 기존 4x4 패치(110-113,85-88)를 정확히 재현하는 중심 --
                              # (n=4일 때 x0=center-2=110,x1=x0+3=113로 정확히 일치, 이벤트수
                              # 8503으로 검증됨). §123에서 (111,86)이 실수로 1픽셀 어긋난
                              # 다른(훨씬 안 좋은) 패치였음을 발견 -- 반드시 (112,87) 사용.
                              # N을 키워도 같은 물리적 위치를 계속 관측해야 비교가 공정함.
# §122에서 찾은 튜닝값(원래 4x4 패치 기준 최선) -- 이산 베이즈 필터, 윈도우 없음
DIFFUSE_EPS = 0.04
LIKE_MATCH = 4.0
LIKE_MISMATCH = 0.25


def run_one(n):
    eventmeta = os.path.join(OUT_DIR, f"uzh_shapes_rotation_{n}x{n}.eventmeta.tsv")
    eventmeta_theta = os.path.join(OUT_DIR, f"uzh_shapes_rotation_{n}x{n}.eventmeta_theta.tsv")
    build_eventmeta(n, CENTER_X, CENTER_Y, EVENTS_TXT, eventmeta)
    augment_eventmeta(eventmeta, GROUNDTRUTH, eventmeta_theta)

    events = load_events(eventmeta_theta, n)
    table = build_transform_table(n)
    errors = run_bayes_filter(events, table, DIFFUSE_EPS, LIKE_MATCH, LIKE_MISMATCH)
    mean_err = sum(errors) / len(errors)
    max_err = max(errors)
    tail = errors[-len(errors) // 10:]
    tail_mean = sum(tail) / len(tail)
    return len(events), mean_err, max_err, tail_mean


def main():
    sizes = [int(x) for x in sys.argv[1:]] if len(sys.argv) > 1 else [4, 6, 8, 12, 16]
    deg_per_idx = 360.0 / N_THETA
    print(f"{'N':>4} {'events':>8} {'mean_err(deg)':>14} {'max_err(deg)':>13} {'tail10%(deg)':>13}")
    for n in sizes:
        n_events, mean_err, max_err, tail_mean = run_one(n)
        print(f"{n:4d} {n_events:8d} {mean_err*deg_per_idx:14.1f} {max_err*deg_per_idx:13.1f} {tail_mean*deg_per_idx:13.1f}")


if __name__ == "__main__":
    main()
