#!/usr/bin/env python3
# tb_steal_buf_event_logger.v의 원시 출력(DELIVERED/OVERRUN 텍스트 라인, event_id로 식별)
# 과 build_uzh_eventmeta.py가 만든 eventmeta.tsv(x/y/polarity/occurrence_timestamp_ns)를
# event_id로 join해서 준영 쪽 CAV 평가용 JSONL + manifest를 만듦. CAV는 이 스크립트/TB
# 안에서 절대 안 부름(AER transport evidence까지만 만들고 평가는 분리).
import json
import subprocess
import sys
import hashlib

EVENTLOG = "common_traces_uzh/event_logger_out/uzh_shapes_rotation_patch.eventlog.txt"
EVENTMETA = "common_traces_uzh/uzh_shapes_rotation_patch.eventmeta.tsv"
OUT_JSONL = "common_traces_uzh/event_logger_out/uzh_shapes_rotation_patch.aer_transport.jsonl"
OUT_MANIFEST = "common_traces_uzh/event_logger_out/uzh_shapes_rotation_patch.manifest.json"
RTL_FILE = "rtl/aer_tx16_trad_rowcol_fovea_cluster2_steal_buf.v"
TB_FILE = "tb/tb_steal_buf_event_logger.v"
TRACE_FILE = "common_traces_uzh/uzh_shapes_rotation_patch.cyclemask.txt"

meta = {}
with open(EVENTMETA) as f:
    header = f.readline()
    for line in f:
        eid, cyc, src, x, y, pol, ts_ns = line.rstrip("\n").split("\t")
        meta[int(eid)] = {
            "logical_source": int(src),
            "x4": int(x), "y4": int(y),
            "polarity": int(pol),
            "occurrence_cycle": int(cyc),
            "occurrence_timestamp_ns": int(ts_ns),
        }

records = {}
delivered_count = 0
overrun_count = 0
seen_ids = set()
dup_count = 0
order_violations = 0
last_id_per_source = {}  # retire-order 기준(파일에 쓰인 순서 = 실제 delivery 순서)

with open(EVENTLOG) as f:
    for line in f:
        parts = line.split()
        kind = parts[0]
        fields = dict(p.split("=") for p in parts[1:])
        eid = int(fields["event_id"])
        if eid in seen_ids:
            dup_count += 1
        seen_ids.add(eid)
        if eid not in meta:
            raise SystemExit(f"event_id {eid} in TB output but not in eventmeta.tsv -- id 정렬이 깨짐")
        rec = dict(meta[eid])
        rec["event_id"] = eid
        if kind == "DELIVERED":
            rec["status"] = "delivered"
            rec["retire_cycle"] = int(fields["retire_cycle"])
            rec["retire_lane"] = int(fields["retire_lane"])
            rec["latency_cycles"] = int(fields["latency_cycles"])
            delivered_count += 1
            src = rec["logical_source"]
            if src in last_id_per_source and eid <= last_id_per_source[src]:
                order_violations += 1
            last_id_per_source[src] = eid
        elif kind == "OVERRUN":
            rec["status"] = "overrun"
            rec["retire_cycle"] = None
            rec["retire_lane"] = None
            rec["latency_cycles"] = None
            overrun_count += 1
        else:
            raise SystemExit(f"unknown line kind: {kind}")
        records[eid] = rec

generated = len(meta)
missing_ids = set(meta.keys()) - seen_ids

with open(OUT_JSONL, "w") as out:
    for eid in sorted(records):
        out.write(json.dumps(records[eid]) + "\n")

def sha1_of(path):
    h = hashlib.sha1()
    with open(path, "rb") as f:
        h.update(f.read())
    return h.hexdigest()

def git_commit():
    try:
        return subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    except Exception:
        return None

def iverilog_version():
    try:
        out = subprocess.check_output(["iverilog", "-V"], text=True, stderr=subprocess.STDOUT)
        return out.splitlines()[0].strip()
    except Exception:
        return None

manifest = {
    "source_trace": "uzh_shapes_rotation_patch.cyclemask.txt",
    "patch": {"x": [110, 113], "y": [85, 88], "bin_seconds": 0.001},
    "dut": "aer_tx16_trad_rowcol_fovea_cluster2_steal_buf.v (unmodified)",
    "harness": "tb_steal_buf_event_logger.v (extends tb_steal_buf_trace_phantom_debug.v)",
    "generated": generated,
    "delivered": delivered_count,
    "overrun": overrun_count,
    "loss_rate": overrun_count / generated if generated else None,
    "checks": {
        "generated_eq_delivered_plus_overrun": generated == delivered_count + overrun_count,
        "every_id_present_exactly_once": (len(missing_ids) == 0 and dup_count == 0),
        "duplicate_count": dup_count,
        "missing_id_count": len(missing_ids),
        "per_source_retire_order_preserved": order_violations == 0,
        "order_violations": order_violations,
    },
    "sha1": {
        "rtl_dut": sha1_of(RTL_FILE),
        "tb_harness": sha1_of(TB_FILE),
        "trace_file": sha1_of(TRACE_FILE),
        "eventmeta_tsv": sha1_of(EVENTMETA),
        "eventlog_txt": sha1_of(EVENTLOG),
        "jsonl_out": sha1_of(OUT_JSONL),
    },
    "repro": {
        "git_commit": git_commit(),
        "simulator": iverilog_version(),
        "compile_cmd": f"iverilog -g2012 -o event_logger.vvp rtl/*.v {TB_FILE}",
        "run_cmd": f"vvp event_logger.vvp +TRACE_FILE={TRACE_FILE} +OUT_FILE={EVENTLOG}",
        "join_cmd": "python3 scripts/join_event_logger_output.py",
    },
}

with open(OUT_MANIFEST, "w") as out:
    json.dump(manifest, out, indent=2)

print(json.dumps(manifest, indent=2))
if (not manifest["checks"]["generated_eq_delivered_plus_overrun"]
        or not manifest["checks"]["every_id_present_exactly_once"]
        or not manifest["checks"]["per_source_retire_order_preserved"]):
    print("JOIN_CHECK_FAIL", file=sys.stderr)
    sys.exit(1)
print("JOIN_CHECK_PASS")
