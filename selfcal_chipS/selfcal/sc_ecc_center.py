import numpy as np, math
E = np.load('/home/aiasic26911/redred_gate_ext/ecc/work/data/roll_ecc.npy')
k, t_us, n, ok, dth, tx, ty, cc = E.T; ok = ok.astype(bool)
m = ok & (np.abs(dth) > 0.8) & (cc > 0.9)
print('windows used', int(m.sum()), 'of', len(E))
for sgn in (+1, -1):
    Qs = []
    for d, a, b in zip(dth[m], tx[m], ty[m]):
        th = math.radians(sgn * d); c, s = math.cos(th), math.sin(th)
        M = np.array([[1 - c, s], [-s, 1 - c]])      # (I - R) with R=[[c,-s],[s,c]]
        Qs.append(np.linalg.solve(M, [a, b]))
    Qs = np.array(Qs)
    med = np.median(Qs, 0); mad = np.median(np.abs(Qs - med), 0)
    print(f'sign {sgn:+d}: Q median ({med[0]:.1f},{med[1]:.1f}) MAD ({mad[0]:.1f},{mad[1]:.1f})  p25 ({np.percentile(Qs[:,0],25):.0f},{np.percentile(Qs[:,1],25):.0f}) p75 ({np.percentile(Qs[:,0],75):.0f},{np.percentile(Qs[:,1],75):.0f})')
