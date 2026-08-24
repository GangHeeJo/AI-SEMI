#!/usr/bin/env python3
# uzh_shapes_rotation_patch.cyclemask.txt(convert_uzh_to_cyclemask.py 산출물)와 짝을 이루는
# per-event 메타데이터 테이블 생성. event_id는 TB가 cyclemask.txt를 읽을 때 도는 순서
# (cycle 오름차순 -> source 오름차순)와 정확히 동일한 규칙으로 매겨서, 두 산출물 사이에
# ID를 파일로 주고받을 필요 없이 자동으로 정렬되게 함(이 패치/bin 설정은 collision=0이
# 이미 확인됐으므로 (cycle,source) 쌍마다 이벤트가 정확히 하나임).
X0, X1 = 110, 113
Y0, Y1 = 85, 88
BIN = 0.001  # 1ms/cycle

events = []  # (cyc, src, x, y, polarity, ts_ns)
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
        polarity = int(parts[3])
        ts_ns = round(t * 1e9)
        events.append((cyc, src, x, y, polarity, ts_ns))

events.sort(key=lambda e: (e[0], e[1]))  # TB 루프 순서(cycle asc, source asc)와 동일

seen = set()
for cyc, src, x, y, polarity, ts_ns in events:
    key = (cyc, src)
    if key in seen:
        raise SystemExit(f"COLLISION at cycle={cyc} source={src} -- eventmeta 가정(패치당 1이벤트) 깨짐")
    seen.add(key)

with open("uzh_shapes_rotation_patch.eventmeta.tsv", "w") as out:
    out.write("event_id\tcycle\tsource\tx\ty\tpolarity\toccurrence_timestamp_ns\n")
    for eid, (cyc, src, x, y, polarity, ts_ns) in enumerate(events):
        out.write(f"{eid}\t{cyc}\t{src}\t{x}\t{y}\t{polarity}\t{ts_ns}\n")

print(f"events={len(events)} written to uzh_shapes_rotation_patch.eventmeta.tsv")
