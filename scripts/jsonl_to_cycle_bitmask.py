#!/usr/bin/env python3
# 준영 공용 trace(jsonl)를 "cycle bitmask" 텍스트로 변환 -- 사이클당 16비트 도착 비트맵
# (arrival[15:0] 포트가 소스당 1비트/사이클이라 같은 사이클 내 같은 소스 중복은 물리적으로
# 구분 불가 -- 병합되면 collisions로 별도 집계해서 알려줌).
import json
import sys
from collections import defaultdict

for path in sys.argv[1:]:
    out_path = path.replace(".events.jsonl", ".cyclemask.txt")
    per_cycle = defaultdict(int)
    collisions = 0
    total_events = 0
    with open(path) as f:
        for line in f:
            ev = json.loads(line)
            total_events += 1
            cyc = ev["occurrence_cycle"]
            src = ev["logical_source"]
            bit = 1 << src
            if per_cycle[cyc] & bit:
                collisions += 1
            per_cycle[cyc] |= bit
    with open(out_path, "w") as out:
        for cyc in sorted(per_cycle):
            out.write(f"{cyc} {per_cycle[cyc]:04x}\n")
    print(f"wrote {out_path} total_events={total_events} collisions={collisions}")
