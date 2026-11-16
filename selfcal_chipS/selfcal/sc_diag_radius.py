import json, math
import numpy as np
D = json.load(open('/home/aiasic26911/selfcal_20261115/code/selfcal/out/obs_roll_rot1.json'))
P = D['P']; obs = [o for o in D['obs'] if o['br'] == 'score']
E = np.load('/home/aiasic26911/redred_gate_ext/ecc/work/data/roll_ecc.npy')
k, t_us, n, ok, dth = E[:, 0], E[:, 1], E[:, 2], E[:, 3].astype(bool), E[:, 4]
th_ecc_cum = np.cumsum(np.where(ok, dth, 0.0))        # deg, cumulative at ECC window k (end of window)
f0 = np.array([o['f0'] for o in obs]); L = np.array([o['L'] for o in obs])
q = np.array([o['q'] for o in obs], float)
th_chip = np.degrees(q[:, 0] * 2 * math.pi / 16384.0); t_chip = q[:, 1:3] / 16.0
# match chip window (end frame f0+L) to ECC window k (frame index)
fend = f0 + L
idx = np.array([int(np.argmin(np.abs(k - f))) for f in fend])
th_e = th_ecc_cum[idx]
sel = np.abs(k[idx] - fend) <= 4
print('score windows', len(obs), 'matched', int(sel.sum()))
# H1
x = th_e[sel]; y = th_chip[sel]
for name, (xx, yy) in {'all': (x, y)}.items():
    A = np.vstack([xx, np.ones_like(xx)]).T; sl, ic = np.linalg.lstsq(A, yy, rcond=None)[0]
    r = np.corrcoef(xx, yy)[0, 1]
    print(f'H1 th_chip = {sl:.3f} * th_ecc + {ic:.2f}  corr {r:.4f}  resid std {np.std(yy - (sl*xx+ic)):.2f} deg  th_ecc span {np.ptp(xx):.0f} deg')
# H2/H3 : use th_ecc in rad (sign from corr)
sgn = 1.0 if np.corrcoef(x, y)[0, 1] > 0 else -1.0
th_r = np.radians(sgn * th_e)
def Am(a):
    c, s = math.cos(a), math.sin(a); return np.array([[c - 1, s], [-s, c - 1]])
def fit_u(thr, tt, m):
    As = np.array([Am(a) for a in thr[m]]); Ac = As - As.mean(0); tc = tt[m] - tt[m].mean(0)
    S = np.einsum('kji,kjl->il', Ac, Ac); b = np.einsum('kji,kj->i', Ac, tc); u = np.linalg.solve(S, b)
    pred = np.einsum('kij,j->ki', Ac, u); r2 = 1 - ((tc - pred) ** 2).sum() / (tc ** 2).sum(); return u, r2
for lim, nm in ((59, 'first-trigger set'), (88, 'accepted set'), (len(obs) - 1, 'all')):
    m = np.zeros(len(obs), bool); m[:lim + 1] = True; m &= sel
    u_th, r2 = fit_u(th_r, t_chip, m)
    print(f'H3 [{nm}] th_ecc + t_chip: u=({u_th[0]:.1f},{u_th[1]:.1f}) R={np.hypot(*u_th):.1f} r2={r2:.3f}   (chip th: ', end='')
    u_c, r2c = fit_u(np.radians(th_chip), t_chip, m); print(f'u=({u_c[0]:.1f},{u_c[1]:.1f}) R={np.hypot(*u_c):.1f} r2={r2c:.3f})')
# H2
u_f = np.array([-5.4, 54.5])
m = sel.copy()
As = np.array([Am(a) for a in th_r[m]]); tm = np.einsum('kij,j->ki', As - As.mean(0), u_f); tc = t_chip[m] - t_chip[m].mean(0)
sl = (tm * tc).sum() / (tm * tm).sum(); r = np.corrcoef(tm.ravel(), tc.ravel())[0, 1]
print(f'H2 t_chip = {sl:.3f} * t_model(th_ecc,u_float) corr {r:.3f}')
