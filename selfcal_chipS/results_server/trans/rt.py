import sys, math, numpy as np
sys.path.insert(0, '/home/aiasic26911/redred_gate_ext/trans')
import sc_model as M
G = M.G; P = (480, 360); U = 1 << 14; st = G.Stream('roll'); B = G.EST_C_BASE['roll']
for rot_t in (True, False):
    for kw in (4, 0):
        sc = M.SelfCal(G.SW, P, P, P, retry=True)
        est = M.EstSC('3d', G.SW, G.SH, P, [11, 32, 32], B['min_ev'], S=3, key_thr=[int(30 * U / 360), 2400, 2400], key_w=kw, rot_t=rot_t, sc=sc, wP=P, wO=P)
        M.run(est, st); o = sc.out; r = M.RNAME[sc.res]
        print(f'rot_t={rot_t} key_w={kw} result={r}' + (f' Q=({o["Qx_est"]},{o["Qy_est"]}) R={math.hypot(o["ux"],o["uy"]):.1f} r2q10={o["r2q10"]} N={o["N"]} dist_ECC={math.hypot(o["Qx_est"]-469.7,o["Qy_est"]-417.2):.1f}' if o else ''), flush=True)
