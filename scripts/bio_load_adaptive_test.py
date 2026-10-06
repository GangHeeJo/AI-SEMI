#!/usr/bin/env python3
# §211: 생체 모방 부하 적응 시험. 쓰기 용량이 도착량의 f배로 모자랄 때(과부하) 어떤 이벤트를 버리느냐에 따라 월드 지도가 얼마나 달라지는지 잰다.
# 정답이 없는 실제 DELTA 롤 영상이라 기준 = 같은 θ로 이벤트를 전부 쓴 지도와의 유사도(NCC, 밴드패스, 반경 420px). 깊이 보정 없이 s=0 평면으로 쌓아 정책 간 상대 비교만 한다.
# 정책(창 = 센서 프레임 하나(약 773 us, 프레임 안 이벤트는 x(열) 순서로 읽힘), 창 안에서 용량 n = f*N):
#   P0 꼬리 버림   : 도착 순서 앞쪽 n개만(현재 하드웨어 FIFO 가득 참 동작, 센서 행 순서로 읽히면 늦게 읽히는 행이 계속 버려짐)
#   P1 이득 조절   : 균등 솎아내기(n개를 창 전체에서 고르게)
#   P2 습관화      : 창 안에서 지도 칸을 처음 보는 이벤트를 먼저, 남는 용량은 균등 솎아내기로 채움
#   P3 도약성 억제 : 회전이 빠른 창에 용량을 덜 주고(예산 ∝ 1/속도) 느린 창에 더 줌, 창 안은 균등 솎아내기. 전체 용량 합은 같음
#   P4 P2+P3
# 도착 스트림은 원본 이벤트의 1/STRIDE 표본. 사용: bio_load_adaptive_test.py <events.h5> <theta.npy> <calib.json> [stride=4]
import json
import sys

import h5py
import numpy as np
from scipy import ndimage as ndi

sys.path.insert(0, "scripts")
from delta_depthwarp2 import load_cal  # noqa: E402

C, OFF, R0 = 1200, 600.0, 420
FRACS = (0.5, 0.25, 0.1)


def cells(x, y, a, c0):
    px = x - c0[0]; py = y - c0[1]; c, s = np.cos(a), np.sin(a)
    xi = np.rint(c * px - s * py + OFF).astype(np.int64); yi = np.rint(s * px + c * py + OFF).astype(np.int64)
    ok = (xi >= 0) & (xi < C) & (yi >= 0) & (yi < C)
    return np.where(ok, yi * C + xi, -1)


def pick_uniform(n_have, n_keep):
    if n_keep >= n_have: return np.arange(n_have)
    return np.floor(np.arange(n_keep) * (n_have / max(n_keep, 1))).astype(np.int64)


def pick_novel(cell, n_keep):
    _, first = np.unique(cell, return_index=True); first.sort()
    if len(first) >= n_keep: return first[pick_uniform(len(first), n_keep)]
    rest = np.setdiff1d(np.arange(len(cell)), first, assume_unique=True)
    return np.sort(np.concatenate([first, rest[pick_uniform(len(rest), n_keep - len(first))]]))


def bandpass(m):
    m = m.reshape(C, C).astype(np.float64); return ndi.gaussian_filter(m, 1.0) - ndi.gaussian_filter(m, 6.0)


def ncc(a, b):
    yy, xx = np.mgrid[:C, :C]; mk = np.hypot(xx - OFF, yy - OFF) <= R0
    u = a[mk] - a[mk].mean(); v = b[mk] - b[mk].mean(); return float((u * v).sum() / (np.linalg.norm(u) * np.linalg.norm(v) + 1e-12))


def main(h5p, th_npy, cal_json, stride):
    _, c0, _, _ = load_cal(cal_json); th = np.load(th_npy); mids = (np.arange(len(th)) * 4 + 2) * 1e3
    f = h5py.File(h5p, "r"); n_all = f["events/t"].shape[0]
    speed = np.abs(np.gradient(th)) / 0.004; sp_med = np.median(speed[speed > 0])
    x = f["events/x"][::stride].astype(np.float64); y = f["events/y"][::stride].astype(np.float64); t = f["events/t"][::stride].astype(np.float64)
    a = -np.interp(t, mids, th); cell = cells(x, y, a, c0)
    _, fstart = np.unique(t, return_index=True); edges = np.concatenate([fstart, [len(t)]]); nwin = len(fstart)
    print(f"arrivals {len(t)} (1/{stride} of {n_all}), frames {nwin}, valid cells {np.mean(cell >= 0):.3f}", flush=True)
    full = np.bincount(cell[cell >= 0], minlength=C * C); Bf = bandpass(full)
    N_w = np.diff(edges); w_speed = np.interp(t[fstart], mids, speed)
    g = 1.0 / (1.0 + w_speed / sp_med)                                                     # P3: 빠를수록 작은 가중
    print(f"{'f':>5s} {'policy':>14s} {'kept':>9s} {'NCC vs full':>12s}")
    for fr in FRACS:
        total_cap = fr * N_w.sum(); budget3 = total_cap * (N_w * g) / (N_w * g).sum()
        for name in ("P0 tail-drop", "P1 gain", "P2 habituation", "P3 saccadic", "P4 P2+P3"):
            m = np.zeros(C * C); kept = 0
            for i in range(nwin):
                s0, s1 = edges[i], edges[i + 1]; n = s1 - s0
                if n == 0: continue
                cw = cell[s0:s1]; cap = int(round(fr * n)) if name in ("P0 tail-drop", "P1 gain", "P2 habituation") else int(round(budget3[i]))
                cap = min(cap, n)
                if name == "P0 tail-drop": idx = np.arange(cap)
                elif name in ("P1 gain", "P3 saccadic"): idx = pick_uniform(n, cap)
                else: idx = pick_novel(cw, cap)
                sel = cw[idx]; sel = sel[sel >= 0]; m += np.bincount(sel, minlength=C * C); kept += len(idx)
            print(f"{fr:5.2f} {name:>14s} {kept / N_w.sum() * 100:8.1f}% {ncc(bandpass(m), Bf):12.3f}", flush=True)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]) if len(sys.argv) > 4 else 4)
