#!/usr/bin/env python3
# §168: 현수의 칩 안 자세 추정기(job3, 4프레임 창마다 후보 N개로 월드 지도 겹침 비교)를 우리 데이터/정답에 적용.
# 현수 코드는 scripts/external/hyunsu_job3_estimator.py 그대로(무수정) 사용하고, 입력만 그의 형식으로 변환:
#   data/ev_<name>.npz (x, y, f=프레임 번호), data/roll_ecc.npy (k, t, n, ok, dth, tx, ty, cc) = 정답 궤적
# 정답: 실제 영상 = 우리 ECC 재현(delta_theta_ecc.py), 합성 = 진짜 theta(정답).
import importlib.util
import json
import os
import sys

import h5py
import numpy as np

WIN = 4


def build(h5_path, work, name, gt_kind, ecc_npy=None, truth_npz=None, min_ev=None):
    os.makedirs(work + "/data", exist_ok=True); os.makedirs(work + "/results", exist_ok=True)
    f = h5py.File(h5_path, "r")
    t = f["events/t"][:]; x = f["events/x"][:]; y = f["events/y"][:]
    fr = np.concatenate([[0], np.cumsum(np.diff(t) != 0)]).astype(np.int32)                  # 프레임 번호(같은 타임스탬프 묶음)
    first = np.concatenate([[0], np.flatnonzero(np.diff(t)) + 1]); t_frame = t[first].astype(np.int64)
    nf = len(first)
    np.savez(f"{work}/data/ev_{name}.npz", x=x, y=y, f=fr)
    starts = list(range(1, nf - WIN, WIN))
    ks = np.array(starts[1:]); n = np.array([(first[min(k + WIN, nf)] if min(k + WIN, nf) < nf else len(t)) - first[k] for k in ks])
    if gt_kind == "ecc":
        a = np.load(ecc_npy); ok = a[:, 2].astype(bool)[:len(ks)]; dth = a[:len(ks), 3]
        dth = np.where(ok, dth, 0.0); cc = a[:len(ks), 4]
    else:                                                                                    # 진짜 theta 정답
        th = np.degrees(np.load(truth_npz)["theta"]); mids = np.arange(len(th)) * 4 + 2.0
        tk = t_frame[ks] / 1e3; tprev = t_frame[np.concatenate([[starts[0]], ks[:-1]])] / 1e3
        dth = np.interp(tk, mids, th) - np.interp(tprev, mids, th); ok = n >= (min_ev or 4500); cc = np.ones(len(ks))
    arr = np.stack([ks.astype(float), t_frame[ks].astype(float), n.astype(float), ok.astype(float), dth, np.zeros(len(ks)), np.zeros(len(ks)), cc], 1)
    np.save(f"{work}/data/roll_ecc.npy", arr)
    return ks, t_frame


def run(work, name, cfg, center=None):
    cwd = os.getcwd(); os.chdir(work)
    try:
        spec = importlib.util.spec_from_file_location("job3_estimator", os.path.join(cwd, "scripts/external/hyunsu_job3_estimator.py"))
        mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
        if center is not None:
            mod.C = np.array(center, dtype=float)                       # 현수 코드의 고정 회전 중심(480,352)을 덮어써 시험
        x, y, f = mod.load(name)
        r, est, qgt, _, k0 = mod.run(name, x, y, f, **cfg)
    finally:
        os.chdir(cwd)
    return r, est, qgt, k0


if __name__ == "__main__":
    # usage: run_hyunsu_estimator.py <real|syn> <events.h5> <workdir> <ecc.npy|truth.npz> [min_ev]
    kind, h5p, work, gtp = sys.argv[1:5]
    min_ev = int(sys.argv[5]) if len(sys.argv) > 5 else 15000
    ks, t_frame = build(h5p, work, "roll", "ecc" if kind == "real" else "truth", gtp if kind == "real" else None, gtp if kind == "syn" else None, min_ev)
    cfg = dict(N=9, S=3, M=2048, refine=True, R=1, fwarp=True, sbits=4, min_ev=min_ev)          # 현수 job3_final 기본 설정
    r, est, qgt, k0 = run(work, "roll", cfg)
    t_ms = t_frame[np.minimum(k0, len(t_frame) - 1)] / 1e3
    np.save(work + "/results/est.npy", np.stack([t_ms, est, qgt]))
    print(json.dumps({k: (round(v, 3) if isinstance(v, float) else v) for k, v in r.items() if k in ("mean_abs", "max_abs", "final", "rms", "sparse_mean", "reads_per_ev", "world_bits")}))
