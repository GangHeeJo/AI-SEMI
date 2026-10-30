#!/usr/bin/env python3
# 현수 자기보정(job26 EstU)의 합성 정답 독립 검증 -- 기준: syn/reports/hyunsu_selfcal/criteria.md (실행 전 커밋 210fda6).
# 센서가 피벗 Q 주위로 회전(p = Q + R(-th)(w - Q), u_true = c - Q)하는 단일 깊이 합성 장면을 만들어 현수 추정기에 넣고,
# (S) 자기보정 / (R) 참 피벗 재맞춤 / (F) 칩 roll 피벗 프리즈의 각도 오차와 복원 피벗을 비교한다.
# 사용: python hyunsu_selfcal_synth.py [--only G1] [--seeds 0,1,2] [--out result.json] [--procs 4]
import json
import math
import sys
import time
from multiprocessing import Pool

sys.path.insert(0, "scripts/external/hyunsu_job26")
import numpy as np

import job18_est as E
import job26_est as U

W, H = 960, 720
C = (W / 2.0, H / 2.0)
NF, PER = 700, 6000
TH_MAX = math.radians(120.0)
GEOMS = {"G0": (0, 0), "G1": (50, 0), "G2": (0, -60), "G3": (-45, 35), "G4": (120, -90)}
FROZEN_U = (0.0, 8.0)                        # 현수 칩 roll 피벗 (480,352) -> u = c - Q


def theta(tau):
    u = np.clip(np.asarray(tau, float) / NF, 0, 1)
    return TH_MAX * 0.5 * (1 - np.cos(np.pi * u))


def rot(x, y, a):
    c, s = np.cos(a), np.sin(a)
    return c * x - s * y, s * x + c * y


def make_scene(seed):
    r = np.random.default_rng(5000 + seed)
    segs = []
    while len(segs) < 60:
        cx, cy = r.uniform(-1000, 1000) + C[0], r.uniform(-800, 800) + C[1]
        a, L = r.uniform(0, np.pi), r.uniform(40, 260)
        segs.append((cx - L / 2 * np.cos(a), cy - L / 2 * np.sin(a), cx + L / 2 * np.cos(a), cy + L / 2 * np.sin(a)))
    dots = np.c_[r.uniform(-1000, 1000, 80) + C[0], r.uniform(-800, 800, 80) + C[1]]
    return np.array(segs), dots


def gen_events(scene, Q, seed):
    rng = np.random.default_rng(seed)
    S, D = scene; nseg = len(S)
    L = np.hypot(S[:, 2] - S[:, 0], S[:, 3] - S[:, 1]); w_el = np.concatenate([L, np.full(len(D), 12.0)]); w_el /= w_el.sum()
    X, Y, F = [], [], []
    for fr in range(NF):
        got, xs, ys = 0, [], []
        while got < PER:
            m = max(12 * (PER - got), 20000)
            el = rng.choice(len(w_el), m, p=w_el); seg = el < nseg
            sg = S[np.minimum(el, nseg - 1)]; u = rng.random(m)
            wx = np.where(seg, sg[:, 0] + u * (sg[:, 2] - sg[:, 0]), D[np.maximum(el - nseg, 0), 0])
            wy = np.where(seg, sg[:, 1] + u * (sg[:, 3] - sg[:, 1]), D[np.maximum(el - nseg, 0), 1])
            dx, dy = sg[:, 2] - sg[:, 0], sg[:, 3] - sg[:, 1]; Ln = np.maximum(np.hypot(dx, dy), 1e-9)
            nx, ny = -dy / Ln, dx / Ln
            tau = fr + rng.random(m); th = theta(tau)
            rx, ry = rot(wx - Q[0], wy - Q[1], -th); px, py = Q[0] + rx, Q[1] + ry
            th2 = theta(tau + 0.25); rx2, ry2 = rot(wx - Q[0], wy - Q[1], -th2)
            vx, vy = (Q[0] + rx2 - px) * 4, (Q[1] + ry2 - py) * 4                      # px/프레임
            nxp, nyp = rot(nx, ny, -th)
            acc = np.where(seg, np.minimum(np.abs(vx * nxp + vy * nyp) / 3.0, 1.0), 0.5)
            px = px + rng.normal(0, 0.6, m); py = py + rng.normal(0, 0.6, m)
            ok = (rng.random(m) < acc) & (px >= 0) & (px < W) & (py >= 0) & (py < H)
            xs.append(px[ok]); ys.append(py[ok]); got += int(ok.sum())
        px = np.concatenate(xs)[:PER]; py = np.concatenate(ys)[:PER]
        nb = int(0.03 * PER); px[:nb] = rng.uniform(0, W, nb); py[:nb] = rng.uniform(0, H, nb)
        X.append(np.floor(px).astype(np.int32)); Y.append(np.floor(py).astype(np.int32)); F.append(np.full(PER, fr, np.int32))
    return np.concatenate(X), np.concatenate(Y), np.concatenate(F)


def run_est(x, y, f, rot1=None):
    est = U.EstU(W, H, C, rot1=list(rot1) if rot1 is not None else None)
    rec = E.run(est, x, y, f, 0, NF)
    return est, rec


def err_deg(rec, sign):
    fc = rec[:, 0]; th_est = rec[:, 9]                                       # 적용 자세의 각도(창 중심)
    tr = theta(fc + 0.5)
    e = sign * (th_est - th_est[0]) - (tr - tr[0])
    return float(np.degrees(np.mean(np.abs(e)))), float(np.degrees(np.max(np.abs(e)))), float(np.degrees(np.corrcoef(th_est, tr)[0, 1]))


def one(job):
    g, seed, sign = job
    u_true = GEOMS[g]; Q = (C[0] - u_true[0], C[1] - u_true[1])
    t0 = time.time(); x, y, f = gen_events(make_scene(seed), Q, 100 + seed)
    out = dict(geom=g, seed=seed, u_true=u_true, events=int(len(x)))
    for name, preset in (("S", None), ("R", u_true), ("F", FROZEN_U)):
        est, rec = run_est(x, y, f, rot1=preset)
        mean_e, max_e, corr = err_deg(rec, sign)
        d = dict(mean=mean_e, max=max_e, corr=corr, mode=est.mode)
        if name == "S" and est.calib:
            d["calib"] = est.calib; d["u_est"] = est.calib.get("u"); d["r2"] = est.calib.get("r2")
        out[name] = d
    out["sec"] = round(time.time() - t0, 1)
    print(json.dumps(out, default=float), flush=True)
    return out


def main():
    a = sys.argv[1:]
    only = a[a.index("--only") + 1].split(",") if "--only" in a else list(GEOMS)
    seeds = [int(s) for s in a[a.index("--seeds") + 1].split(",")] if "--seeds" in a else [0, 1, 2]
    procs = int(a[a.index("--procs") + 1]) if "--procs" in a else 4
    # 부호 규약: G0/시드0에서 (R) 재맞춤의 상관 부호로 한 번 정해 모든 시험에 동일 적용
    u0 = GEOMS["G0"]; x, y, f = gen_events(make_scene(0), (C[0], C[1]), 100)
    est, rec = run_est(x, y, f, rot1=u0)
    sign = 1.0 if np.corrcoef(rec[:, 9], theta(rec[:, 0] + 0.5))[0, 1] >= 0 else -1.0
    print("sign convention:", sign, flush=True)
    jobs = [(g, s, sign) for g in only for s in seeds]
    with Pool(procs) as p: res = p.map(one, jobs)
    summ = []
    ok = dict(P1=[], P4=0, n=0)
    for g in only:
        rs = [r for r in res if r["geom"] == g]
        ut = np.array(GEOMS[g], float)
        e_S = float(np.median([r["S"]["mean"] for r in rs])); e_R = float(np.median([r["R"]["mean"] for r in rs])); e_F = float(np.median([r["F"]["mean"] for r in rs]))
        du = [float(np.hypot(*(np.array(r["S"]["u_est"]) - ut))) if r["S"].get("u_est") else float("nan") for r in rs]
        rot1 = sum(r["S"]["mode"] == "rot1" for r in rs)
        summ.append(f"{g} u_true={tuple(ut)} 평균 각도오차(중앙값, deg): 자기보정 S={e_S:.2f} 재맞춤 R={e_R:.2f} 프리즈 F={e_F:.2f} | 피벗 복원 오차(px, 시드별) {['%.1f' % d for d in du]} | rot1 선택 {rot1}/{len(rs)}")
    txt = "\n".join(summ); print(txt)
    p2 = all(float(np.median([r["S"]["mean"] for r in res if r["geom"] == g])) <= max(1.0, 1.5 * float(np.median([r["R"]["mean"] for r in res if r["geom"] == g]))) for g in only)
    p3n = sum(float(np.median([r["F"]["mean"] for r in res if r["geom"] == g])) >= 3 * float(np.median([r["S"]["mean"] for r in res if r["geom"] == g])) for g in only if g in ("G1", "G2", "G3", "G4"))
    p4 = sum(r["S"]["mode"] == "rot1" for r in res); p1ok = True
    for g in only:
        if g == "G0": continue
        ut = np.array(GEOMS[g], float); tol = max(10.0, 0.2 * np.hypot(*ut))
        n_ok = sum((r["S"].get("u_est") is not None) and np.hypot(*(np.array(r["S"]["u_est"]) - ut)) <= tol for r in res if r["geom"] == g)
        p1ok = p1ok and n_ok >= 2
    verdict = f"P1 {'PASS' if p1ok else 'FAIL'} | P2 {'PASS' if p2 else 'FAIL'} | P3 {'PASS' if p3n >= 2 else 'FAIL'}({p3n}/4 기하) | P4 {'PASS' if p4 >= 12 else 'FAIL'}({p4}/{len(res)})"
    print(verdict)
    if "--out" in a:
        open(a[a.index("--out") + 1], "w", encoding="utf-8").write(json.dumps(res, default=float, indent=1))
        open(a[a.index("--out") + 1].replace(".json", ".txt"), "w", encoding="utf-8").write(f"sign={sign}\n{txt}\n{verdict}\n")


if __name__ == "__main__":
    main()
