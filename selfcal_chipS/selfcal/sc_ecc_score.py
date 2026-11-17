"""ECC error (deg) of the integer roll model for given pivots (same metric as scripts/selfcal_ecc_pivot.py).
usage (from ~/redred_gate_ext/ecc/work): python3 sc_ecc_score.py x,y [x,y ...]"""
import sys, numpy as np
sys.path.insert(0, 'results')
import job6_golden as G, job11_core as C, job24_est as E
ds = 'roll'; st = G.Stream(ds); GT = G.EstGT(ds, 12); fe = G.DS[ds]['f_eval']
gq = np.array([GT.at(k)[0] for k in range(st.nf)]); m = np.arange(st.nf) >= fe
for a in sys.argv[1:]:
    p = tuple(int(v) for v in a.split(','))
    est = E.make_prof(ds); est.pivot = p; est = E.attach_gt_start(est, ds)
    rs = C.run(ds, st, est, rec_img=False); se = (rs['qf'] - gq) / GT.unit
    print(f'ECC err pivot {p} = {np.abs(se[m]).mean():.3f} deg', flush=True)
