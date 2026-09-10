#!/usr/bin/env python3
# UZH가 아닌 완전히 독립된 실제 영상(KakaoTalk_20260907_201023489.mp4, 이벤트카메라 스타일
# 좌우분할 시각화 -- 왼쪽 흑백 인텐시티/오른쪽 이미 렌더링된 ON=빨강/OFF=파랑 이벤트)에서
# 왼쪽 흑백 프레임만 갖고 표준 DVS 온셋 방식(로그 인텐시티 차분 + 문턱값)으로 합성 이벤트를
# 만들어 우리 AER 트래픽 포맷(cycle+주소비트맵+극성비트맵)으로 변환한다.
#
# 시간 해상도는 convert_uzh_to_cyclemask.py(1ms=1cycle)와 반드시 맞춰야 한다 -- 처음에
# "프레임 하나(24fps=41.7ms)=1cycle"로 만들었더니 실제로는 41.7ms 동안 흩어져 발생했을
# 이벤트들이 전부 한 사이클에 뭉쳐서 인위적인 버스트가 생겼고(overrun 83.9%), 프레임 안에서
# 균등분포로 흩뿌려 1ms=1cycle로 다시 만들었더니 overrun 0%로 사라짐(진짜 RTL 한계가 아니라
# 변환 방식의 인공물이었음, progress.md 참고).
import math
import random
import sys

import cv2
import numpy as np

BIN_MS = 1.0  # convert_uzh_to_cyclemask.py와 동일 해상도(1ms=1cycle)
C_THRESH = math.log(1.15)  # ~15% 상대 밝기 변화가 문턱치(전형적 DVS contrast threshold)


def find_most_active_patch(cap, half_w, h, block=4, diff_thresh=15):
    """왼쪽 절반 전체를 스캔해서 프레임간 변화가 가장 많은 block x block 패치 위치를 찾는다."""
    prev = None
    activity = np.zeros((h, half_w), dtype=np.int64)
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        gray = cv2.cvtColor(frame[:, :half_w], cv2.COLOR_BGR2GRAY).astype(np.float32)
        if prev is not None:
            diff = np.abs(gray - prev)
            activity += (diff > diff_thresh).astype(np.int64)
        prev = gray
    best = (0, -1, -1)
    for y in range(0, h - block, 4):
        row_sum = np.sum(activity[y:y + block, :], axis=0)
        csum = np.insert(np.cumsum(row_sum), 0, 0)
        win = csum[block:] - csum[:-block]
        x = int(np.argmax(win))
        val = win[x]
        if val > best[0]:
            best = (val, y, x)
    return best[1], best[2]


def convert(video_path, out_addrpol, out_cycle_theta, block=4, seed=0):
    cap = cv2.VideoCapture(video_path)
    fps = cap.get(cv2.CAP_PROP_FPS)
    frame_dur_ms = 1000.0 / fps
    w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    half_w = w // 2

    y0, x0 = find_most_active_patch(cap, half_w, h, block=block)
    print(f"most active {block}x{block} patch: y={y0} x={x0}")

    cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
    rng = random.Random(seed)
    prev_log = None
    by_cycle = {}
    frame_idx = 0
    total_events = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        patch = frame[y0:y0 + block, x0:x0 + block, :]
        gray = cv2.cvtColor(patch, cv2.COLOR_BGR2GRAY).astype(np.float64)
        cur_log = np.log(gray + 1.0)
        if prev_log is not None:
            delta = cur_log - prev_log
            fired = np.abs(delta) > C_THRESH
            frame_start_ms = frame_idx * frame_dur_ms
            for r in range(block):
                for c in range(block):
                    if fired[r, c]:
                        src = r * block + c
                        pol = 1 if delta[r, c] > 0 else 0
                        # 프레임 구간 내 실제 발생 시점은 알 수 없으니 균등난수로 흩뿌려서
                        # 1ms=1cycle 해상도로 되돌린다(프레임=1cycle 압축의 인공적 버스트 방지).
                        t_ms = frame_start_ms + rng.uniform(0, frame_dur_ms)
                        cyc = int(t_ms / BIN_MS)
                        bit = 1 << src
                        addr, polm = by_cycle.get(cyc, (0, 0))
                        addr |= bit
                        if pol:
                            polm |= bit
                        by_cycle[cyc] = (addr, polm)
                        total_events += 1
            prev_log = np.where(fired, cur_log, prev_log)
        else:
            prev_log = cur_log
        frame_idx += 1
    cap.release()

    max_cyc = max(by_cycle)
    with open(out_addrpol, "w") as out:
        for cyc in sorted(by_cycle):
            addr, polm = by_cycle[cyc]
            out.write(f"{cyc} {addr:04x} {polm:04x}\n")
    with open(out_cycle_theta, "w") as f:
        for cyc in range(max_cyc + 1):
            f.write(f"{cyc} 0\n")  # 실제 pose 데이터 없음 -- 구조적 검증 전용, theta 상수 0

    print(f"frames={frame_idx} total_events={total_events} unique_active_cycles={len(by_cycle)} "
          f"max_cycle={max_cyc} -> {out_addrpol}, {out_cycle_theta}")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit("usage: convert_video_to_cyclemask.py <video.mp4> <out_addrpol.txt> <out_cycle_theta.txt>")
    convert(sys.argv[1], sys.argv[2], sys.argv[3])
