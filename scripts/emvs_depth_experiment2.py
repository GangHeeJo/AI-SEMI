#!/usr/bin/env python3
# §202 (§201의 후속): EMVS식 후처리(쌍선형 투표, 가우시안 적응 임계, 중앙값 필터)를 모든 방법에 똑같이 적용해 투표/증거 단계의 차이만 비교.
# UZH simulation_3planes/3walls(깊이 정답 있음)에서:
#   A   EMVS 표준: 모든 이벤트가 모든 깊이 평면에 쌍선형 투표한 DSI
#   A2  모든 이벤트가 자기 구간을 제외한 두 시간 구간의 증거로 평면 하나를 골라 그 평면에만 투표(일치 필터 없음)
#   B   A2 + 두 복제본이 +-1평면 안에서 일치한 이벤트만
#   C   B + 같은 극성 DSI에서 증거를 얻음
# EMVS 후처리: 신뢰도 = 평면별 최댓값, 깊이 = argmax, 마스크 = 8비트 정규화한 신뢰도가 가우시안 5x5 국소 평균 + c보다 큰 곳, 깊이 인덱스와 마스크에 5x5 중앙값 필터.
# (세부 값은 논문 설정에 대한 기억 기반이라 공식 코드와 같다고 장담 못 함 -> A에는 정답으로 c를 고른 최선 사례를 따로 보고하는 관대한 기준도 적용)
# 깊이 범위는 넓은 사전값(역깊이 균등), 자세 규약은 정답 깊이를 쓰지 않고 DSI 초점으로 자동 선택.
# 사용: emvs_depth_experiment2.py <seq_dir> [t_ref=1.0] [half_window_s=0.25]
import itertools
import os
import sys

import cv2
import numpy as np
import pandas as pd
from scipy import ndimage as ndi
from scipy.spatial.transform import Rotation as Rot, Slerp

import OpenEXR

Z_MIN, Z_MAX, NZ = 0.8, 10.0, 112
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


def project_f(o, dd):
    lam = (Zs[None, :] - o[:, 2:3]) / dd[:, 2:3]; X = o[:, 0:1] + lam * dd[:, 0:1]; Y = o[:, 1:2] + lam * dd[:, 1:2]
    return fx * X / Zs[None, :] + cx, fy * Y / Zs[None, :] + cy


def project(o, dd):                                                                         # 반올림 인덱스(증거 계산용)
    u, v = project_f(o, dd); u = np.rint(u).astype(np.int64); v = np.rint(v).astype(np.int64); ok = (u >= 0) & (u < W) & (v >= 0) & (v < H)
    return np.where(ok, (np.arange(NZ)[None, :] * H + v) * W + u, -1)


def splat(out, u, v, plane):                                                                # EMVS식 쌍선형 투표
    u0 = np.floor(u).astype(np.int64); v0 = np.floor(v).astype(np.int64); fu = u - u0; fv = v - v0
    for du, dv, ww in ((0, 0, (1 - fu) * (1 - fv)), (1, 0, fu * (1 - fv)), (0, 1, (1 - fu) * fv), (1, 1, fu * fv)):
        uu = u0 + du; vv = v0 + dv; ok = (uu >= 0) & (uu < W) & (vv >= 0) & (vv < H); out += np.bincount(((plane * H + vv) * W + uu)[ok], weights=ww[ok], minlength=len(out))


def dsi_of(o, dd, sel, chunk=120000):                                                       # 증거용 DSI(반올림 투표)
    out = np.zeros(NZ * H * W, np.float64); idx = np.nonzero(sel)[0]
    for a in range(0, len(idx), chunk):
        ii = idx[a:a + chunk]; q = project(o[ii], dd[ii]); out += np.bincount(q[q >= 0], minlength=NZ * H * W)
    return out.reshape(NZ, H, W).astype(np.float32)


def dsi_all_planes_bilinear(o, dd, chunk=60000):                                            # A: 모든 이벤트가 모든 평면에 쌍선형 투표(EMVS 표준)
    out = np.zeros(NZ * H * W, np.float64)
    for a in range(0, len(o), chunk):
        u, v = project_f(o[a:a + chunk], dd[a:a + chunk]); splat(out, u, v, np.broadcast_to(np.arange(NZ)[None, :], u.shape))
    return out.reshape(NZ, H, W)


def dsi_assigned(su, sv, sk):                                                               # 이벤트가 고른 평면에만 쌍선형 투표
    out = np.zeros(NZ * H * W, np.float64); m = sk >= 0; splat(out, su[m], sv[m], sk[m]); return out.reshape(NZ, H, W)


SM = lambda D: ndi.gaussian_filter(D, (0.7, 1.0, 1.0))
sub = np.zeros(len(t), bool); sub[::15] = True; best = None
for conv, sx, sy in itertools.product(("c2w", "w2c"), (1, -1), (1, -1)):
    o_, dd_ = setup(conv, sx, sy); f_ = float(SM(dsi_of(o_, dd_, sub)).max(0).sum() / sub.sum())
    if best is None or f_ > best[0]: best = (f_, conv, sx, sy)
print(f"pose convention selected by DSI focus (no ground-truth depth used): {best[1]} sx={best[2]:+d} sy={best[3]:+d}"); o, dd = setup(*best[1:])


def emvs_extract(D, med=5):                                                                 # 신뢰도 = 평면별 최댓값, 깊이 = argmax 인덱스에 중앙값 필터(EMVS 후처리의 임계 마스크는 쓰지 않음: 임계 하나에 결과가 좌우되어 같은 커버리지 비교로 대체)
    conf = D.max(0).astype(np.float32); idx = cv2.medianBlur(D.argmax(0).astype(np.uint8), med); return Zs[idx], conf


ts = np.loadtxt(d + "/depthmaps.txt", dtype=str); GT = np.array(OpenEXR.File(os.path.join(d, ts[np.argmin(abs(ts[:, 0].astype(float) - T_REF)), 1])).channels()["Z"].pixels)


def report(nm, D, ks=(1000, 3000, 6000)):                                                  # 각 방법의 자기 신뢰도 상위 K 픽셀에서 정확도(같은 커버리지 비교)
    Z, conf = emvs_extract(D); order = np.argsort(conf.ravel())[::-1]; rel = (np.abs(Z - GT) / GT).ravel(); out = []
    for K in ks: r = rel[order[:K]]; out.append(f"K={K}: median {np.median(r) * 100:5.2f}% within5% {(r < 0.05).mean() * 100:5.1f}%")
    print(f"{nm:44s} " + " | ".join(out), flush=True)


report("A  EMVS (all events, all planes, bilinear)", dsi_all_planes_bilinear(o, dd))
D_on = dsi_all_planes_bilinear(o[p == 1], dd[p == 1]); D_off = dsi_all_planes_bilinear(o[p == 0], dd[p == 0])
report("A+pol EMVS with per-polarity DSI (sqrt of sum sq)", np.sqrt(D_on ** 2 + D_off ** 2))                  # 극성별로 따로 투표한 DSI의 제곱합 제곱근: 같은 극성끼리 모일수록 높음(EMVS 틀 안에서 극성만 추가)
G = 3; grp = np.minimum(((t - t[0]) / (t[-1] - t[0] + 1e-9) * G).astype(int), G - 1)
Dg = {pol: [SM(dsi_of(o, dd, (grp == j) & ((p == pol) if pol is not None else np.ones(len(t), bool)))).ravel() for j in range(G)] for pol in (None, 0, 1)}


def vote(use_pol, chunk=100000):
    keep = np.zeros(len(t), bool); su = np.zeros(len(t)); sv = np.zeros(len(t)); sk = np.full(len(t), -1, np.int64)
    for a in range(0, len(t), chunk):
        ii = np.arange(a, min(a + chunk, len(t))); u, v = project_f(o[ii], dd[ii]); q = project(o[ii], dd[ii]); qc = np.maximum(q, 0); valid = q >= 0; ev_ = np.full((2, len(ii), NZ), -1.0, np.float32)
        for k, dgap in enumerate((1, 2)):
            for j in range(G):
                m = grp[ii] == (j - dgap) % G                                          # 이벤트 구간 g, 증거 구간 j = g + dgap (자기 구간 제외)
                if not m.any(): continue
                if use_pol:
                    for pol in (0, 1):
                        mm = m & (p[ii] == pol); ev_[k][mm] = np.where(valid[mm], Dg[pol][j][qc[mm]], -1)
                else: ev_[k][m] = np.where(valid[m], Dg[None][j][qc[m]], -1)
        ka, kb = ev_[0].argmax(1), ev_[1].argmax(1); ok = (ev_[0].max(1) > 0) & (ev_[1].max(1) > 0); keep[ii] = ok & (np.abs(ka - kb) <= 1)
        kc = (ev_[0] + ev_[1]).argmax(1); r = np.arange(len(ii)); su[ii] = u[r, kc]; sv[ii] = v[r, kc]; sk[ii] = np.where(ok, kc, -1)
    return keep, su, sv, sk


kB, su, sv, skB = vote(False); kC, suC, svC, skC = vote(True)
report("A2 every event votes its own plane", dsi_assigned(su, sv, skB))
print(f"   [B] kept {kB.mean() * 100:.1f}% of events"); report("B  ours: assigned + agreement", dsi_assigned(su, sv, np.where(kB, skB, -1)))
print(f"   [C] kept {kC.mean() * 100:.1f}% of events"); report("C  ours + polarity-matched", dsi_assigned(suC, svC, np.where(kC, skC, -1)))
