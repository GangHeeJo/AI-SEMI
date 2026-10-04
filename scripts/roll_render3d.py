#!/usr/bin/env python3
# §187: 상대 3D 점 (u,v,s)의 시각화. (1) 깊이 색 지도 (2) u-s 단면도(깊이 층 구조) (3) 가상 시점 이동 렌더(상대 시차 gamma*(s-s_mid) 만큼 가로 이동).
# 사용: roll_render3d.py <events.h5> <theta.npy> <calib.json> <diag_prefix> <out.png> [title]   (DELTA_RHO 환경변수는 해당 실행과 동일하게)
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from scipy import ndimage as ndi

from roll_relative3d import load, uv

h5p, th, cal, diag, out = sys.argv[1:6]; title = sys.argv[6] if len(sys.argv) > 6 else ""
x, y, a, s, fl, e, c0, tol, C = load(h5p, th, cal, diag); ag = (fl == 1) & np.isfinite(s); x, y, a, s = x[ag], y[ag], a[ag], s[ag]; u, v = uv(x, y, a, s, e, c0); OFF = C / 2
lo, hi = np.percentile(s, [2, 98]); smid = float(np.median(s)); print(f"agreed events {len(s)}; s range (2-98%) {lo:.0f}..{hi:.0f} px, median {smid:.0f}")
def depth_map(du=0.0):
    p = np.rint(v + OFF).astype(np.int64) * C + np.rint(u + du + OFF).astype(np.int64); ok = (p >= 0) & (p < C * C); p = p[ok]
    N = np.bincount(p, minlength=C * C).reshape(C, C).astype(np.float32); S = np.bincount(p, weights=s[ok], minlength=C * C).reshape(C, C).astype(np.float32)
    ys, xs = np.nonzero(N > np.percentile(N[N > 0], 50)); y0, y1 = np.percentile(ys, [1, 99]).astype(int); x0, x1 = np.percentile(xs, [1, 99]).astype(int)
    return N[y0:y1, x0:x1], S[y0:y1, x0:x1]
def colorize(N, S):
    Sm = ndi.gaussian_filter(S, 1.5) / np.maximum(ndi.gaussian_filter(N, 1.5), 1e-6); h = np.clip((Sm - lo) / (hi - lo + 1e-6), 0, 1)
    rgb = plt.cm.turbo(h)[..., :3]; br = np.clip(N / np.percentile(N[N > 0], 99.5), 0, 1) ** 0.5; return rgb * br[..., None]
fig, ax = plt.subplots(2, 3, figsize=(30, 20))
N, S = depth_map(); ax[0, 0].imshow(colorize(N, S)); ax[0, 0].set_title(f"{title} depth-colored world map (color = relative depth s, blue far end .. red near end)", fontsize=13)
ax[0, 1].imshow(np.minimum(N, np.percentile(N[N > 0], 99.5)) ** 0.6, cmap="gray"); ax[0, 1].set_title("same map, intensity only", fontsize=13)
H, ue, se = np.histogram2d(u, s, bins=[np.arange(u.min(), u.max(), 3), np.arange(lo - 20, hi + 20, 3)]); ax[0, 2].imshow(np.log1p(H).T, origin="lower", aspect="auto", cmap="magma", extent=[ue[0], ue[-1], se[0], se[-1]])
ax[0, 2].set_title("cross-section: world x (u) vs relative depth s  (horizontal bands = depth layers)", fontsize=13)
for k, g in enumerate((-0.6, 0.6)):
    Nn, Sn = depth_map(g * 0.0)  # placeholder to keep crop identical
    p = np.rint(v + OFF).astype(np.int64) * C + np.rint(u + g * (s - smid) + OFF).astype(np.int64); ok = (p >= 0) & (p < C * C); M = np.bincount(p[ok], minlength=C * C).reshape(C, C).astype(np.float32)
    ys, xs = np.nonzero(N > 0); M = M[: , :]; yy, xx = np.nonzero(depth_map()[0] >= 0)  # crop below
    ax[1, k].set_title(f"virtual viewpoint shift gamma={g:+.1f} (parallax = gamma*(s - s_median))", fontsize=13); ax[1, k].imshow(np.minimum(M, np.percentile(M[M > 0], 99.5)) ** 0.6, cmap="gray")
    ys2, xs2 = np.nonzero(M > np.percentile(M[M > 0], 50)); ax[1, k].set_ylim(np.percentile(ys2, 99), np.percentile(ys2, 1)); ax[1, k].set_xlim(np.percentile(xs2, 1), np.percentile(xs2, 99))
ax[1, 2].axis("off")
for a_ in ax.ravel(): a_.tick_params(labelsize=8)
plt.tight_layout(); plt.savefig(out, dpi=36)
