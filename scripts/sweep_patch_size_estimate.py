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
from rotation_estimate_model import N_THETA, build_transform_table, load_events_ts, run_window_time

GROUNDTRUTH = "common_traces_uzh/uzh_shapes_rotation_groundtruth.txt"
EVENTS_TXT = "shapes_rotation/events.txt"
OUT_DIR = "common_traces_uzh"
CENTER_X, CENTER_Y = 111, 86  # 기존 4x4 패치(110-113,85-88) 중심과 동일 -- N을 키워도
                              # 같은 물리적 위치를 계속 관측해야 비교가 공정함
WINDOW_MS_LIST = (50, 100, 200, 400, 800)  # §119 확인: 이벤트 "개수" 대신 실제 시간으로
                                            # 잘라야 N마다 윈도우가 같은 시간폭을 담아 공정함


def run_one(n):
    eventmeta = os.path.join(OUT_DIR, f"uzh_shapes_rotation_{n}x{n}.eventmeta.tsv")
    eventmeta_theta = os.path.join(OUT_DIR, f"uzh_shapes_rotation_{n}x{n}.eventmeta_theta.tsv")
    build_eventmeta(n, CENTER_X, CENTER_Y, EVENTS_TXT, eventmeta)
    augment_eventmeta(eventmeta, GROUNDTRUTH, eventmeta_theta)

    events_ts = load_events_ts(eventmeta_theta, n)
    table = build_transform_table(n)
    best = None
    for window_ms in WINDOW_MS_LIST:
        errors = run_window_time(events_ts, table, window_ms, min_events=16)
        if not errors:
            continue
        mean_err = sum(errors) / len(errors)
        if best is None or mean_err < best[1]:
            best = (window_ms, mean_err, max(errors), len(errors))
    return len(events_ts), best


def main():
    sizes = [int(x) for x in sys.argv[1:]] if len(sys.argv) > 1 else [4, 6, 8, 12, 16]
    deg_per_idx = 360.0 / N_THETA
    print(f"{'N':>4} {'events':>8} {'best_Wms':>8} {'windows':>7} {'mean_err(idx)':>14} {'mean_err(deg)':>14} {'max_err(deg)':>13}")
    for n in sizes:
        n_events, (window_ms, mean_err, max_err, n_windows) = run_one(n)
        print(f"{n:4d} {n_events:8d} {window_ms:8d} {n_windows:7d} {mean_err:14.2f} {mean_err*deg_per_idx:14.1f} {max_err*deg_per_idx:13.1f}")


if __name__ == "__main__":
    main()
