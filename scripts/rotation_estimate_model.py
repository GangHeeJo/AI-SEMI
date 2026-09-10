#!/usr/bin/env python3
# Digital 2차 2단계(회전각 직접 추정) 소프트웨어 오라클 -- RTL 착수 전 정확도 실측 전용.
# 문헌조사(reference_papers.md 2-C)에서 좁힌 아이디어: Kim2014(파티클 필터)의 "후보 채점"과
# EROAM(구면 ICP)의 "기존 지도와 대조"를, 우리가 1단계에서 이미 만든 인프라(theta_idx 256개
# 이산 LUT, world_mem 규칙 격자) 위에 그대로 얹는다 -- 파티클/k-d tree 둘 다 필요 없어짐.
#
# 알고리즘(윈도우 단위, causal -- 매 순간 "지금까지의 자기 추정"만으로 이어감):
#   1. 윈도우의 각 이벤트를 후보 theta_idx(0~255) 전부로 transform() -> 예측 world (X,Y).
#   2. world_mem에 이미 그 칸이 쓰여있으면 극성 일치 +1 / 불일치 -1, 안 쓰여있으면 0(중립).
#   3. 윈도우 전체 합산 점수가 최고인 후보를 이 윈도우의 추정 theta로 채택, world_mem 갱신.
#   4. 추정치를 ground-truth theta_idx(eventmeta_theta.tsv, 추정 로직에는 안 먹임, 채점용으로만
#      사후 비교)와 대조해서 오차를 측정한다.
#
# 이 스크립트는 RTL을 전혀 안 건드림 -- 정확도가 나쁘면 여기서 멈추고 방향을 다시 잡는다.

import sys
from collections import defaultdict

from coord_transform_model import N_THETA, local_xy_from_row_col, transform

EVENTMETA_PATH = "common_traces_uzh/uzh_shapes_rotation_patch.eventmeta_theta.tsv"


def load_events(path):
    """(row, col, polarity, gt_theta_idx) 리스트. gt_theta_idx는 채점(정확도 측정)에만 쓰고
    추정 알고리즘 입력으로는 절대 안 씀."""
    events = []
    with open(path) as f:
        header = f.readline().rstrip("\n").split("\t")
        idx = {name: i for i, name in enumerate(header)}
        for line in f:
            parts = line.rstrip("\n").split("\t")
            source = int(parts[idx["source"]])
            row, col = source // 4, source % 4
            pol = int(parts[idx["polarity"]])
            gt_theta = int(parts[idx["theta_idx"]])
            events.append((row, col, pol, gt_theta))
    return events


def build_transform_table():
    """(row,col,theta_idx) -> (X,Y) 전체 4096가지 사전계산 -- RMCM 룩업과 같은 표,
    매 윈도우마다 transform()을 다시 부르는 대신 이 표를 인덱싱해서 속도를 낸다."""
    table = {}
    for row in range(4):
        for col in range(4):
            xc2, yc2 = local_xy_from_row_col(row, col)
            for theta_idx in range(N_THETA):
                table[(row, col, theta_idx)] = transform(xc2, yc2, theta_idx)
    return table


def circular_diff(a, b, n=N_THETA):
    d = abs(a - b) % n
    return min(d, n - d)


def run_window_size(events, table, window):
    world_mem = {}  # (X,Y) -> polarity
    errors = []
    n = len(events)
    for start in range(0, n, window):
        chunk = events[start:start + window]
        scores = [0] * N_THETA
        for row, col, pol, _gt in chunk:
            for theta_idx in range(N_THETA):
                X, Y = table[(row, col, theta_idx)]
                cell = world_mem.get((X, Y))
                if cell is not None:
                    scores[theta_idx] += 1 if cell == pol else -1
        best_theta = max(range(N_THETA), key=lambda t: scores[t])
        if not world_mem:
            best_theta = 0  # 부트스트랩: 첫 윈도우는 전부 0점 동점 -- 우리 theta 정의(시작 자세
            # 기준 상대 회전각) 자체와 일치하는 기준점이라 이게 임시방편이 아니라 정의상 맞는 값.

        for row, col, pol, _gt in chunk:
            X, Y = table[(row, col, best_theta)]
            world_mem[(X, Y)] = pol

        gt_repr = chunk[len(chunk) // 2][3]  # 윈도우 중간 이벤트의 실제 theta를 대표값으로 사용
        errors.append(circular_diff(best_theta, gt_repr))
    return errors


def run_tracking(events, table, window, radius):
    """개선판 -- 매 윈도우마다 256개 후보 전부를 다시 찾는 대신, 직전 추정치 근방
    [-radius,+radius] 안에서만 찾는다("회전은 갑자기 안 튄다"는 물리적 연속성 가정,
    실제 추적 시스템에서 흔한 기법). 전수 탐색이 국소적으로 비슷해 보이는(aliasing) 먼
    후보로 튀는 걸 막아서 안정성이 나아지는지 확인하는 게 목적."""
    world_mem = {}
    errors = []
    current = 0
    n = len(events)
    for start in range(0, n, window):
        chunk = events[start:start + window]
        candidates = range(N_THETA) if not world_mem else [
            (current + d) % N_THETA for d in range(-radius, radius + 1)
        ]
        best_theta, best_score = None, None
        for theta_idx in candidates:
            score = 0
            for row, col, pol, _gt in chunk:
                X, Y = table[(row, col, theta_idx)]
                cell = world_mem.get((X, Y))
                if cell is not None:
                    score += 1 if cell == pol else -1
            if best_score is None or score > best_score:
                best_score, best_theta = score, theta_idx

        if not world_mem:
            best_theta = 0  # 부트스트랩(run_window_size와 동일 이유)

        current = best_theta
        for row, col, pol, _gt in chunk:
            X, Y = table[(row, col, best_theta)]
            world_mem[(X, Y)] = pol

        gt_repr = chunk[len(chunk) // 2][3]
        errors.append(circular_diff(best_theta, gt_repr))
    return errors


def demo():
    events = load_events(EVENTMETA_PATH)
    table = build_transform_table()
    print(f"loaded {len(events)} real UZH events, theta 후보 {N_THETA}개, 사전계산 테이블 {len(table)}칸")

    deg_per_idx = 360.0 / N_THETA

    print("-- v1: 매 윈도우 256개 후보 전수탐색 --")
    for window in (8, 16, 32, 64):
        errors = run_window_size(events, table, window)
        mean_err = sum(errors) / len(errors)
        max_err = max(errors)
        print(f"W={window:3d}: windows={len(errors):4d} "
              f"mean_err={mean_err:5.2f}idx({mean_err*deg_per_idx:5.1f}deg) "
              f"max_err={max_err:3d}idx({max_err*deg_per_idx:5.1f}deg)")

    print("-- v2: 직전 추정치 근방(radius)만 탐색(tracking) --")
    for window in (4, 8, 16):
        for radius in (4, 8, 16, 32):
            errors = run_tracking(events, table, window, radius)
            mean_err = sum(errors) / len(errors)
            max_err = max(errors)
            print(f"W={window:3d} radius={radius:3d}: windows={len(errors):4d} "
                  f"mean_err={mean_err:5.2f}idx({mean_err*deg_per_idx:5.1f}deg) "
                  f"max_err={max_err:3d}idx({max_err*deg_per_idx:5.1f}deg)")


if __name__ == "__main__":
    if len(sys.argv) > 1:
        EVENTMETA_PATH = sys.argv[1]
    demo()
