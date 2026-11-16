"""selfcal step B1: float analysis of the bootstrap pivot fit on recorded integer observations (chip convention).
    t/16 = (R(-th) - I) u + t_off,   u = Q - P  (pixels),  th = q0 * 2pi / 2^14
Reports the trigger window (job26 rule m >= 0.4 W, m = |tx|+|ty| + |th| W/2 in px), centred/uncentred r2, u, Q,
and the sensitivity of r2 to the window set.
    python3 sc_fit.py out/obs_roll_rot1.json
"""
import sys, json, math
import numpy as np

D = json.load(open(sys.argv[1]))
W = 960
P = D['P']
obs = [o for o in D['obs'] if o["br"] == "score"]
q = np.array([o['q'] for o in obs], float)
th = q[:, 0] * 2 * math.pi / 16384.0
t = q[:, 1:3] / 16.0
m = np.abs(t[:, 0]) + np.abs(t[:, 1]) + np.abs(th) * W / 2
ktr = int(np.argmax(m >= 0.4 * W)) if (m >= 0.4 * W).any() else None


def A(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c - 1, s], [-s, c - 1]])


def fit(k1, centred=True, k0=0):
    th_, t_ = th[k0:k1 + 1], t[k0:k1 + 1]
    As = np.array([A(a) for a in th_])
    if centred:
        Ac = As - As.mean(0); tc = t_ - t_.mean(0)
    else:
        Ac, tc = As, t_
    S = np.einsum('kji,kjl->il', Ac, Ac); b = np.einsum('kji,kj->i', Ac, tc)
    tot = float((tc ** 2).sum())
    u = np.linalg.solve(S, b)
    res = float(((tc - np.einsum('kij,j->ki', Ac, u)) ** 2).sum())
    return dict(n=len(th_), u=u, Q=(P[0] + u[0], P[1] + u[1]), R=float(np.hypot(*u)), r2=1 - res / tot,
                t_std=math.sqrt(tot / len(th_)), detS=float(np.linalg.det(S)), cond=float(np.linalg.cond(S)),
                th_span_deg=float(np.degrees(th_.max() - th_.min())))


print(sys.argv[1], 'obs windows', len(obs), 'trigger idx', ktr, 'window', obs[ktr]['w'] if ktr is not None else None)
if ktr is not None:
    for c in (True, False):
        f = fit(ktr, c)
        print(' centred' if c else ' uncentred', {k: (np.round(v, 3).tolist() if isinstance(v, np.ndarray) else (round(v, 4) if isinstance(v, float) else v)) for k, v in f.items()})
    print(' r2 vs end window (centred):')
    for k1 in sorted(set([max(3, ktr // 4), ktr // 2, 3 * ktr // 4, ktr, ktr + 10, ktr + 25, ktr + 50, len(obs) - 1])):
        if 3 <= k1 < len(obs):
            f = fit(k1)
            print('  k1=%4d n=%4d th_span=%7.2f deg  Q=(%8.1f,%8.1f) R=%9.1f r2=%.4f t_std=%.1f cond=%.1f' % (
                k1, f['n'], f['th_span_deg'], f['Q'][0], f['Q'][1], f['R'], f['r2'], f['t_std'], f['cond']))
