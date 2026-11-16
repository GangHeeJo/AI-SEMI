# ECC of integer roll-mode reference model vs pivot (provenance: job27_pivot_sens.py from earlier session, pivots changed).
# Reads ~/selfcal_20261115/code/results read-only; run from ~/redred_gate_ext/ecc.
import numpy as np, sys, time
sys.path.insert(0, '/home/aiasic26911/selfcal_20261115/code/results')
import job6_golden as G, job11_core as C, job24_est as E
ds = 'roll'; st = G.Stream(ds); GT = G.EstGT(ds, 12); fe = G.DS[ds]['f_eval']
gq = np.array([GT.at(k)[0] for k in range(st.nf)]); m = np.arange(st.nf) >= fe
def run(piv):
    est = E.make_prof(ds); est.pivot = piv; est = E.attach_gt_start(est, ds)
    rs = C.run(ds, st, est, rec_img=False)
    se = (rs['qf'] - gq) / GT.unit
    return np.abs(se[m]).mean(), np.abs(se[m] - np.median(se[m])).mean()
cands = {f'({x},{y})': (x, y) for x in range(465, 500, 5) for y in range(340, 440, 10)}
for name, p in cands.items():
    t = time.time(); a, c = run(p)
    print(f'{name:30s} pivot={p}  err_all={a:.3f} deg  err_cen={c:.3f}  ({time.time()-t:.0f}s)', flush=True)
