"""key_w 4 vs 0 in the 3-DOF bootstrap: decision, pivot, distance to ECC centre, ECC error of published pivot (prereg 2026-11-17).
usage: python3 sc_nokey_eval.py roll|pan"""
import sys, math, time
import numpy as np
sys.path.insert(0, '/home/aiasic26911/redred_gate_ext/trans')
import sc_model as M
G = M.G; ds = sys.argv[1]; P = (480, 360); U = 1 << 14
st = G.Stream(ds); B = G.EST_C_BASE[ds]
for kw_ in (4, 0):
    t0 = time.time(); sc = M.SelfCal(G.SW, P, P, P, retry=True)
    thr = [int(30 * U / 360), 150 * 16, 150 * 16]
    est = M.EstSC('3d', G.SW, G.SH, P, [11, 32, 32], B['min_ev'], S=3, key_thr=thr, key_w=kw_, rot_t=True, sc=sc, wP=P, wO=P)
    nw, f = M.run(est, st)
    o = sc.out; pub = est.pub_win
    print(f'{ds} key_w={kw_} windows={nw} state={sc.st} result={M.RNAME[sc.res]} pub_win={pub} pivot={est.pivot} mode={est.mode} ({time.time()-t0:.0f}s)', flush=True)
    if o:
        Sd = max(o['Sd'], 1); ux, uy = 256 * o['Bx'] / Sd, 256 * o['By'] / Sd
        r2 = (o['Bx'] ** 2 + o['By'] ** 2) / (o['Sd'] * o['T']) if o['Sd'] * o['T'] else 0
        Q = (P[0] + ux, P[1] + uy)
        print(f'   Q_est={o.get("Qx_est")},{o.get("Qy_est")} u=({ux:.1f},{uy:.1f}) R={math.hypot(ux,uy):.1f} r2={r2:.3f} N={o["N"]} dist_to_ECC={math.hypot(Q[0]-469.7, Q[1]-417.2):.1f}px', flush=True)
        if ds == 'roll' and M.RNAME[sc.res] != 'none' and o.get('Qx_est') is not None:
            sys.path.insert(0, '/home/aiasic26911/selfcal_20261115/code/results')
            import job11_core as C, job24_est as E
            GT = G.EstGT(ds, 12); fe = G.DS[ds]['f_eval']; gq = np.array([GT.at(k)[0] for k in range(st.nf)]); m = np.arange(st.nf) >= fe
            e2 = E.make_prof(ds); e2.pivot = (int(o['Qx_est']), int(o['Qy_est'])); e2 = E.attach_gt_start(e2, ds)
            rs = C.run(ds, st, e2, rec_img=False); se = (rs['qf'] - gq) / GT.unit
            print(f'   ECC err of pivot ({o["Qx_est"]},{o["Qy_est"]}) = {np.abs(se[m]).mean():.3f} deg', flush=True)
