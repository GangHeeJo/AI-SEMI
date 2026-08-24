#!/usr/bin/env python3
# §98 최종 확정(극성 포함) 버전: tb_steal_buf_polarity_event_logger.v(DUT=극성판 steal_buf,
# 실제 하드웨어가 pol_mask로 내보낸 극성)의 원시 로그를 eventmeta.tsv(ground truth)와
# event_id로 join. join_event_logger_output.py와 다른 점 -- hw_polarity(실제 하드웨어
# 출력)를 ground-truth polarity와 대조해서 "주소뿐 아니라 극성도 DUT가 실제로 정확히
# 실어 날랐다"를 증명하는 checks.polarity_roundtrip_ok를 추가로 냄.
import json
import subprocess
import sys
import hashlib

EVENTLOG = "common_traces_uzh/event_logger_out/uzh_shapes_rotation_patch.polarity_eventlog.txt"
EVENTMETA = "common_traces_uzh/uzh_shapes_rotation_patch.eventmeta.tsv"
OUT_JSONL = "common_traces_uzh/event_logger_out/uzh_shapes_rotation_patch.aer_transport_polarity.jsonl"
OUT_MANIFEST = "common_traces_uzh/event_logger_out/uzh_shapes_rotation_patch.polarity_manifest.json"
RTL_FILE = "rtl/aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity.v"
TB_FILE = "tb/tb_steal_buf_polarity_event_logger.v"
TRACE_FILE = "common_traces_uzh/uzh_shapes_rotation_patch.addrpol.txt"

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
polarity_mismatches = 0
last_id_per_source = {}

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
            rec["hw_polarity"] = int(fields["hw_polarity"])
            rec["latency_cycles"] = int(fields["latency_cycles"])
            if rec["hw_polarity"] != rec["polarity"]:
                polarity_mismatches += 1
            delivered_count += 1
            src = rec["logical_source"]
            if src in last_id_per_source and eid <= last_id_per_source[src]:
                order_violations += 1
            last_id_per_source[src] = eid
        elif kind == "OVERRUN":
            rec["status"] = "overrun"
            rec["retire_cycle"] = None
            rec["retire_lane"] = None
            rec["hw_polarity"] = None
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
    "source_trace": "uzh_shapes_rotation_patch.addrpol.txt",
    "patch": {"x": [110, 113], "y": [85, 88], "bin_seconds": 0.001},
    "dut": "aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity.v (final submission candidate, includes real polarity -- NOT the unmodified baseline used in section 93/98's first pass)",
    "harness": "tb_steal_buf_polarity_event_logger.v",
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
        "polarity_roundtrip_ok": polarity_mismatches == 0,
        "polarity_mismatches": polarity_mismatches,
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
        "compile_cmd": f"iverilog -g2012 -o pol_event_logger.vvp rtl/*.v {TB_FILE}",
        "run_cmd": f"vvp pol_event_logger.vvp +TRACE_FILE={TRACE_FILE} +OUT_FILE={EVENTLOG}",
        "join_cmd": "python3 scripts/join_polarity_event_logger_output.py",
    },
}

with open(OUT_MANIFEST, "w") as out:
    json.dump(manifest, out, indent=2)

print(json.dumps(manifest, indent=2))
if (not manifest["checks"]["generated_eq_delivered_plus_overrun"]
        or not manifest["checks"]["every_id_present_exactly_once"]
        or not manifest["checks"]["per_source_retire_order_preserved"]
        or not manifest["checks"]["polarity_roundtrip_ok"]):
    print("JOIN_CHECK_FAIL", file=sys.stderr)
    sys.exit(1)
print("JOIN_CHECK_PASS")
