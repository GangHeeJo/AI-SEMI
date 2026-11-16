"""selfcal step B0: collect integer 3-DOF bootstrap observations on the professor data and diagnose the r2 boundary.

Runs job24_est.EstS(mode='3d') from the stream start with q_init = 0 and pivot P = sensor centre (no GT, no tuned
pivot), records (th, tx, ty) after every window, and evaluates the job26 bootstrap fit at the trigger window in the
CHIP convention:
    world = R(-th)(p - P) + P - t/16     and rotation about Q  =>  t/16 = (R(-th) - I)(Q - P) + t_off
Variants: rot_t False (job24 RTL as built) / True (translation rotated into the plane frame).
    python3 sc_obs.py roll|pan [rot_t 0|1] [max_windows]
"""
import sys, json, math, time
from pathlib import Path
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / 'results'))
import job6_golden as G
import job24_est as E

ds = sys.argv[1]
rot_t = len(sys.argv) > 2 and sys.argv[2] == '1'
maxw = int(sys.argv[3]) if len(sys.argv) > 3 else 10 ** 9
OUT = Path(__file__).resolve().parent / 'out'; OUT.mkdir(exist_ok=True)
P = (G.SW // 2, G.SH // 2)
B = G.EST_C_BASE[ds]
U = (1 << G.ABITS)
d = [11, 32, 32]                                         # th: roll preset spacing; t: 2 px in Q4 (job26 d_t)
thr = [int(30 * U / 360), 150 * 16, 150 * 16]
est = E.EstS('3d', G.SW, G.SH, P, d, B['min_ev'], S=3, key_thr=thr, key_w=4)
est.rot_t = rot_t
st = G.Stream(ds)
t0 = time.time()
nf = st.nf; f = 1; wi = 0; obs = []
while f < nf and wi < maxw:
    L = est.next_len()
    frames = list(range(f, min(f + L, nf)))
    evs = [st.frame(k) for k in frames]
    n = sum(len(e[0]) for e in evs)
    wev = (np.concatenate([e[0] for e in evs]), np.concatenate([e[1] for e in evs]),
           np.concatenate([np.full(len(e[0]), j, np.int8) for j, e in enumerate(evs)]))
    qc, per = est.begin_poses(len(frames)); est._applied = qc
    est.end(wi, frames, wev, n)
    r = est.trace[-1]
    obs.append(dict(w=wi, f0=frames[0], L=len(frames), n=int(n), br=r['branch'], q=list(map(int, est.q)), v=list(map(int, est.v))))
    wi += 1; f += len(frames)
    if wi % 50 == 0:
        print(ds, 'win', wi, 'frame', f, 'q', est.q, '%.0fs' % (time.time() - t0), flush=True)
tag = f'{ds}_rot{int(rot_t)}'
json.dump(dict(ds=ds, rot_t=rot_t, P=P, d=d, thr=thr, min_ev=B['min_ev'], obs=obs), open(OUT / f'obs_{tag}.json', 'w'))
print('saved', OUT / f'obs_{tag}.json', 'windows', len(obs), '%.0fs' % (time.time() - t0))
