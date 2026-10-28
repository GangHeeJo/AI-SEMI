#!/usr/bin/env python3
# §142: contrast-max 파라미터 땜질(fb-smooth 등)이 아니라, 구조 자체가 다른 대안들을
# 직접 구현/실측해서 비교한다. 여기는 그 중 하나 -- CMax-SLAM류 "진짜" 배치 번들조정.
#
# 기존 run_contrast_max/_fb_smooth는 전부 "윈도우 단위로 독립 추정 + 국소적으로만 앞뒤 참고"
# 구조인데, 이 방식은 궤적 전체를 K개 제어점(control point)으로 대표하고(구간은 선형보간),
# **전체 시퀀스의 전역 명암대비(global contrast)를 한꺼번에** 좌표하강(coordinate descent)으로
# 재최적화한다 -- CMax-SLAM 논문의 spline bundle adjustment를 우리 스케일(이산 theta, 조수
# scipy 없음)에 맞게 가장 단순한 형태로 근사.
import sys
import tempfile

sys.path.insert(0, "scripts")
import build_uzh_eventmeta_nxn
import build_uzh_pose_theta
from rotation_estimate_model import build_transform_table, load_events_ts, circular_diff
from coord_transform_model import N_THETA

EVENTS_TXT = "shapes_rotation/events.txt"
GROUNDTRUTH_TXT = "shapes_rotation/groundtruth.txt"


def build_patch_events_ts(x_center, y_center, n=4, tmpdir=None):
    tmpdir = tmpdir or tempfile.gettempdir()
    ev_path = f"{tmpdir}/ba_{x_center}_{y_center}.tsv"
    aug_path = f"{tmpdir}/ba_{x_center}_{y_center}_theta.tsv"
    build_uzh_eventmeta_nxn.build(n, x_center, y_center, EVENTS_TXT, ev_path)
    build_uzh_pose_theta.augment_eventmeta(ev_path, GROUNDTRUTH_TXT, aug_path)
    return load_events_ts(aug_path, n)


def _score_theta(chunk, table, theta_idx):
    hist = {}
    for row, col, pol, _gt, _ts in chunk:
        key = (*table[(row, col, theta_idx)], pol)
        hist[key] = hist.get(key, 0) + 1
    return sum(c * c for c in hist.values())


def batch_bundle_adjust(events, table, n_ctrl=40, init_ctrl=None, radius=12, passes=4):
    """events: (row,col,pol,gt,ts_ns) 오름차순. n_ctrl개 제어점을 실시간축으로 균등 배치,
    구간 선형보간(가장 가까운 제어점 값으로 반올림)으로 각 이벤트의 theta를 결정.
    좌표하강: 제어점 하나씩(다른 건 고정) ±radius 범위에서 그 제어점이 담당하는 이벤트들의
    집중도 점수(Σcount^2)가 최대가 되는 값으로 갱신, 이를 passes회 반복(전역 수렴 근사).
    init_ctrl(길이 n_ctrl, 이미 알려진 초기 추정 -- 없으면 0)로 warm-start."""
    n = len(events)
    ts = [e[4] for e in events]
    t0, t1 = ts[0], ts[-1]
    span = max(t1 - t0, 1)
    bounds = [t0 + span * k / n_ctrl for k in range(n_ctrl + 1)]

    ctrl = list(init_ctrl) if init_ctrl else [0] * n_ctrl
    # 이벤트를 제어점 "구간"별로 미리 나눠둠(구간 k = bounds[k]~bounds[k+1])
    buckets = [[] for _ in range(n_ctrl)]
    bi = 0
    for e in events:
        while bi < n_ctrl - 1 and e[4] >= bounds[bi + 1]:
            bi += 1
        buckets[bi].append(e)

    for _p in range(passes):
        for k in range(n_ctrl):
            chunk = buckets[k]
            if not chunk:
                continue
            center = ctrl[k]
            best_score, best_theta = -1, center
            for d in range(-radius, radius + 1):
                theta_idx = (center + d) % N_THETA
                score = _score_theta(chunk, table, theta_idx)
                if score > best_score:
                    best_score, best_theta = score, theta_idx
            ctrl[k] = best_theta

    return ctrl, bounds


def theta_at(ctrl, bounds, ts_ns):
    for k in range(len(ctrl)):
        if ts_ns < bounds[k + 1] or k == len(ctrl) - 1:
            return ctrl[k]
    return ctrl[-1]


def evaluate(events, ctrl, bounds, window=16):
    deg = 360.0 / N_THETA
    errs = []
    n = len(events)
    for start in range(0, n - window + 1, window):
        chunk = events[start:start + window]
        gt_mid = chunk[window // 2][3]
        ts_mid = chunk[window // 2][4]
        est = theta_at(ctrl, bounds, ts_mid)
        errs.append(circular_diff(est, gt_mid) * deg)
    return errs


def demo():
    from rotation_estimate_model import run_contrast_max_fb_smooth

    events = build_patch_events_ts(112, 87, 4)
    table = build_transform_table(4)
    deg = 360.0 / N_THETA

    fb_errs = run_contrast_max_fb_smooth(
        [(r, c, p, g) for r, c, p, g, _ts in events], table, window=16, search_radius=30, smooth_k=9)
    fb_mean = sum(fb_errs) / len(fb_errs) * deg
    fb_worst = max(fb_errs) * deg
    print(f"fb-smooth(기존 최고): mean={fb_mean:5.1f}deg worst={fb_worst:6.1f}deg")

    for n_ctrl in (20, 40, 80):
        ctrl, bounds = batch_bundle_adjust(events, table, n_ctrl=n_ctrl, radius=12, passes=4)
        errs = evaluate(events, ctrl, bounds, window=16)
        mean_e = sum(errs) / len(errs) * deg
        worst_e = max(errs) * deg
        print(f"batch-BA(n_ctrl={n_ctrl:3d}): mean={mean_e:5.1f}deg worst={worst_e:6.1f}deg")


if __name__ == "__main__":
    demo()
