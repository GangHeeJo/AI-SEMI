#!/usr/bin/env python3
# §201: 깊이 정답이 있는 시뮬레이션 시퀀스(UZH simulation_3planes/3walls)로 이벤트 깊이 추정 방식을 비교.
# EMVS(Rebecq 2018)와 같은 틀: 기준 시점의 깊이 평면 Z_i들에 이벤트 광선을 투영해 시차 공간 영상(DSI, 평면별 이벤트 수)을 만들고 평면별 최댓값으로 깊이를 구함.
#   A  EMVS 기본: 모든 이벤트로 만든 DSI의 argmax
#   B  우리 방식: 시간 G=3 구간. 이벤트는 자기 구간을 제외한 두 구간의 DSI(평활)로 평면을 각각 고르고(자기 이벤트 불참), 두 선택이 +-1평면 안에서 일치하면 채택. 채택 이벤트만으로 DSI 재구성
#   C  B + 극성: 이벤트가 같은 극성 DSI에서 증거를 얻음
# 깊이 범위는 사전값(Z_MIN, Z_MAX; 정답을 보고 정한 것이 아님), 자세 규약(카메라->월드 / 월드->카메라)은 정답 깊이를 쓰지 않고 DSI 대비가 큰 쪽으로 자동 선택.
# 평가: 기준 시각에 가장 가까운 정답 깊이 맵과 추정 깊이의 절대 상대오차(|Z - Zgt| / Zgt), 5% 이내 비율, 신뢰도 상위 K 픽셀 정밀도.
# 사용: emvs_depth_experiment.py <seq_dir> [t_ref] [half_window_s]
import os
import sys

import numpy as np
import pandas as pd
from scipy import ndimage as ndi
from scipy.spatial.transform import Rotation as Rot, Slerp

import OpenEXR

Z_MIN, Z_MAX, NZ = 1.0, 2.2, 72
W, H = 240, 180
d = sys.argv[1]; T_REF = float(sys.argv[2]) if len(sys.argv) > 2 else 1.0; HW = float(sys.argv[3]) if len(sys.argv) > 3 else 0.25
fx, fy, cx, cy = np.loadtxt(d + "/calib.txt")[:4]; Zs = np.linspace(Z_MIN, Z_MAX, NZ)
ev = pd.read_csv(d + "/events.txt", sep=" ", header=None, names=["t", "x", "y", "p"]).values; ev = ev[(ev[:, 0] >= T_REF - HW) & (ev[:, 0] < T_REF + HW)]
t, x, y, p = ev[:, 0], ev[:, 1], ev[:, 2], ev[:, 3].astype(int); g = np.loadtxt(d + "/groundtruth.txt"); print(f"{os.path.basename(d)}: {len(t)} events in [{T_REF - HW:.2f}, {T_REF + HW:.2f}] s, {NZ} planes {Z_MIN}-{Z_MAX} m")
Rw = Slerp(g[:, 0], Rot.from_quat(g[:, 4:8])); pos = np.stack([np.interp(t, g[:, 0], g[:, k]) for k in (1, 2, 3)], 1); rot = Rw(t)
rref = Rw([T_REF])[0]; cref = np.array([np.interp(T_REF, g[:, 0], g[:, k]) for k in (1, 2, 3)])


dc = np.c_[(x - cx) / fx, (y - cy) / fy, np.ones(len(x))]; o = rref.inv().apply(pos - cref); dd = rref.inv().apply(rot.apply(dc))                    # 이벤트 광선을 기준 카메라 좌표계로(자세 = 카메라->월드)


def project(o, dd, i0, i1):
    lam = (Zs[None, :] - o[i0:i1, 2:3]) / dd[i0:i1, 2:3]; X = o[i0:i1, 0:1] + lam * dd[i0:i1, 0:1]; Y = o[i0:i1, 1:2] + lam * dd[i0:i1, 1:2]
    u = np.rint(fx * X / Zs[None, :] + cx).astype(np.int64); v = np.rint(fy * Y / Zs[None, :] + cy).astype(np.int64); ok = (u >= 0) & (u < W) & (v >= 0) & (v < H)
    return np.where(ok, (np.arange(NZ)[None, :] * H + v) * W + u, -1)                       # DSI 선형 위치(평면, 행, 열)


def dsi_of(o, dd, sel, chunk=120000):
    out = np.zeros(NZ * H * W, np.float64); idx = np.nonzero(sel)[0]
    for a in range(0, len(idx), chunk):
        ii = idx[a:a + chunk]; q = project(o[ii], dd[ii], 0, len(ii)); out += np.bincount(q[q >= 0], minlength=NZ * H * W)
    return out.reshape(NZ, H, W).astype(np.float32)
SM = lambda D: ndi.gaussian_filter(D, (0.7, 1.0, 1.0))


def depth_map(D):
    Ds = SM(D); k = Ds.argmax(0); conf = Ds.max(0); thr = ndi.gaussian_filter(conf, 6) * 1.0 + 0.5; m = (conf > thr) & (conf >= 2); return Zs[k], conf, m


def gt_depth():
    ts = np.loadtxt(d + "/depthmaps.txt", dtype=str); tt = ts[:, 0].astype(float); f = ts[np.argmin(abs(tt - T_REF)), 1]
    ch = OpenEXR.File(os.path.join(d, f)).channels()["Z"].pixels; return np.array(ch)


GT = gt_depth()
def evaluate(nm, Z, conf, m, K=3000):
    rel = np.abs(Z - GT) / GT; sel = m & (GT > 0); top = np.argsort(np.where(m, conf, -1).ravel())[::-1][:K]; rt = rel.ravel()[top]
    print(f"{nm:34s} pixels {sel.sum():6d} | median rel err {np.median(rel[sel]) * 100:5.2f}% mean {rel[sel].mean() * 100:5.2f}% | within 5%: {(rel[sel] < 0.05).mean() * 100:5.1f}% | top-{K} confident: median {np.median(rt) * 100:5.2f}%, within 5% {(rt < 0.05).mean() * 100:5.1f}%")


Dall = dsi_of(o, dd, np.ones(len(t), bool)); Zq, cq, mq = depth_map(Dall); evaluate("A  EMVS (all events)", Zq, cq, mq)

# --- B / C: 시간 G=3 구간, 자기 구간을 뺀 증거로 평면 선택 + 두 복제본 일치
G = 3; grp = np.minimum(((t - t[0]) / (t[-1] - t[0] + 1e-9) * G).astype(int), G - 1)
Dg = {pol: [dsi_of(o, dd, (grp == j) & ((p == pol) if pol is not None else True)) for j in range(G)] for pol in (None, 0, 1)}
Dg_s = {pol: [SM(Dg[pol][j]).ravel() for j in range(G)] for pol in Dg}


def vote(use_pol, chunk=100000):
    keep = np.zeros(len(t), bool); idx = np.arange(len(t))
    for a in range(0, len(t), chunk):
        ii = idx[a:a + chunk]; q = project(o[ii], dd[ii], 0, len(ii)); qc = np.maximum(q, 0); valid = q >= 0; ev_ = np.zeros((2, len(ii), NZ), np.float32)
        for k, dgap in enumerate((1, 2)):
            for j in range(G):
                m = grp[ii] == (j - dgap) % G                                    # 이 이벤트 구간 g, 증거 구간 j = g + dgap (자기 구간 제외)
                if not m.any(): continue
                if use_pol:
                    for pol in (0, 1):
                        mm = m & (p[ii] == pol); ev_[k][mm] = np.where(valid[mm], Dg_s[pol][j][qc[mm]], -1)
                else: ev_[k][m] = np.where(valid[m], Dg_s[None][j][qc[m]], -1)
        ka, kb = ev_[0].argmax(1), ev_[1].argmax(1); ok = (ev_[0].max(1) > 0) & (ev_[1].max(1) > 0); keep[ii] = ok & (np.abs(ka - kb) <= 1)
    return keep


for nm, up in (("B  ours: cross-validated + agreement", False), ("C  ours + polarity-matched evidence", True)):
    keep = vote(up); Dk = dsi_of(o, dd, keep); Zk, ck, mk = depth_map(Dk); print(f"   [{nm.split()[0]}] kept {keep.mean() * 100:.1f}% of events"); evaluate(nm, Zk, ck, mk)
