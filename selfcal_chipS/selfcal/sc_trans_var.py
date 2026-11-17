"""Locate translation under-measurement: integer 3d model with translation spacing d_t varied (prereg 2026-11-17).
usage: python3 sc_trans_var.py D_T   (run from anywhere; reads code clone results read-only)"""
import sys, json, math, time
import numpy as np
sys.path.insert(0, '/home/aiasic26911/selfcal_20261115/code/results')
import job6_golden as G
import job24_est as E
dt = int(sys.argv[1]); ds = 'roll'; tag = sys.argv[2] if len(sys.argv) > 2 else f'dt{dt}'
kw = {a.split('=')[0]: int(a.split('=')[1]) for a in sys.argv[3:]}
P = (G.SW // 2, G.SH // 2); B = G.EST_C_BASE[ds]; U = 1 << G.ABITS
d = [11, dt, dt]; thr = [int(30 * U / 360), 150 * 16, 150 * 16]
est = E.EstS('3d', G.SW, G.SH, P, d, B['min_ev'], S=3, key_thr=thr, **{**dict(key_w=4), **kw}); est.rot_t = True
st = G.Stream(ds); nf = st.nf; f = 1; wi = 0; obs = []; t0 = time.time()
while f < nf:
    L = est.next_len(); frames = list(range(f, min(f + L, nf))); evs = [st.frame(k) for k in frames]
    n = sum(len(e[0]) for e in evs)
    wev = (np.concatenate([e[0] for e in evs]), np.concatenate([e[1] for e in evs]),
           np.concatenate([np.full(len(e[0]), j, np.int8) for j, e in enumerate(evs)]))
    qc, per = est.begin_poses(len(frames)); est._applied = qc; est.end(wi, frames, wev, n)
    r = est.trace[-1]
    obs.append(dict(w=wi, f0=frames[0], L=len(frames), n=int(n), br=r['branch'], q=list(map(int, est.q)), v=list(map(int, est.v))))
    wi += 1; f += len(frames)
    if wi % 50 == 0: print('win', wi, 'f', f, '%.0fs' % (time.time() - t0), flush=True)
json.dump(dict(dt=dt, obs=obs), open(f'/home/aiasic26911/redred_gate_ext/trans/obs_{tag}.json', 'w'))
# slope vs ECC model
Ee = np.load('/home/aiasic26911/redred_gate_ext/ecc/work/data/roll_ecc.npy')
k, ok, dth = Ee[:, 0], Ee[:, 3].astype(bool), Ee[:, 4]
thc = np.cumsum(np.where(ok, dth, 0.0)); so = [o for o in obs if o['br'] == 'score']
f0 = np.array([o['f0'] for o in so]); L = np.array([o['L'] for o in so]); q = np.array([o['q'] for o in so], float)
th_i = np.degrees(q[:, 0] * 2 * math.pi / 16384.0); t_i = q[:, 1:3] / 16.0
idx = np.array([int(np.argmin(np.abs(k - x))) for x in f0 + L]); sel = np.abs(k[idx] - (f0 + L)) <= 4
x = thc[idx][sel]; y = th_i[sel]; sgn = 1.0 if np.corrcoef(x, y)[0, 1] > 0 else -1.0
th_r = np.radians(sgn * thc[idx])
def Am(a): c, s = math.cos(a), math.sin(a); return np.array([[c - 1, s], [-s, c - 1]])
u = np.array([-10.3, 57.2]); As = np.array([Am(a) for a in th_r[sel]])
tm = np.einsum('kij,j->ki', As - As.mean(0), u); tc = t_i[sel] - t_i[sel].mean(0)
s = (tm * tm).sum() and (tm * tc).sum() / (tm * tm).sum(); r = np.corrcoef(tm.ravel(), tc.ravel())[0, 1]
print(f'RESULT {tag} d_t={dt} score_windows={len(so)} matched={int(sel.sum())} slope={s:.3f} corr={r:.3f} th_slope={np.polyfit(x,y,1)[0]:.3f}')
