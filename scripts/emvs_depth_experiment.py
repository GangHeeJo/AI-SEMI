#!/usr/bin/env python3
# §201: 깊이 정답이 있는 시뮬레이션 시퀀스(UZH simulation_3planes/3walls)로 이벤트 깊이 추정 방식을 비교.
# EMVS(Rebecq 2018)와 같은 틀: 기준 시점의 깊이 평면 Z_i들에 이벤트 광선을 투영해 시차 공간 영상(DSI, 평면별 이벤트 수)을 만들고 평면별 최댓값으로 깊이를 구함.
#   A  EMVS 기본: 모든 이벤트로 만든 DSI의 argmax
#   B  우리 방식: 시간 G=3 구간. 이벤트는 자기 구간을 제외한 두 구간의 DSI(평활)로 평면을 각각 고르고(자기 이벤트 불참), 두 선택이 +-1평면 안에서 일치하면 채택. 채택 이벤트만으로 DSI 재구성
#   C  B + 극성: 이벤트가 같은 극성 DSI에서 증거를 얻음
# 깊이 범위는 넓은 사전값(역깊이 균등 간격, 정답을 보고 정한 것이 아님). 자세 규약(c2w/w2c, 이동 축 부호)은 정답 깊이를 쓰지 않고 DSI 초점(평면별 최댓값 합)이 큰 쪽을 자동 선택.
# 평가: 기준 시각에 가장 가까운 정답 깊이 맵과 추정 깊이의 절대 상대오차, 5% 이내 비율, 신뢰도 상위 K 픽셀 정밀도.
# 사용: emvs_depth_experiment.py <seq_dir> [t_ref=1.0] [half_window_s=0.25]
import itertools
import os
import sys

import numpy as np
import pandas as pd
from scipy import ndimage as ndi
from scipy.spatial.transform import Rotation as Rot, Slerp

import OpenEXR

Z_MIN, Z_MAX, NZ = 0.8, 6.0, 96
W, H = 240, 180
d = sys.argv[1]; T_REF = float(sys.argv[2]) if len(sys.argv) > 2 else 1.0; HW = float(sys.argv[3]) if len(sys.argv) > 3 else 0.25
fx, fy, cx, cy = np.loadtxt(d + "/calib.txt")[:4]; Zs = 1.0 / np.linspace(1 / Z_MAX, 1 / Z_MIN, NZ)
ev = pd.read_csv(d + "/events.txt", sep=" ", header=None, names=["t", "x", "y", "p"]).values; ev = ev[(ev[:, 0] >= T_REF - HW) & (ev[:, 0] < T_REF + HW)]
t, x, y, p = ev[:, 0], ev[:, 1], ev[:, 2], ev[:, 3].astype(int); g = np.loadtxt(d + "/groundtruth.txt"); print(f"{os.path.basename(d)}: {len(t)} events in [{T_REF - HW:.2f}, {T_REF + HW:.2f}] s, {NZ} planes {Z_MIN}-{Z_MAX} m (inverse-depth spacing)")
SL = Slerp(g[:, 0], Rot.from_quat(g[:, 4:8])); P_all = np.stack([np.interp(t, g[:, 0], g[:, k]) for k in (1, 2, 3)], 1); R_all = SL(t)
R_ref = SL([T_REF])[0]; P_ref = np.array([np.interp(T_REF, g[:, 0], g[:, k]) for k in (1, 2, 3)]); dc = np.c_[(x - cx) / fx, (y - cy) / fy, np.ones(len(x))]


def setup(conv, sx, sy):
    R, P, Rr, Pr = (R_all, P_all, R_ref, P_ref) if conv == "c2w" else (R_all.inv(), -R_all.inv().apply(P_all), R_ref.inv(), -R_ref.inv().apply(P_ref))      # 카메라->월드 회전/카메라 중심
    o = Rr.inv().apply(P - Pr); dd = Rr.inv().apply(R.apply(dc)); o = o * np.array([sx, sy, 1.0]); return o, dd


def project(o, dd):
    lam = (Zs[None, :] - o[:, 2:3]) / dd[:, 2:3]; X = o[:, 0:1] + lam * dd[:, 0:1]; Y = o[:, 1:2] + lam * dd[:, 1:2]
    u = np.rint(fx * X / Zs[None, :] + cx).astype(np.int64); v = np.rint(fy * Y / Zs[None, :] + cy).astype(np.int64); ok = (u >= 0) & (u < W) & (v >= 0) & (v < H)
    return np.where(ok, (np.arange(NZ)[None, :] * H + v) * W + u, -1)


def dsi_of(o, dd, sel, chunk=120000):
    out = np.zeros(NZ * H * W, np.float64); idx = np.nonzero(sel)[0]
    for a in range(0, len(idx), chunk):
        ii = idx[a:a + chunk]; q = project(o[ii], dd[ii]); out += np.bincount(q[q >= 0], minlength=NZ * H * W)
    return out.reshape(NZ, H, W).astype(np.float32)


SM = lambda D: ndi.gaussian_filter(D, (0.7, 1.0, 1.0))
sub = np.zeros(len(t), bool); sub[::15] = True; best = None; print("pose-convention selection by DSI focus (no ground-truth depth used):")
for conv, sx, sy in itertools.product(("c2w", "w2c"), (1, -1), (1, -1)):
    o_, dd_ = setup(conv, sx, sy); f_ = float(SM(dsi_of(o_, dd_, sub)).max(0).sum() / sub.sum()); print(f"   {conv} sx={sx:+d} sy={sy:+d}: focus {f_:.3f}")
    if best is None or f_ > best[0]: best = (f_, conv, sx, sy)
print(f"   -> selected {best[1]} sx={best[2]:+d} sy={best[3]:+d}"); o, dd = setup(*best[1:])


def depth_map(D):
    Ds = SM(D); k = Ds.argmax(0); conf = Ds.max(0); thr = ndi.gaussian_filter(conf, 6) + 0.5; m = (conf > thr) & (conf >= 2); return Zs[k], conf, m


ts = np.loadtxt(d + "/depthmaps.txt", dtype=str); GT = np.array(OpenEXR.File(os.path.join(d, ts[np.argmin(abs(ts[:, 0].astype(float) - T_REF)), 1])).channels()["Z"].pixels)


def evaluate(nm, Z, conf, m, K=3000):
    rel = np.abs(Z - GT) / GT; sel = m & (GT > 0); top = np.argsort(np.where(m, conf, -1).ravel())[::-1][:K]; rt = rel.ravel()[top]
    print(f"{nm:38s} pixels {sel.sum():6d} | median rel err {np.median(rel[sel]) * 100:5.2f}% mean {rel[sel].mean() * 100:5.2f}% | within 5%: {(rel[sel] < 0.05).mean() * 100:5.1f}% | top-{K}: median {np.median(rt) * 100:5.2f}%, within 5% {(rt < 0.05).mean() * 100:5.1f}%", flush=True)


Zq, cq, mq = depth_map(dsi_of(o, dd, np.ones(len(t), bool))); evaluate("A  EMVS (all events)", Zq, cq, mq)
vals, cnts = np.unique(np.round(Zq[mq] / 0.1) * 0.1, return_counts=True); print(f"   estimated depth histogram (confident pixels, >800 px): { {round(float(a), 1): int(b) for a, b in zip(vals, cnts) if b > 800} }   GT depth values: {np.unique(np.round(GT / 0.1) * 0.1)}")
G = 3; grp = np.minimum(((t - t[0]) / (t[-1] - t[0] + 1e-9) * G).astype(int), G - 1)
Dg = {pol: [SM(dsi_of(o, dd, (grp == j) & ((p == pol) if pol is not None else np.ones(len(t), bool)))).ravel() for j in range(G)] for pol in (None, 0, 1)}


def vote(use_pol, chunk=100000):
    keep = np.zeros(len(t), bool)
    for a in range(0, len(t), chunk):
        ii = np.arange(a, min(a + chunk, len(t))); q = project(o[ii], dd[ii]); qc = np.maximum(q, 0); valid = q >= 0; ev_ = np.full((2, len(ii), NZ), -1.0, np.float32)
        for k, dgap in enumerate((1, 2)):
            for j in range(G):
                m = grp[ii] == (j - dgap) % G                                          # 이벤트 구간 g, 증거 구간 j = g + dgap (자기 구간 제외)
                if not m.any(): continue
                if use_pol:
                    for pol in (0, 1):
                        mm = m & (p[ii] == pol); ev_[k][mm] = np.where(valid[mm], Dg[pol][j][qc[mm]], -1)
                else: ev_[k][m] = np.where(valid[m], Dg[None][j][qc[m]], -1)
        ka, kb = ev_[0].argmax(1), ev_[1].argmax(1); ok = (ev_[0].max(1) > 0) & (ev_[1].max(1) > 0); keep[ii] = ok & (np.abs(ka - kb) <= 1)
    return keep


for nm, up in (("B  ours: cross-validated + agreement", False), ("C  ours + polarity-matched evidence", True)):
    keep = vote(up); Zk, ck, mk = depth_map(dsi_of(o, dd, keep)); print(f"   [{nm.split()[0]}] kept {keep.mean() * 100:.1f}% of events"); evaluate(nm, Zk, ck, mk)
