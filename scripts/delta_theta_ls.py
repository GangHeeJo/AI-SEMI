#!/usr/bin/env python3
# §163: θ(t)를 추정기 여러 개에서 "합리적으로" 결합 -- 평균/중앙값이 아니라 측정 모델 + 로버스트 가중 최소제곱(칼만 평활기와
# 같은 원리의 배치 해). 각 추정기가 무엇을 재는지와 어떤 오차를 갖는지를 식으로 쓰고, 잡음 크기는 잔차에서 반복 추정한다.
#
# 상태: 노드 θ_j (ECC 창 시점) + 천천히 변하는 증분 배율 a(t)(노드 간격 250ms 선형보간) + 선 방향 절대각 오프셋 u
# 측정:
#  E1 ECC 증분    θ_{r+1}-θ_r = a(t_r) * dθ^ECC_r   (시차로 생기는 배율 편향을 a가 흡수, 병진 불변이라 편향이 작음)
#  E2 CMax 증분   θ_{r+1}-θ_r = ∫ω_cmax dt          (깊이로 배율이 +-20% 편향 -> 가장 약한 정보, 불확실성 비례 모델)
#  E3 선 방향     θ(t_i)+u = ψ_i + 90° m_i          (절대각, 병진 불변이지만 원근선이 섞이는 프레임에서 편향) -> 신뢰/비신뢰 두 부류의
#                                                     분산을 따로 추정, Cauchy 로버스트 손실
#  E4 평활 사전   θ_{j+1}-2θ_j+θ_{j-1} = 0           (관성: 각가속도가 작다)
#  E5 배율 사전   a_j = 1, a_{j+1}-a_j = 0
#  E6 시작 고정   θ_0 = 0
# 잡음 크기: 그룹별 잔차의 MAD로 반복 갱신(분산 성분 추정). 90° 감김은 ECC 적분으로 푼다(오차 << 45°).
import sys

import numpy as np

KNOT_MS = 250.0
RELIABLE = dict(lines=10, coh=0.85)
UNREL = dict(lines=5, coh=0.0)
C_CAUCHY = 2.385


def hat_matrix(tq, knots):
    H = np.zeros((len(tq), len(knots)))
    for i, t in enumerate(tq):
        j = np.searchsorted(knots, t) - 1
        j = int(np.clip(j, 0, len(knots) - 2))
        w = np.clip((t - knots[j]) / (knots[j + 1] - knots[j]), 0, 1)
        H[i, j], H[i, j + 1] = 1 - w, w
    return H


def fuse(ecc_npy, psi_npy, omega_npy, verbose=True, knot_ms=KNOT_MS, fixed_gain=False, drop=()):
    drop = set(drop)
    ecc = np.load(ecc_npy); r = np.load(psi_npy); om = np.load(omega_npy)
    t = ecc[:, 0]; ok = ecc[:, 2].astype(bool); y = np.radians(np.where(ok, ecc[:, 3], 0.0))
    R = len(t); dt = float(np.median(np.diff(t)))
    tn = np.concatenate([[t[0] - dt], t])                 # 노드 시각(ms): 노드 r+1 = ECC 행 r의 창
    N = len(tn)
    knots = np.arange(tn[0], tn[-1] + knot_ms, knot_ms); J = len(knots)
    if J < 2:
        knots = np.array([tn[0], tn[-1]]); J = 2
    Hr = hat_matrix(t, knots)                              # 증분 r이 쓰는 배율 보간 가중치
    # CMax 증분
    cw = (np.arange(len(om)) * 4.0 + 2.0)                  # 4ms 창 중앙(ms)
    cum = np.cumsum(om[:, 1] * 0.004)
    cmax_inc = np.interp(tn[1:], cw, cum, left=0) - np.interp(tn[:-1], cw, cum, left=0)
    # 선 방향 프레임: 90도 감김을 ECC 적분(a=1)으로 해결
    tf = r[:, 0] + 10.0; lines = r[:, 2]; psi = np.radians(r[:, 3]); coh = r[:, 4]
    th_e = np.concatenate([[0], np.cumsum(y)])
    use = np.isfinite(psi) & (lines >= UNREL["lines"]) & (tf >= tn[0]) & (tf <= tn[-1])
    rel = use & (lines >= RELIABLE["lines"]) & (coh >= RELIABLE["coh"])
    fi = np.flatnonzero(use)
    th_at = np.interp(tf[fi], tn, th_e)
    ref = fi[rel[fi]][:5]
    u0 = np.angle(np.mean(np.exp(4j * (psi[ref] - np.interp(tf[ref], tn, th_e))))) / 4      # 4중대칭 평균으로 오프셋 초기화
    per = np.pi / 2
    m = np.round((th_at + u0 - psi[fi]) / per)
    psi_un = psi[fi] + per * m
    fi_rel = rel[fi]
    # 앵커의 노드 보간 가중치
    A_th = np.zeros((len(fi), N))
    for k, i in enumerate(fi):
        j = int(np.clip(np.searchsorted(tn, tf[i]) - 1, 0, N - 2)); w = np.clip((tf[i] - tn[j]) / (tn[j + 1] - tn[j]), 0, 1)
        A_th[k, j], A_th[k, j + 1] = 1 - w, w
    nU = N + J + 1                                         # 미지수: θ_0..θ_{N-1}, a_0..a_{J-1}, u
    rows = []; groups = []                                 # (행벡터, 우변, 그룹명)
    def row(vec, rhs, g):
        rows.append((vec, rhs, g))
    for k in range(R):
        if ok[k]:
            v = np.zeros(nU); v[k + 1] = 1; v[k] = -1; v[N:N + J] = -Hr[k] * y[k]; row(v, 0.0, "ecc")
        v = np.zeros(nU); v[k + 1] = 1; v[k] = -1; row(v, cmax_inc[k], "cmax")
    for k in range(len(fi)):
        if k in drop:
            continue                                  # 교차 검증: 빠진 앵커는 적합에 쓰지 않음
        v = np.zeros(nU); v[:N] = A_th[k]; v[-1] = 1; row(v, psi_un[k], "ori_rel" if fi_rel[k] else "ori_unrel")
    for j in range(1, N - 1):
        v = np.zeros(nU); v[j - 1], v[j], v[j + 1] = 1, -2, 1; row(v, 0.0, "smooth")
    for j in range(J):
        v = np.zeros(nU); v[N + j] = 1; row(v, 1.0, "gain_prior")
        if j + 1 < J:
            v = np.zeros(nU); v[N + j], v[N + j + 1] = -1, 1; row(v, 0.0, "gain_smooth")
    v = np.zeros(nU); v[0] = 1; row(v, 0.0, "start")
    Amat = np.array([x[0] for x in rows]); bvec = np.array([x[1] for x in rows]); grp = np.array([x[2] for x in rows])
    names = ["ecc", "cmax", "ori_rel", "ori_unrel", "smooth", "gain_prior", "gain_smooth", "start"]
    sig = dict(ecc=np.radians(0.15), cmax=np.radians(0.5), ori_rel=np.radians(3.0), ori_unrel=np.radians(10.0),
               smooth=np.radians(0.3), gain_prior=1e-3 if fixed_gain else 0.1, gain_smooth=1e-3 if fixed_gain else 0.05, start=1e-4)
    scale_cmax = 0.25 * np.abs(cmax_inc)                   # CMax 불확실성은 증분 크기에 비례(배율 편향)
    cmax_idx = np.flatnonzero(grp == "cmax")
    sol = np.zeros(nU)
    for it in range(12):
        s = np.array([sig[g] for g in grp])
        s[cmax_idx] = np.sqrt(sig["cmax"] ** 2 + (scale_cmax[:len(cmax_idx)] * 1.0) ** 2) if len(cmax_idx) == len(scale_cmax) else s[cmax_idx]
        res = Amat @ sol - bvec if it else np.zeros(len(bvec))
        wr = np.ones(len(bvec))
        if it:
            for g in ("ecc", "cmax", "ori_rel", "ori_unrel"):
                idx = grp == g; z = res[idx] / s[idx]; wr[idx] = 1.0 / (1.0 + (z / C_CAUCHY) ** 2)     # Cauchy 로버스트 가중
        W = np.sqrt(wr) / s
        sol, *_ = np.linalg.lstsq(Amat * W[:, None], bvec * W, rcond=None)
        res = Amat @ sol - bvec
        for g in ("ecc", "cmax", "ori_rel", "ori_unrel", "smooth"):               # 분산 성분 갱신(MAD)
            idx = grp == g
            if idx.sum() > 8:
                sg = 1.4826 * np.median(np.abs(res[idx] - np.median(res[idx])))
                sig[g] = float(np.clip(sg, np.radians(0.02), np.radians(30)))
    theta = sol[:N]; a = sol[N:N + J]; u = sol[-1]
    info = dict(sigma_deg={g: float(np.degrees(sig[g])) for g in ("ecc", "cmax", "ori_rel", "ori_unrel", "smooth")},
                gains=a.tolist(), u_deg=float(np.degrees(u)), tn=tn, n_anchor_rel=int(fi_rel.sum()), n_anchor=int(len(fi)),
                downweighted_anchor=float(np.mean(wr[np.isin(grp, ["ori_rel", "ori_unrel"])] < 0.5)))
    info["heldout"] = {int(k): float(psi_un[k] - (A_th[k] @ theta + u)) for k in drop}
    info["anchor_idx_t"] = tf[fi].tolist(); info["anchor_rel"] = fi_rel.tolist()
    if verbose:
        print("estimated noise (deg): " + ", ".join(f"{k} {v:.3f}" for k, v in info["sigma_deg"].items()))
        print("gain a(t) at knots:", np.round(a, 3).tolist(), "| anchors used %d (reliable %d), downweighted fraction %.2f" % (info["n_anchor"], info["n_anchor_rel"], info["downweighted_anchor"]))
    return theta, tn, info


def to_mids(theta, tn, n_win, win_ms=4):
    mids = np.arange(n_win) * win_ms + win_ms / 2.0
    return np.interp(mids, tn, theta)


if __name__ == "__main__":
    # usage: delta_theta_ls.py <ecc.npy> <psi_raw.npy> <omega_cmax.npy> <out_theta.npy> [n_win]
    th, tn, info = fuse(sys.argv[1], sys.argv[2], sys.argv[3])
    n_win = int(sys.argv[5]) if len(sys.argv) > 5 else 398
    np.save(sys.argv[4], to_mids(th, tn, n_win))
    print("final theta %.1f deg" % np.degrees(th[-1]))


def select_model(ecc_npy, psi_npy, omega_npy, n_blocks=6):
    """배율 유연도(노드 간격)를 앵커 블록 교차 검증으로 선택. 후보: 배율 고정(a=1), 전역 상수, 1000/500/250ms 노드."""
    th, tn, info = fuse(ecc_npy, psi_npy, omega_npy, verbose=False)
    ta = np.array(info["anchor_idx_t"]); rel = np.array(info["anchor_rel"])
    order = np.argsort(ta); blocks = np.array_split(order, n_blocks)
    cands = [("a=1 fixed", dict(fixed_gain=True)), ("a const", dict(knot_ms=1e9)), ("knots 1000ms", dict(knot_ms=1000.0)),
             ("knots 500ms", dict(knot_ms=500.0)), ("knots 250ms", dict(knot_ms=250.0))]
    out = {}
    for name, kw in cands:
        errs = []
        for b in blocks:
            bb = [int(i) for i in b if rel[i]]                  # 신뢰 앵커만 검증 대상
            if len(bb) < 3:
                continue
            _, _, inf = fuse(ecc_npy, psi_npy, omega_npy, verbose=False, drop=bb, **kw)
            errs += list(inf["heldout"].values())
        e = np.degrees(np.array(errs))
        out[name] = (float(1.4826 * np.median(np.abs(e - np.median(e)))), float(np.sqrt(np.mean(e ** 2))), float(np.median(e)), len(e))
    return out, cands
