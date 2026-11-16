"""job24 step 4: end-to-end expectation for chip_s_full (estimator -> transform -> world) on a job24 vector segment.
World starts at zero, LFSR at LFSR0; every in-range sensor pixel of frames f0..f1-1 (stream order) is mapped with
the ESTIMATOR's per-frame params (exp_fp.hex) and Morris-updated sequentially (job23b world_writer semantics:
W17 8 px cell, 4-bit Morris, linear packing 16 cells/word, 128 words/bank, row-major).
    python job24_world.py <seg>      -> results/job24_vectors/<seg>/{world.json, mem_final_w.hex}
"""
import numpy as np, json, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "results"))
import job6_golden as G
import job17_core as J

R = G.R
seg = sys.argv[1]; ds = seg.split('_')[0]
D = Path(__file__).resolve().parent / "out/vec" / seg
meta = json.load(open(D / "meta.json")); meta["f0"], meta["f1"] = 0, meta["frames"]
F = 10; LFSR0 = 0xACE1; NB, WPB = 16, 128


def lstep(r):
    return (r >> 1) | ((((r >> 0) ^ (r >> 2) ^ (r >> 3) ^ (r >> 5)) & 1) << 15)


def s32(h):
    v = int(h, 16); return v - (1 << 32) if v >= 1 << 31 else v


st = G.Stream(ds)
g4, g8 = J.grids(ds)
X0, Y0, W, H = g8.X0, g8.Y0, g8.W, g8.H
assert W * H <= NB * WPB * 16
fp = [tuple(s32(t) for t in l.split()) for l in open(D / 'exp_fp.hex')]
f0, f1 = meta['f0'], meta['f1']
assert len(fp) == f1 - f0
m = np.zeros(W * H, np.int64); r = LFSR0; ninr = 0
for i, k in enumerate(range(f0, f1)):
    cs, sn, bx, by = fp[i]
    x, y, _ = st.frame(k)
    X = bx + cs * x.astype(np.int64) - sn * y.astype(np.int64); Y = by + sn * x.astype(np.int64) + cs * y.astype(np.int64)
    cx = ((X >> F) - X0) >> 3; cy = ((Y >> F) - Y0) >> 3
    ok = (cx >= 0) & (cx < W) & (cy >= 0) & (cy < H)
    for c in (cy * W + cx)[ok]:
        r = lstep(r); v = int(m[c])
        if v < 15 and (r & ((1 << v) - 1)) == 0:
            m[c] = v + 1
    ninr += int(ok.sum())
words = np.zeros(NB * WPB, np.uint64)
c = np.arange(W * H)
np.bitwise_or.at(words, c >> 4, (m.astype(np.uint64) << (np.uint64(4) * (c & 15).astype(np.uint64))))
with open(D / 'mem_final_w.hex', 'w') as fh:
    for v in words:
        fh.write(f'{int(v):016x}\n')
json.dump(dict(X0=int(X0), Y0=int(Y0), W=int(W), H=int(H), lfsr0=LFSR0, n_inrange=ninr, lfsr_end=r,
               nonzero_cells=int((m > 0).sum())), open(D / 'world.json', 'w'), indent=1)
print(seg, X0, Y0, W, H, 'inrange', ninr, 'cells', int((m > 0).sum()))
with open(D / 'wgrid.hex', 'w') as fh:
    for v in (X0, Y0, W, H):
        fh.write(format(int(v) & ((1 << 64) - 1), '016x') + '\n')
