#!/usr/bin/env python3
# RTL 착수용 고정소수점 오라클 -- rotation_estimate_model.py:297 run_bayes_filter_proper()의
# float 로직을 정수 연산(RTL이 실제로 할 수 있는 연산: 시프트/덧셈/LUT참조/포화)으로 재구현해
# 비트폭·시프트-eps 근사·카운터 포화가 §128/130에서 확인한 정확도(고정 파라미터, 20곳 평균
# 20°대/최악 40°대)를 얼마나 갉아먹는지 RTL을 작성하기 전에 미리 확인한다.
#
# float 대비 바뀌는 것:
#   - 정규화: 매 스텝 합이 1이 되도록 나누는 대신, 최댓값이 너무 작아지면(RENORM_LOW 밑) 왼쪽
#     시프트로만 복구한다(나눗셈 없음, MAP 추정 순서는 스칼라 곱에 불변).
#   - diffuse_eps: 나눗셈 대신 오른쪽 시프트(eps_shift)로 근사(예: eps_shift=3 -> eps=0.125).
#   - 우도: (n_match+alpha)/(total+2*alpha)를 카운터 포화(0~CNT_MAX) 입력공간 전체에 대해
#     미리 계산한 정수 LUT(Q8, 0~256)로 대체 -- RTL의 case문 LUT와 동일한 내용.
import sys
import tempfile
import os

from coord_transform_model import N_THETA
from rotation_estimate_model import (
    load_events, build_transform_table, circular_diff, run_bayes_filter_proper,
)
import build_uzh_eventmeta_nxn
import build_uzh_pose_theta

BELIEF_BITS = 32
BELIEF_INIT = 1 << (BELIEF_BITS - 4)
RENORM_LOW = 1 << 16
CNT_MAX = 15
LIKE_BITS = 8
LIKE_SCALE = 1 << LIKE_BITS

EVENTS_TXT = "shapes_rotation/events.txt"
GROUNDTRUTH_TXT = "shapes_rotation/groundtruth.txt"

# §130에서 강건성 검증에 쓴 20곳(8곳 원위치 주변 + 240x180 전역 무작위 12곳), (x_center,y_center)
POSITIONS_20 = [
    (112, 87), (113, 88), (111, 86), (114, 89), (107, 81), (121, 96), (101, 71),
    (131, 101), (101, 59), (110, 123), (66, 49), (165, 108), (72, 86), (134, 47),
    (176, 104), (87, 44), (71, 95), (113, 48), (90, 51), (130, 94),
]


def make_like_lut(alpha):
    lut = {}
    for n_on in range(CNT_MAX + 1):
        for n_off in range(CNT_MAX + 1):
            total = n_on + n_off
            for pol in (0, 1):
                n_match = n_on if pol else n_off
                like = (n_match + alpha) / (total + 2 * alpha)
                lut[(n_on, n_off, pol)] = round(like * LIKE_SCALE)
    return lut


def run_bayes_filter_fixed(events, table, eps_shift, alpha, theta_log=None, maxb_log=None,
                            snapshot_event=None, snapshot_out=None):
    """run_bayes_filter_proper()의 정수 고정소수점판. eps_shift: diffuse_eps ~= 2**-eps_shift.
    alpha: 정식 사전(합성시점 상수, 정수 -- LUT를 유한하게 만들려면 정수여야 함).
    theta_log: 리스트를 넘기면 이벤트마다 map_theta를 append -- RTL 대조용 벡터 생성에 씀
    (rtl/bayes_filter.v, scripts/dump_bayes_filter_vectors.py).
    maxb_log: 리스트를 넘기면 이벤트마다 (likelihood 직후 max_b, 적용된 renorm shift)를 append
    -- RTL과의 divergence 지점을 찾는 디버깅용."""
    like_lut = make_like_lut(alpha)
    world_on = {}
    world_off = {}
    belief = [0] * N_THETA
    belief[0] = BELIEF_INIT
    errors = []
    collapsed = 0

    for ev_i, (row, col, pol, gt) in enumerate(events):
        if snapshot_event == ev_i and snapshot_out is not None:
            snapshot_out["pre"] = list(belief)
        new_belief = [0] * N_THETA
        for i in range(N_THETA):
            b, bl, br = belief[i], belief[i - 1], belief[(i + 1) % N_THETA]
            new_belief[i] = b - 2 * (b >> eps_shift) + (bl >> eps_shift) + (br >> eps_shift)
        belief = new_belief

        max_b = 0
        for theta_idx in range(N_THETA):
            X, Y = table[(row, col, theta_idx)]
            n_on = world_on.get((X, Y), 0)
            n_off = world_off.get((X, Y), 0)
            like = like_lut[(n_on, n_off, pol)]
            belief[theta_idx] = (belief[theta_idx] * like) >> LIKE_BITS
            if belief[theta_idx] > max_b:
                max_b = belief[theta_idx]

        if maxb_log is not None:
            maxb_log.append(max_b)
        if max_b == 0:
            # 전부 0으로 붕괴 -- 비트폭 부족 신호. 균등분포로 리셋하고 카운트만 남긴다.
            collapsed += 1
            belief = [BELIEF_INIT >> 8] * N_THETA
            max_b = belief[0]
        if max_b < RENORM_LOW:
            shift = 0
            while (max_b << (shift + 1)) < BELIEF_INIT:
                shift += 1
            if shift:
                belief = [b << shift for b in belief]

        if snapshot_event == ev_i and snapshot_out is not None:
            snapshot_out["post"] = list(belief)

        map_theta = max(range(N_THETA), key=lambda t: belief[t])
        X, Y = table[(row, col, map_theta)]
        if pol:
            world_on[(X, Y)] = min(world_on.get((X, Y), 0) + 1, CNT_MAX)
        else:
            world_off[(X, Y)] = min(world_off.get((X, Y), 0) + 1, CNT_MAX)
        errors.append(circular_diff(map_theta, gt))
        if theta_log is not None:
            theta_log.append(map_theta)

    if collapsed:
        print(f"  ! belief collapsed to 0 {collapsed}x -- BELIEF_BITS/LIKE_BITS 부족 의심", file=sys.stderr)
    return errors


def tail_mean(errors, frac=0.1):
    k = max(1, int(len(errors) * frac))
    return sum(errors[-k:]) / k


def build_patch_events(x_center, y_center, n=4, tmpdir=None, events_txt=None, groundtruth_txt=None):
    """events_txt/groundtruth_txt를 넘기면 shapes_rotation 대신 그 데이터셋을 씀 -- UZH와
    같은 포맷(t x y polarity / t tx ty tz qx qy qz qw)이면 아무 데이터셋이든 그대로 재사용
    가능(예: scripts/convert_robotevt_bag.py로 변환한 RobotEvt PureRot)."""
    events_txt = events_txt or EVENTS_TXT
    groundtruth_txt = groundtruth_txt or GROUNDTRUTH_TXT
    tmpdir = tmpdir or tempfile.gettempdir()
    ev_path = os.path.join(tmpdir, f"fx_{x_center}_{y_center}.tsv")
    aug_path = os.path.join(tmpdir, f"fx_{x_center}_{y_center}_theta.tsv")
    build_uzh_eventmeta_nxn.build(n, x_center, y_center, events_txt, ev_path)
    build_uzh_pose_theta.augment_eventmeta(ev_path, groundtruth_txt, aug_path)
    return load_events(aug_path, n)


def grid_search(eps_list, alpha_list, positions=POSITIONS_20):
    """§128/130의 파라미터 탐색을 커밋된 코드로 재현. run_bayes_filter_proper(float)을
    positions 전체에 대해 (eps,alpha) 그리드로 돌려, 평균 최소화/최악(minimax) 최소화
    두 기준 각각의 최선 설정을 찾는다. 이벤트 추출(파일 스캔)은 위치당 한 번만 하고
    캐시해서 재사용 -- 그리드 크기와 무관하게 위치 수만큼만 스캔한다."""
    table = build_transform_table(4)
    deg = 360.0 / N_THETA
    with tempfile.TemporaryDirectory() as tmp:
        cached = [(x, y, build_patch_events(x, y, 4, tmp)) for x, y in positions]

    results = []
    for eps in eps_list:
        for alpha in alpha_list:
            means, worsts = [], []
            for x, y, events in cached:
                err = run_bayes_filter_proper(events, table, eps, alpha)
                means.append(tail_mean(err) * deg)
                worsts.append(max(err) * deg)
            avg_mean = sum(means) / len(means)
            worst_max = max(worsts)
            results.append((eps, alpha, avg_mean, worst_max))
            print(f"eps={eps:5.3f} alpha={alpha:4.1f}  mean(avg)={avg_mean:5.1f}  worst(max)={worst_max:5.1f}")

    best_avg = min(results, key=lambda r: r[2])
    best_minimax = min(results, key=lambda r: r[3])
    print(f"\nN={len(cached)} positions, {len(results)} combos")
    print(f"best avg-optimized : eps={best_avg[0]}, alpha={best_avg[1]}  mean={best_avg[2]:.1f} worst={best_avg[3]:.1f}")
    print(f"best minimax        : eps={best_minimax[0]}, alpha={best_minimax[1]}  mean={best_minimax[2]:.1f} worst={best_minimax[3]:.1f}")
    return results, best_avg, best_minimax


def validate_positions(eps_shift, alpha, positions=POSITIONS_20, float_eps=None, float_alpha=None):
    """float 오라클과 고정소수점판을 같은 위치들에서 나란히 비교."""
    table = build_transform_table(4)
    deg = 360.0 / N_THETA
    fx_means, fx_worsts = [], []
    fl_means, fl_worsts = [], []
    with tempfile.TemporaryDirectory() as tmp:
        for x, y in positions:
            events = build_patch_events(x, y, 4, tmp)
            fx_err = run_bayes_filter_fixed(events, table, eps_shift, alpha)
            fx_mean, fx_worst = tail_mean(fx_err) * deg, max(fx_err) * deg
            fx_means.append(fx_mean); fx_worsts.append(fx_worst)
            line = f"({x:3d},{y:3d}) n={len(events):5d}  fixed(shift={eps_shift},a={alpha}): mean={fx_mean:5.1f} worst={fx_worst:5.1f}"
            if float_eps is not None:
                fl_err = run_bayes_filter_proper(events, table, float_eps, float_alpha)
                fl_mean, fl_worst = tail_mean(fl_err) * deg, max(fl_err) * deg
                fl_means.append(fl_mean); fl_worsts.append(fl_worst)
                line += f"   float(eps={float_eps},a={float_alpha}): mean={fl_mean:5.1f} worst={fl_worst:5.1f}"
            print(line)
    print(f"\nN={len(positions)} fixed  : mean(avg)={sum(fx_means)/len(fx_means):.1f} worst(max)={max(fx_worsts):.1f}")
    if fl_means:
        print(f"N={len(positions)} float  : mean(avg)={sum(fl_means)/len(fl_means):.1f} worst(max)={max(fl_worsts):.1f}")


if __name__ == "__main__":
    if "--grid" in sys.argv:
        # §131 정정: §128/130의 그리드서치 자체가 재현 불가능한 임시 코드로 나온 결과였음.
        # 같은 조합 수(56 = 7x8)로 커밋된 코드로 재확정한다.
        eps_list = [0.0, 0.01, 0.02, 0.05, 0.1, 0.15, 0.2]
        alpha_list = [0.25, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 5.0]
        grid_search(eps_list, alpha_list)
    else:
        # worst-tuned(eps=0.15,alpha=3.0, §128/130)의 하드웨어 근사: eps=1/8=0.125 -> eps_shift=3
        print("== worst-tuned 근사: eps_shift=3(eps=0.125 vs float 0.15), alpha=3 ==")
        validate_positions(eps_shift=3, alpha=3, float_eps=0.15, float_alpha=3.0)
