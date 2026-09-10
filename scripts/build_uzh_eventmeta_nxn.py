#!/usr/bin/env python3
# build_uzh_eventmeta.py의 일반화판 -- 4x4 고정 대신 임의 크기 N x N 패치를 지원.
# §117/118에서 4x4 패치의 회전추정 정확도가 나빴던 원인이 "시야가 좁아서"인지 확인하려고
# 센서 커버리지를 넓혀서(N=8 등) 같은 실험을 다시 돌리기 위한 데이터 준비 단계.
#
# 원본(4x4 전용)은 1단계 실트래픽 검증에 이미 쓰이고 있어서 건드리지 않고, 이 파일을 따로 둠.
# 사용법: python build_uzh_eventmeta_nxn.py <N> <x_center> <y_center> <out.tsv>
#   예: python build_uzh_eventmeta_nxn.py 8 111 86 common_traces_uzh/uzh_shapes_rotation_8x8.eventmeta.tsv
#   (기존 4x4는 X0,X1=110,113 Y0,Y1=85,88 -> 중심 (111.5, 86.5)였으므로 기본 중심은 111,86 근방 권장)
import sys

BIN = 0.001  # 1ms/cycle, 4x4 버전과 동일 시간해상도


def build(n, x_center, y_center, events_path, out_path):
    half = n // 2
    x0, x1 = x_center - half, x_center - half + n - 1
    y0, y1 = y_center - half, y_center - half + n - 1
    print(f"patch: x=[{x0},{x1}] y=[{y0},{y1}] (n={n})")

    events = []  # (cyc, src, x, y, polarity, ts_ns)
    with open(events_path) as f:
        for line in f:
            parts = line.split()
            if len(parts) != 4:
                continue
            t = float(parts[0])
            x = int(parts[1]); y = int(parts[2])
            if not (x0 <= x <= x1 and y0 <= y <= y1):
                continue
            row = y - y0
            col = x - x0
            src = row * n + col
            cyc = int(t / BIN)
            polarity = int(parts[3])
            ts_ns = round(t * 1e9)
            events.append((cyc, src, x, y, polarity, ts_ns))

    events.sort(key=lambda e: (e[0], e[1]))

    seen = set()
    collisions = 0
    for cyc, src, x, y, polarity, ts_ns in events:
        key = (cyc, src)
        if key in seen:
            collisions += 1  # 4x4용 원본과 달리 여기선 크래시 대신 카운트만 함 -- 패치가
            # 커지면 발생할 수 있음, 심하면 BIN을 더 잘게 쪼개야 한다는 신호로 보고만 함.
        seen.add(key)

    with open(out_path, "w") as out:
        out.write("event_id\tcycle\tsource\tx\ty\tpolarity\toccurrence_timestamp_ns\n")
        for eid, (cyc, src, x, y, polarity, ts_ns) in enumerate(events):
            out.write(f"{eid}\t{cyc}\t{src}\t{x}\t{y}\t{polarity}\t{ts_ns}\n")

    print(f"events={len(events)} collisions={collisions} ({100.0*collisions/max(1,len(events)):.2f}%) -> {out_path}")


if __name__ == "__main__":
    if len(sys.argv) != 5:
        raise SystemExit("usage: build_uzh_eventmeta_nxn.py <N> <x_center> <y_center> <out.tsv> "
                          "(reads shapes_rotation/events.txt)")
    build(int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]), "shapes_rotation/events.txt", sys.argv[4])
