#!/usr/bin/env python3
# 준영 공용 trace(jsonl)를 "cycle source" 2열 텍스트로 변환 -- Verilog $fscanf로 읽기 쉽게.
# 이 스크립트/입력 jsonl은 전부 우리 repo(common_traces_steal_buf/) 안에서만 동작함.
import json
import sys

for path in sys.argv[1:]:
    out_path = path.replace(".events.jsonl", ".cyclesrc.txt")
    with open(path) as f, open(out_path, "w") as out:
        for line in f:
            ev = json.loads(line)
            out.write(f"{ev['occurrence_cycle']} {ev['logical_source']}\n")
    print(f"wrote {out_path}")
