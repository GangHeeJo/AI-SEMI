"""Replay the chip-S integer reference models over a whole recording and save world-map snapshots.
estimator = job24_est.EstS (bit-exact with the chip-S estimator RTL), world = job24_world.py semantics
(8 px cell, 4-bit Morris counter, LFSR16, stream order). usage: python3 make_snaps.py roll|pan [every=4] [maxframes]"""
import sys, numpy as np
from pathlib import Path
RES = Path.home() / 'redred_gate_ext/ecc/work/results'
sys.path.insert(0, str(RES))
import job6_golden as G
import job17_core as J
import job24_est as E

ds = sys.argv[1]; every = int(sys.argv[2]) if len(sys.argv) > 2 else 4
maxf = int(sys.argv[3]) if len(sys.argv) > 3 else 10 ** 9
F = 10; LFSR0 = 0xACE1
st = G.Stream(ds)
est = E.attach_gt_start(E.make_prof(ds), ds)
if ds == 'pan':
    Wd, _ = E.pan_coupling_regs(); wp = Wd
else:
    wp = dict(pivot=est.pivot)
nf = min(st.nf, maxf)

# ---- 1) per-frame world parameters from the estimator, whole stream
fp = {}
f = 1
while f < nf:
    L = est.next_len()
    frames = list(range(f, min(f + L, st.nf)))
    evs = [st.frame(k) for k in frames]
    n = sum(len(e[0]) for e in evs)
    wev = (np.concatenate([e[0] for e in evs]), np.concatenate([e[1] for e in evs]),
           np.concatenate([np.full(len(e[0]), j, np.int8) for j, e in enumerate(evs)]))
    qc, per = est.begin_poses(len(frames)); est._applied = qc
    for k, p in zip(frames, per):
        fp[k] = E.wparams(est.mode, p, wp)
    est.end(len(est.trace), frames, wev, n)
    f += len(frames)
print('estimator done, frames', len(fp), flush=True)

# ---- 2) world accumulation (job24_world semantics) with snapshots
g4, g8 = J.grids(ds)
X0, Y0, W, H = g8.X0, g8.Y0, g8.W, g8.H
m = np.zeros(W * H, np.int64); r = LFSR0
def lstep(r): return (r >> 1) | ((((r >> 0) ^ (r >> 2) ^ (r >> 3) ^ (r >> 5)) & 1) << 15)
snaps, sens, ks, angs = [], [], [], []
recent = []
for k in range(1, nf):
    cs, sn, bx, by = fp[k]
    x, y, _ = st.frame(k)
    X = bx + cs * x.astype(np.int64) - sn * y.astype(np.int64); Y = by + sn * x.astype(np.int64) + cs * y.astype(np.int64)
    cx = ((X >> F) - X0) >> 3; cy = ((Y >> F) - Y0) >> 3
    ok = (cx >= 0) & (cx < W) & (cy >= 0) & (cy < H)
    for c in (cy * W + cx)[ok]:
        r = lstep(r); v = int(m[c])
        if v < 15 and (r & ((1 << v) - 1)) == 0:
            m[c] = v + 1
    s = np.zeros((180, 240), np.uint16); np.add.at(s, (y // 4, x // 4), 1)
    recent.append(s); recent = recent[-4:]
    if k % every == 0:
        snaps.append(m.reshape(H, W).astype(np.uint8)); sens.append(np.minimum(sum(recent), 255).astype(np.uint8))
        ks.append(k); angs.append(np.degrees(np.arctan2(sn, cs)))
    if k % 100 == 0: print('frame', k, 'cells', int((m > 0).sum()), flush=True)
out = Path.home() / 'redred_gate_ext/video'; out.mkdir(exist_ok=True)
np.savez_compressed(out / f'snaps_{ds}.npz', world=np.array(snaps), sensor=np.array(sens), k=np.array(ks), ang=np.array(angs),
                    X0=X0, Y0=Y0, W=W, H=H, every=every)
print('saved', len(snaps), 'snapshots', flush=True)
