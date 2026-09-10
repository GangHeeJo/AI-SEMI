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

from coord_transform_model import N_THETA, transform

EVENTMETA_PATH = "common_traces_uzh/uzh_shapes_rotation_patch.eventmeta_theta.tsv"
PATCH_N = 4  # 로컬 센서 한 변 크기 -- §119(센서 커버리지 확장)부터 4가 아닌 값도 지원


def local_xy_from_row_col_n(row, col, n):
    """coord_transform_model.local_xy_from_row_col()의 일반화판(n=4일 때 완전히 동일한 값을
    냄) -- 그 함수는 4x4 전용 RTL(steal_buf)에 묶여있어서 건드리지 않고, 임의 크기 패치를
    쓰는 이 소프트웨어 실험 전용으로 여기에 따로 둔다."""
    xc2 = 2 * col - (n - 1)
    yc2 = 2 * row - (n - 1)
    return xc2, yc2


def load_events(path, n=PATCH_N):
    """(row, col, polarity, gt_theta_idx) 리스트. gt_theta_idx는 채점(정확도 측정)에만 쓰고
    추정 알고리즘 입력으로는 절대 안 씀."""
    events = []
    with open(path) as f:
        header = f.readline().rstrip("\n").split("\t")
        idx = {name: i for i, name in enumerate(header)}
        for line in f:
            parts = line.rstrip("\n").split("\t")
            source = int(parts[idx["source"]])
            row, col = source // n, source % n
            pol = int(parts[idx["polarity"]])
            gt_theta = int(parts[idx["theta_idx"]])
            events.append((row, col, pol, gt_theta))
    return events


def load_events_ts(path, n=PATCH_N):
    """load_events()와 같지만 타임스탬프도 같이 반환 -- §119에서 발견한 confound(패치가
    커질수록 같은 이벤트 개수가 더 짧은 실제 시간만 담는 문제)를 없앤 시간 기준 윈도우용."""
    events = []
    with open(path) as f:
        header = f.readline().rstrip("\n").split("\t")
        idx = {name: i for i, name in enumerate(header)}
        for line in f:
            parts = line.rstrip("\n").split("\t")
            source = int(parts[idx["source"]])
            row, col = source // n, source % n
            pol = int(parts[idx["polarity"]])
            gt_theta = int(parts[idx["theta_idx"]])
            ts_ns = int(parts[idx["occurrence_timestamp_ns"]])
            events.append((row, col, pol, gt_theta, ts_ns))
    return events


def build_transform_table(n=PATCH_N):
    """(row,col,theta_idx) -> (X,Y) 사전계산(n=4면 RMCM 룩업과 같은 4096가지 표) --
    매 윈도우마다 transform()을 다시 부르는 대신 이 표를 인덱싱해서 속도를 낸다."""
    table = {}
    for row in range(n):
        for col in range(n):
            xc2, yc2 = local_xy_from_row_col_n(row, col, n)
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


def run_window_time(events_ts, table, window_ms, min_events=1):
    """run_window_size()와 같은 채점/부트스트랩 로직이지만, 이벤트 개수 대신 실제 시간
    (window_ms) 단위로 윈도우를 자른다 -- N(패치 크기)이 달라져도 각 윈도우가 담는 실제
    시간 길이가 똑같아서 §119의 confound 없이 공정하게 비교 가능.

    min_events: 시간이 다 찼어도 이벤트가 이 개수 미만이면 계속 누적(다음 시간 구간과
    합침) -- 조용한 구간에서 이벤트 1~2개짜리 윈도우가 사실상 무작위 추정을 내고 그게
    causal하게 이후 윈도우까지 오염시키는 문제(실측으로 확인, §119 재실험)를 막는다."""
    world_mem = {}
    errors = []
    if not events_ts:
        return errors
    window_ns = window_ms * 1_000_000
    bucket_end = events_ts[0][4] + window_ns
    bucket = []

    def process(chunk):
        if not chunk:
            return
        scores = [0] * N_THETA
        for row, col, pol, _gt, _ts in chunk:
            for theta_idx in range(N_THETA):
                X, Y = table[(row, col, theta_idx)]
                cell = world_mem.get((X, Y))
                if cell is not None:
                    scores[theta_idx] += 1 if cell == pol else -1
        best_theta = max(range(N_THETA), key=lambda t: scores[t])
        if not world_mem:
            best_theta = 0
        for row, col, pol, _gt, _ts in chunk:
            X, Y = table[(row, col, best_theta)]
            world_mem[(X, Y)] = pol
        gt_repr = chunk[len(chunk) // 2][3]
        errors.append(circular_diff(best_theta, gt_repr))

    for ev in events_ts:
        if ev[4] >= bucket_end and len(bucket) >= min_events:
            process(bucket)
            bucket = []
            bucket_end = ev[4] + window_ns
        elif ev[4] >= bucket_end:
            bucket_end = ev[4] + window_ns  # 시간은 다 찼지만 개수 부족 -- 창을 밀고 계속 누적
        bucket.append(ev)
    process(bucket)
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


def run_bayes_filter(events, table, diffuse_eps=0.02, like_match=2.0, like_mismatch=0.5):
    """알고리즘 재설계(§122) -- Kim2014의 파티클 필터 정신을 우리 문제(theta가 정확히 256개
    이산값)에 맞게 다시 만듦: 파티클(몬테카를로 샘플) 대신 256개 상태 전부에 대한 정확한
    확률분포(belief)를 유지하는 이산 베이즈 필터(histogram filter). §117~120의 "윈도우마다
    1등만 뽑고 확정"(argmax, all-or-nothing) 방식이 근본 문제였다고 보고 -- 매 이벤트마다:
      1) 확산(diffuse_eps): "그새 조금 돌았을 수도 있다"를 반영해 belief를 살짝 펴줌 -- 한 번
         틀린 방향으로 쏠려도 나중에 복구 가능(§118 tracking에서 못 풀었던 lock-in 문제).
      2) 갱신: 이 이벤트가 world_mem과 맞으면 belief를 올리고(like_match), 틀리면
         내리고(like_mismatch), 안 쓰여있으면 그대로(중립) 곱한 뒤 정규화.
      3) 이번 이벤트는 belief의 최댓값(MAP) theta로 world_mem에 기록(causal, §117과 동일 철학).
    윈도우 개념 자체가 없어짐(매 이벤트가 곧 하나의 갱신) -- §119/120에서 계속 문제였던
    "윈도우를 개수/시간 중 뭘로 자르느냐"라는 confound 자체가 사라짐.
    """
    world_mem = {}
    belief = [0.0] * N_THETA
    belief[0] = 1.0  # 부트스트랩: 시작 자세 기준(우리 theta 정의와 일치, §117 참고) --
    # world_mem이 비어있는 동안은 모든 theta의 우도가 1(중립)이라 belief가 그대로 유지됨.
    errors = []

    for row, col, pol, gt in events:
        new_belief = [0.0] * N_THETA
        for i in range(N_THETA):
            new_belief[i] = ((1 - 2 * diffuse_eps) * belief[i]
                              + diffuse_eps * belief[i - 1]
                              + diffuse_eps * belief[(i + 1) % N_THETA])
        belief = new_belief

        total = 0.0
        for theta_idx in range(N_THETA):
            X, Y = table[(row, col, theta_idx)]
            cell = world_mem.get((X, Y))
            like = 1.0 if cell is None else (like_match if cell == pol else like_mismatch)
            belief[theta_idx] *= like
            total += belief[theta_idx]
        if total > 0:
            belief = [b / total for b in belief]

        map_theta = max(range(N_THETA), key=lambda t: belief[t])
        X, Y = table[(row, col, map_theta)]
        world_mem[(X, Y)] = pol
        errors.append(circular_diff(map_theta, gt))

    return errors


def run_bayes_filter_confidence(events, table, diffuse_eps=0.04, like_match=4.0, like_mismatch=0.25,
                                 max_strength=4):
    """run_bayes_filter()의 world_mem 표현을 강화한 판(§124) -- 칸마다 "마지막 극성 1개"만
    저장하던 걸 ON/OFF 관측 횟수 누적으로 바꿔서, 한 번 본 칸과 여러 번 일관되게 본 칸을
    다르게(신뢰도 가중) 취급한다. Kim2014의 지도가 단일 비트가 아니라 누적 gradient
    추정치인 것과 같은 방향 -- 정보 손실(반복 관측을 버리던 것)을 줄이는 게 목적.

    strength = min(총 관측횟수, max_strength) / max_strength (0~1) -- 처음 본 칸은 약하게,
    여러 번 일관되게 확인된 칸은 강하게 믿는다(포화형, 무한정 확신하지 않도록 상한을 둠).
    """
    world_on = {}
    world_off = {}
    belief = [0.0] * N_THETA
    belief[0] = 1.0
    errors = []

    for row, col, pol, gt in events:
        new_belief = [0.0] * N_THETA
        for i in range(N_THETA):
            new_belief[i] = ((1 - 2 * diffuse_eps) * belief[i]
                              + diffuse_eps * belief[i - 1]
                              + diffuse_eps * belief[(i + 1) % N_THETA])
        belief = new_belief

        total = 0.0
        for theta_idx in range(N_THETA):
            X, Y = table[(row, col, theta_idx)]
            n_on = world_on.get((X, Y), 0)
            n_off = world_off.get((X, Y), 0)
            n_total = n_on + n_off
            if n_total == 0:
                like = 1.0
            else:
                dominant = 1 if n_on > n_off else 0
                strength = min(n_total, max_strength) / max_strength
                if dominant == pol:
                    like = 1.0 + strength * (like_match - 1.0)
                else:
                    like = 1.0 - strength * (1.0 - like_mismatch)
            belief[theta_idx] *= like
            total += belief[theta_idx]
        if total > 0:
            belief = [b / total for b in belief]

        map_theta = max(range(N_THETA), key=lambda t: belief[t])
        X, Y = table[(row, col, map_theta)]
        if pol:
            world_on[(X, Y)] = world_on.get((X, Y), 0) + 1
        else:
            world_off[(X, Y)] = world_off.get((X, Y), 0) + 1
        errors.append(circular_diff(map_theta, gt))

    return errors


def run_bayes_filter_proper(events, table, diffuse_eps=0.04, prior_alpha=0.5):
    """run_bayes_filter_confidence()의 결함 수정판(§127) -- 그쪽의 `strength =
    min(총관측횟수,max_s)/max_s`는 5:5로 팽팽하게 갈린 칸도 "다수결" 극성을 무조건 강하게
    믿어버리는 결함이 있음(총 횟수만 보고 얼마나 쏠렸는지는 안 봄). 대신 정식 베이지안
    사후예측확률(Beta-Bernoulli 켤레사전분포, prior_alpha=Jeffreys류 유사사전)을 그대로 씀:
      P(이번 관측=pol | 이 칸의 지금까지 이력) = (해당 극성 관측횟수 + alpha) / (총 관측 + 2*alpha)
    안 본 칸은 자동으로 0.5(중립), 쏠릴수록 자연스럽게 0 또는 1에 가까워짐 -- like_match/
    like_mismatch/max_strength 같은 임의 하이퍼파라미터가 필요 없어짐(diffuse_eps, prior_alpha
    둘 뿐).
    """
    world_on = {}
    world_off = {}
    belief = [0.0] * N_THETA
    belief[0] = 1.0
    errors = []

    for row, col, pol, gt in events:
        new_belief = [0.0] * N_THETA
        for i in range(N_THETA):
            new_belief[i] = ((1 - 2 * diffuse_eps) * belief[i]
                              + diffuse_eps * belief[i - 1]
                              + diffuse_eps * belief[(i + 1) % N_THETA])
        belief = new_belief

        total = 0.0
        for theta_idx in range(N_THETA):
            X, Y = table[(row, col, theta_idx)]
            n_on = world_on.get((X, Y), 0)
            n_off = world_off.get((X, Y), 0)
            n_match = n_on if pol else n_off
            like = (n_match + prior_alpha) / (n_on + n_off + 2 * prior_alpha)
            belief[theta_idx] *= like
            total += belief[theta_idx]
        if total > 0:
            belief = [b / total for b in belief]

        map_theta = max(range(N_THETA), key=lambda t: belief[t])
        X, Y = table[(row, col, map_theta)]
        if pol:
            world_on[(X, Y)] = world_on.get((X, Y), 0) + 1
        else:
            world_off[(X, Y)] = world_off.get((X, Y), 0) + 1
        errors.append(circular_diff(map_theta, gt))

    return errors


def demo(eventmeta_path=EVENTMETA_PATH, n=PATCH_N):
    events = load_events(eventmeta_path, n)
    table = build_transform_table(n)
    print(f"patch={n}x{n} loaded {len(events)} real UZH events, theta 후보 {N_THETA}개, 사전계산 테이블 {len(table)}칸")

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

    print("-- v3(§122): 이산 베이즈 필터(윈도우 없음, 매 이벤트 갱신) --")
    for diffuse_eps in (0.0, 0.01, 0.02, 0.05):
        for like_match, like_mismatch in ((2.0, 0.5), (1.5, 0.7), (3.0, 0.3)):
            errors = run_bayes_filter(events, table, diffuse_eps, like_match, like_mismatch)
            mean_err = sum(errors) / len(errors)
            max_err = max(errors)
            last10pct = errors[-len(errors) // 10:]
            tail_mean = sum(last10pct) / len(last10pct)
            print(f"eps={diffuse_eps:.2f} like=({like_match},{like_mismatch}): "
                  f"mean_err={mean_err:5.2f}idx({mean_err*deg_per_idx:5.1f}deg) "
                  f"max_err={max_err:3d}idx({max_err*deg_per_idx:5.1f}deg) "
                  f"tail10%_mean={tail_mean*deg_per_idx:5.1f}deg")


if __name__ == "__main__":
    # usage: rotation_estimate_model.py [eventmeta.tsv] [N]
    path = sys.argv[1] if len(sys.argv) > 1 else EVENTMETA_PATH
    patch_n = int(sys.argv[2]) if len(sys.argv) > 2 else PATCH_N
    demo(path, patch_n)
