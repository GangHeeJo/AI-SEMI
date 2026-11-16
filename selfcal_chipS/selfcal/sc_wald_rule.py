import json, math, sys
import numpy as np
D = json.load(open('/home/aiasic26911/selfcal_20261115/code/selfcal/out/obs_roll_rot1.json'))
P = D['P']; obs = [o for o in D['obs'] if o['br'] == 'score']
q = np.array([o['q'] for o in obs], float)
th = q[:, 0] * 2 * math.pi / 16384.0; t = q[:, 1:3] / 16.0
w = np.array([o['w'] for o in obs])
def A(a):
    c, s = math.cos(a), math.sin(a); return np.array([[c - 1, s], [-s, c - 1]])
def wald(k1):
    n = k1 + 1; h = n // 2
    As = np.array([A(a) for a in th[:n]])
    d = As[h:].mean(0) - As[:h].mean(0); dt = t[h:n].mean(0) - t[:h].mean(0)
    u = np.linalg.solve(d, dt); return u
def ls(k1):
    As = np.array([A(a) for a in th[:k1 + 1]]); Ac = As - As.mean(0); tc = t[:k1 + 1] - t[:k1 + 1].mean(0)
    S = np.einsum('kji,kjl->il', Ac, Ac); b = np.einsum('kji,kj->i', Ac, tc); return np.linalg.solve(S, b)
for label, wi in (('first trigger w127', 127), ('accepted w156', 156)):
    k1 = int(np.where(w <= wi)[0].max())
    for name, f in (('LS (current)', ls), ('Wald W', wald)):
        u = f(k1); print(f'{label:20s} k1={k1:4d} {name:13s} u=({u[0]:7.2f},{u[1]:7.2f}) Q=({P[0]+u[0]:7.2f},{P[1]+u[1]:7.2f}) R={np.hypot(*u):6.2f}')
