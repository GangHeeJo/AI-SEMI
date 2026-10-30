#!/usr/bin/env python3
# 먼 피벗(pan 유사) 변형 -- 기준: syn/reports/hyunsu_selfcal/criteria_far.md (실행 전 커밋 cdedb32). 주 시험(hyunsu_selfcal_synth.py)의 함수를 재사용하고
# 기하별 회전각 범위와 장면 영역만 바꾼다.
# 사용: python hyunsu_selfcal_far.py [--procs 4] [--out result.json]
import json
import math
import sys
import time
from multiprocessing import Pool

sys.path.insert(0, "scripts")
import numpy as np

import hyunsu_selfcal_synth as S

FAR = {"V1": ((1500, -400), 20.0), "V2": ((6000, 0), 8.0), "V3": ((20000, -1000), 5.0)}


def make_scene_far(seed, span):
    """센서 이동량(span px)을 덮는 영역, 선분 수는 면적에 비례(기준 60개 / 2000x1600)."""
    r = np.random.default_rng(5000 + seed)
    hx, hy = 1000 + span, 800 + span
    n = int(60 * (2 * hx * 2 * hy) / (2000 * 1600)); n = min(n, 1500)
    segs = []
    while len(segs) < n:
        cx, cy = r.uniform(-hx, hx) + S.C[0], r.uniform(-hy, hy) + S.C[1]
        a, L = r.uniform(0, np.pi), r.uniform(40, 260)
        segs.append((cx - L / 2 * np.cos(a), cy - L / 2 * np.sin(a), cx + L / 2 * np.cos(a), cy + L / 2 * np.sin(a)))
    nd = min(int(80 * (2 * hx * 2 * hy) / (2000 * 1600)), 2000)
    dots = np.c_[r.uniform(-hx, hx, nd) + S.C[0], r.uniform(-hy, hy, nd) + S.C[1]]
    return np.array(segs), dots


def one(job):
    g, seed = job
    u_true, th_deg = FAR[g]
    S.TH_MAX = math.radians(th_deg)
    Q = (S.C[0] - u_true[0], S.C[1] - u_true[1])
    span = abs(math.radians(th_deg)) * math.hypot(*u_true)
    t0 = time.time(); x, y, f = S.gen_events(make_scene_far(seed, span), Q, 100 + seed)
    out = dict(geom=g, seed=seed, u_true=u_true, th_deg=th_deg, span=round(span), events=int(len(x)))
    for name, preset in (("S", None), ("R", u_true), ("F", S.FROZEN_U)):
        est, rec = S.run_est(x, y, f, rot1=preset)
        mean_e, max_e, corr = S.err_deg(rec, 1.0)
        d = dict(mean=mean_e, max=max_e, corr=corr, mode=est.mode)
        if name == "S" and est.calib:
            d["calib"] = est.calib; d["u_est"] = est.calib.get("u"); d["r2"] = est.calib.get("r2")
        out[name] = d
    out["sec"] = round(time.time() - t0, 1)
    print(json.dumps(out, default=float), flush=True)
    return out


def main():
    a = sys.argv[1:]
    procs = int(a[a.index("--procs") + 1]) if "--procs" in a else 4
    jobs = [(g, s) for g in FAR for s in (0, 1, 2)]
    with Pool(procs) as p: res = p.map(one, jobs)
    lines = []; q1 = {}; q2 = {}; q3 = 0
    for g in FAR:
        rs = [r for r in res if r["geom"] == g]; ut = np.array(FAR[g][0], float); R = float(np.hypot(*ut))
        e = {k: float(np.median([r[k]["mean"] for r in rs])) for k in "SRF"}
        ok = 0; det = []
        for r in rs:
            ue = r["S"].get("u_est")
            if ue is None: det.append("n/a"); continue
            ue = np.array(ue, float); Re = float(np.hypot(*ue)); ang = abs(math.degrees(math.atan2(ue[1], ue[0]) - math.atan2(ut[1], ut[0])))
            ang = min(ang, 360 - ang); good = r["S"]["mode"] == "rot1" and abs(Re - R) <= 0.3 * R and ang <= 10
            ok += bool(good); det.append(f"{r['S']['mode']} R_est={Re:.0f} 방향오차={ang:.1f}° r2={r['S'].get('r2', 0):.2f}")
        q1[g] = ok >= 2; q2[g] = e["S"] <= max(1.0, 3 * e["R"])
        base = e["S"] if all(r["S"]["mode"] == "rot1" for r in rs) else e["R"]
        q3 += e["F"] >= 3 * base
        lines.append(f"{g} u_true={tuple(ut)} R={R:.0f} 각도 {FAR[g][1]}° span={rs[0]['span']}px | 오차 중앙값 S={e['S']:.2f} R={e['R']:.2f} F={e['F']:.2f} | " + "; ".join(det))
    verdict = f"Q1 {'PASS' if all(q1.values()) else 'FAIL'} {q1} | Q2 {'PASS' if all(q2.values()) else 'FAIL'} {q2} | Q3 {'PASS' if q3 >= 2 else 'FAIL'}({q3}/3)"
    txt = "\n".join(lines) + "\n" + verdict; print(txt)
    if "--out" in a:
        open(a[a.index("--out") + 1], "w", encoding="utf-8").write(json.dumps(res, default=float, indent=1))
        open(a[a.index("--out") + 1].replace(".json", ".txt"), "w", encoding="utf-8").write(txt + "\n")


if __name__ == "__main__":
    main()
