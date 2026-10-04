#!/usr/bin/env python3
# §185: pan 합성 정답 평가. 정답 지도 = 평면 j의 요소들을 자기 Q 좌표(캔버스 = Q - (x0,y0))에 그린 것(올바른 lam으로 되돌린 이상적 결과).
# 지도별(기준선 lam=1 / 전체 이벤트 층 선택 / 신뢰도 게이팅) 지표: NCC(밴드패스, 이동 +-20px 탐색), 잔상 질량(정답 선 3px 밖 질량), 복원율(정답 선 2px 이내 이벤트 존재),
# 이벤트별 층 정답률(|선택 lam - 참 lam| <= 0.015, 깊이 없는 잡음 이벤트 제외).
# 사용: synth_pan_evaluate.py <truth.npz> <run_prefix> <synth.h5> [stride]
import sys

import h5py
import numpy as np
from scipy import ndimage as ndi
from scipy.signal import fftconvolve


def render(truth, x0y0, shape):
    img = np.zeros(shape, np.float32); ox, oy = x0y0
    for a, b, c, d, lam in truth["segs"]:
        n = int(max(abs(c - a), abs(d - b)) * 2) + 2; xs = np.linspace(a, c, n) - ox; ys = np.linspace(b, d, n) - oy
        xi = np.rint(xs).astype(int); yi = np.rint(ys).astype(int); ok = (xi >= 0) & (xi < shape[1]) & (yi >= 0) & (yi < shape[0]); np.add.at(img, (yi[ok], xi[ok]), 1)
    for x, y, lam in truth["dots"]:
        xi, yi = int(round(x - ox)), int(round(y - oy))
        if 0 <= xi < shape[1] and 0 <= yi < shape[0]: img[yi, xi] += 12
    return ndi.gaussian_filter(img, 1.3)


def prep(m):
    m = np.log1p(m.astype(np.float32)); return ndi.gaussian_filter(m, 1.5) - ndi.gaussian_filter(m, 12)


def ncc(a, b, R=20):
    a = a - a.mean(); b = b - b.mean(); cc = fftconvolve(a, b[::-1, ::-1], mode="same")                     # 상호상관(전체), 중심 +-R 안에서 최대
    cy, cx = np.array(cc.shape) // 2; win = cc[cy - R:cy + R + 1, cx - R:cx + R + 1]; iy, ix = np.unravel_index(win.argmax(), win.shape)
    dy, dx = iy - R, ix - R; bs = np.roll(np.roll(b, dy, 0), dx, 1); return float((a * bs).sum() / np.sqrt((a ** 2).sum() * (bs ** 2).sum())), dy, dx


def metrics(M, T, PT, tmask3, tmask2, line):
    n, dy, dx = ncc(PT, prep(M)); Ms = np.roll(np.roll(M, dy, 0), dx, 1)
    prec = Ms[tmask3].sum() / Ms.sum(); sup = ndi.binary_dilation(Ms > 0, iterations=2)
    return n, (1 - prec) * 100, float(sup[line].mean()) * 100


if __name__ == "__main__":
    truth = dict(np.load(sys.argv[1])); pre = sys.argv[2]; stride = int(sys.argv[4]) if len(sys.argv) > 4 else 1
    E = np.load(pre + "_ev.npz"); x0y0 = E["x0y0"]; Mb = np.load(pre + "_base.npy"); Ma = np.load(pre + "_all.npy"); Mg = np.load(pre + "_gate.npy")
    T = render(truth, x0y0, Mb.shape); PT = prep(T); tm = T > 0.05 * T.max(); tmask3 = ndi.binary_dilation(tm, iterations=3); tmask2 = ndi.binary_dilation(tm, iterations=2); line = T > 0.2 * T.max()
    lt = h5py.File(sys.argv[3], "r")["events/lam_true"][::stride].astype(np.float64); n = min(len(lt), len(E["lam_every"]))
    print(f"truth w={float(truth['w']):.2f} (planes lam {np.round(truth['lam_planes'],3).tolist()}, floor lam 1-w..1+w)")
    print(f"{'map':32s}{'NCC':>7s}{'ghost mass %':>14s}{'coverage %':>12s}")
    for nm, M in (("baseline (lambda=1)", Mb), ("layers on all events", Ma), ("layers + confidence gating", Mg)):
        r = metrics(M, T, PT, tmask3, tmask2, line); print(f"{nm:32s}{r[0]:7.3f}{r[1]:14.1f}{r[2]:12.1f}")
    ok = np.isfinite(lt[:n]); ag = E["agree"][:n]; le = E["lam_every"][:n].astype(np.float64); lg = E["lam"][:n].astype(np.float64)
    hit_all = np.abs(le - lt[:n]) <= 0.015; hit_base = np.abs(1.0 - lt[:n]) <= 0.015
    print(f"layer accuracy (events with true depth {ok.sum()/1e6:.1f}M): baseline lambda=1 {hit_base[ok].mean()*100:.1f}% | all-event selection {hit_all[ok].mean()*100:.1f}% | agreed events {ag[ok].mean()*100:.1f}% of events, correct {hit_all[ok & ag].mean()*100:.1f}% | rejected-event accuracy if layer were used {hit_all[ok & ~ag].mean()*100:.1f}%")
