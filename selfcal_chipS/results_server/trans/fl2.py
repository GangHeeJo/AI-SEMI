import json, math, numpy as np
rec = np.load('/home/aiasic26911/redred_gate_ext/trans/float_rec.npy'); D = json.load(open('/home/aiasic26911/redred_gate_ext/trans/float_boot.json')); Q = np.array(D['boot_q'])
# align boot_q rows to rec rows by pose equality
rows = []; p = 0
for q in Q:
    while p < len(rec) and not np.allclose(rec[p, 3:6], q, atol=1e-9): p += 1
    rows.append(p); p += 1
rows = np.array(rows); print('aligned', len(rows), 'rows max', rows.max())
fend = rec[rows, 0] + 0.5 * rec[rows, 1]
Ee = np.load('/home/aiasic26911/redred_gate_ext/ecc/work/data/roll_ecc.npy'); k, ok, dth = Ee[:, 0], Ee[:, 3].astype(bool), Ee[:, 4]; thc = np.cumsum(np.where(ok, dth, 0.0))
idx = np.array([int(np.argmin(np.abs(k - v))) for v in fend]); sel = np.abs(k[idx] - fend) <= 4
th_f = np.degrees(Q[:, 0]); print('th slope vs ECC', np.polyfit(thc[idx][sel], th_f[sel], 1)[0], 'corr', np.corrcoef(thc[idx][sel], th_f[sel])[0, 1])
def A(a): c, s = math.cos(a), math.sin(a); return np.array([[c - 1, -s], [s, c - 1]])
for nm, uu in (('u_ecc float-conv (10.3,-57.2)', np.array([10.3, -57.2])), ('u_fit (6.5,-48.4)', np.array([6.475, -48.40]))):
    ang = np.radians(thc[idx][sel]) * np.sign(np.corrcoef(thc[idx][sel], th_f[sel])[0, 1])
    tm = np.array([A(a) @ uu for a in ang]); tc = Q[sel][:, 1:3]; tm -= tm.mean(0); tc = tc - tc.mean(0)
    print(f'FLOAT t slope vs {nm}: {(tm*tc).sum()/(tm*tm).sum():.3f} corr {np.corrcoef(tm.ravel(), tc.ravel())[0,1]:.3f}')
# per-window comparison with integer obs (score windows), by window end frame
I = [o for o in json.load(open('/home/aiasic26911/redred_gate_ext/trans/obs_dt32.json'))['obs'] if o['br'] == 'score']
fi = np.array([o['f0'] + o['L'] for o in I]); qi = np.array([o['q'] for o in I], float)
thi = np.degrees(qi[:, 0] * 2 * math.pi / 16384); ti = qi[:, 1:3] / 16
m = [(a, int(np.argmin(np.abs(fi - fend[a])))) for a in range(len(fend)) if np.min(np.abs(fi - fend[a])) <= 2]
a_, b_ = np.array([x[0] for x in m]), np.array([x[1] for x in m]); print('matched windows', len(m))
print('th float vs int: slope %.3f corr %.4f' % (np.polyfit(th_f[a_], thi[b_], 1)[0], np.corrcoef(th_f[a_], thi[b_])[0, 1]))
for c, nm in ((0, 'tx'), (1, 'ty')):
    print(f'{nm} float vs int: slope {np.polyfit(Q[a_, 1 + c], ti[b_, c], 1)[0]:.3f} corr {np.corrcoef(Q[a_, 1 + c], ti[b_, c])[0, 1]:.3f}  float range {Q[a_,1+c].min():.0f}..{Q[a_,1+c].max():.0f} int range {ti[b_,c].min():.0f}..{ti[b_,c].max():.0f}')
