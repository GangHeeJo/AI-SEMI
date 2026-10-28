#!/usr/bin/env python3
# §139: 1차 arbiter(cluster2_steal_buf_polarity_pose)가 실제로 만드는 "배출 순서"가
# 2차 contrast-max 회전추정 정확도를 얼마나 해치는지 직접 측정.
#
# tb/tb_arbiter_reorder_capture.v가 실 RTL을 실 UZH 트레이스(패치 112,87)로 구동해
# common_traces_uzh/uzh_shapes_rotation_patch.arbiter_delivered.txt에
# "cycle row col pol true_arrival_cycle"을 배출 순서 그대로 남겼다(true_arrival_cycle은
# RTL 밖 TB에서 pending_cnt/FIFO push-pop을 그대로 미러링해 복원한 값 -- 8비트 pose_mask는
# 옛 256단계 스케일에 고정돼 있어 현재 1024단계 ground truth와 안 맞아서 안 씀).
#
# 비교:
#   baseline = build_patch_events(112,87,4) -- 진짜 시간순(§136/137에서 쓴 것과 동일 소스)
#   reordered = arbiter_delivered.txt를 배출 순서 그대로 읽되, 각 이벤트의 ground truth는
#               "진짜 도착 사이클"로 재계산(배출 사이클이 아니라) -- 그래서 순서만 다르고
#               ground truth 매핑 방식은 baseline과 완전히 동일.
import sys

sys.path.insert(0, "scripts")
from bayes_filter_fixed_model import build_patch_events
from build_uzh_pose_theta import build_theta_lookup, load_groundtruth, theta_at, theta_to_idx
from rotation_estimate_model import build_transform_table, run_contrast_max

DELIVERED_TXT = "common_traces_uzh/uzh_shapes_rotation_patch.arbiter_delivered.txt"
GROUNDTRUTH_TXT = "shapes_rotation/groundtruth.txt"
BIN_S = 0.001  # build_uzh_eventmeta.py/export_cycle_theta와 동일한 1cyc=1ms 매핑


def load_reordered_events():
    gt_ts_ns, gt_quats = load_groundtruth(GROUNDTRUTH_TXT)
    theta_lookup = build_theta_lookup(gt_ts_ns, gt_quats)
    ts_only = [t for t, _ in theta_lookup]

    events = []
    with open(DELIVERED_TXT) as f:
        for line in f:
            parts = line.split()
            if len(parts) != 5:
                continue
            _deliver_cyc, row, col, pol, true_cyc = (int(x) for x in parts)
            query_ns = round(true_cyc * BIN_S * 1e9)
            theta = theta_at(theta_lookup, ts_only, query_ns)
            gt_theta_idx = theta_to_idx(theta)
            events.append((row, col, pol, gt_theta_idx))
    return events


def summarize(name, errors, deg_per_idx):
    mean_err = sum(errors) / len(errors) * deg_per_idx
    worst_err = max(errors) * deg_per_idx
    print(f"{name:12s}: windows={len(errors):4d} mean={mean_err:5.1f}deg worst={worst_err:5.1f}deg")
    return mean_err, worst_err


def main():
    table = build_transform_table(4)
    from coord_transform_model import N_THETA
    deg_per_idx = 360.0 / N_THETA

    baseline_events = build_patch_events(112, 87, 4)
    reordered_events = load_reordered_events()
    print(f"baseline events={len(baseline_events)} reordered events={len(reordered_events)}")
    assert len(baseline_events) == len(reordered_events), "이벤트 개수가 다름 -- 캡처 트레이스 확인 필요"

    for radius in (None, 30):
        tag = "global" if radius is None else f"radius={radius}"
        print(f"-- {tag} --")
        base_err = run_contrast_max(baseline_events, table, window=16, search_radius=radius)
        reord_err = run_contrast_max(reordered_events, table, window=16, search_radius=radius)
        summarize("chrono(true)", base_err, deg_per_idx)
        summarize("arbiter-order", reord_err, deg_per_idx)


if __name__ == "__main__":
    main()
