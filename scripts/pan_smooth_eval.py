#!/usr/bin/env python3
# §186: 깊이 평활 제약을 합성 정답으로 평가. 사용: pan_smooth_eval.py <truth.npz> <run_prefix> <synth.h5> <track.npy> [cells] [wins_ms]
import sys

import h5py
import numpy as np

from pan_smooth_lambda import place, smooth
from synth_pan_evaluate import metrics, prep, render
from scipy import ndimage as ndi

truth = dict(np.load(sys.argv[1])); pre = sys.argv[2]; h5p = sys.argv[3]; tr = np.load(sys.argv[4])
cells = [int(v) for v in sys.argv[5].split(",")] if len(sys.argv) > 5 else [8, 16, 32]; wins = [float(v) for v in sys.argv[6].split(",")] if len(sys.argv) > 6 else [3.1, 12.4]
E = np.load(pre + "_ev.npz"); x0, y0 = E["x0y0"]; le = E["lam_every"].astype(np.float64); Mb = np.load(pre + "_base.npy"); shape = Mb.shape
f = h5py.File(h5p, "r"); x = f["events/x"][:].astype(np.float64); y = f["events/y"][:].astype(np.float64); t = f["events/t"][:].astype(np.float64); lt = f["events/lam_true"][:].astype(np.float64)
px = np.interp(t, tr[:, 0], tr[:, 1]); py = np.interp(t, tr[:, 0], tr[:, 2]); n = min(len(le), len(t))
T = render(truth, (x0, y0), shape); PT = prep(T); tm = T > 0.05 * T.max(); t3 = ndi.binary_dilation(tm, iterations=3); t2 = ndi.binary_dilation(tm, iterations=2); line = T > 0.2 * T.max(); ok = np.isfinite(lt)
print(f"truth w={float(truth['w']):.2f}   (unsmoothed all-event layers NCC reference below)"); print(f"{'variant':34s}{'NCC':>7s}{'ghost %':>9s}{'cover %':>9s}{'lambda acc %':>14s}")
def row(nm, lam):
    M = place(x[:n], y[:n], px[:n], py[:n], lam, x0, y0, shape); r = metrics(M, T, PT, t3, t2, line); acc = (np.abs(lam - lt[:n]) <= 0.015)[ok[:n]].mean() * 100
    print(f"{nm:34s}{r[0]:7.3f}{r[1]:9.1f}{r[2]:9.1f}{acc:14.1f}")
row("baseline lambda=1", np.ones(n)); row("all-event layers (no smoothing)", le[:n])
for c in cells:
    for w in wins: row(f"smoothed cell {c}px, window {w}ms", smooth(x[:n], y[:n], t[:n], le[:n], c, w * 1000))
