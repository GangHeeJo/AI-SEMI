#!/usr/bin/env python3
# UZH shapes_rotation의 진짜 이벤트(events.txt: timestamp x y polarity)를 우리
# cyclemask.txt 포맷(사이클번호 + 16비트 도착 비트맵)으로 변환. 240x180 센서 중
# 4x4 패치만 잘라 우리 N=16 소스공간에 매핑(source=row*4+col). 극성은 우리 AER
# 스코프 밖(주소만 다룸)이라 ON/OFF 구분 없이 "이 소스가 이 사이클에 발화했다"만 기록.
import sys

X0, X1 = 110, 113
Y0, Y1 = 85, 88
BIN = 0.001  # 1ms/cycle

per_cycle = {}
total = 0
collisions = 0
min_cyc = None
max_cyc = None

with open("shapes_rotation/events.txt") as f:
    for line in f:
        parts = line.split()
        if len(parts) != 4:
            continue
        t = float(parts[0])
        x = int(parts[1]); y = int(parts[2])
        if not (X0 <= x <= X1 and Y0 <= y <= Y1):
            continue
        row = y - Y0
        col = x - X0
        src = row * 4 + col
        cyc = int(t / BIN)
        bit = 1 << src
        total += 1
        prev = per_cycle.get(cyc, 0)
        if prev & bit:
            collisions += 1
        per_cycle[cyc] = prev | bit
        if min_cyc is None or cyc < min_cyc: min_cyc = cyc
        if max_cyc is None or cyc > max_cyc: max_cyc = cyc

with open("uzh_shapes_rotation_patch.cyclemask.txt", "w") as out:
    for cyc in sorted(per_cycle):
        out.write(f"{cyc} {per_cycle[cyc]:04x}\n")

print(f"patch=({X0}-{X1},{Y0}-{Y1}) bin={BIN}s total_events={total} "
      f"unique_active_cycles={len(per_cycle)} span_cycles={max_cyc-min_cyc if max_cyc else 0} "
      f"same_cycle_same_source_collisions={collisions}")
