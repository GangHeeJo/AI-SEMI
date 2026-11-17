"""d_t 32 vs 16 on real roll/pan and synthetic scenes (prereg 2026-11-17)."""
import sys, math, statistics as S
import numpy as np
sys.path.insert(0, '/home/aiasic26911/redred_gate_ext/trans'); sys.path.insert(0, '/home/aiasic26911/redred_gate_ext/synth')
import sc_synth_int as B, sc_synth_depth_lib as DL
M = B.M; G = M.G; Y = B.Y; W, H = Y.W, Y.H; U = 1 << 14
def real(ds, dt):
    P = (480, 360); st = G.Stream(ds); sc = M.SelfCal(G.SW, P, P, P, retry=True); Bb = G.EST_C_BASE[ds]
    est = M.EstSC('3d', G.SW, G.SH, P, [11 if ds == 'roll' else Bb['d'], dt, dt], Bb['min_ev'], S=3, key_thr=[int(30 * U / 360), 2400, 2400], key_w=4, rot_t=True, sc=sc, wP=P, wO=P)
    M.run(est, st); o = sc.out; res = M.RNAME[sc.res]
    msg = f'REAL {ds} d_t={dt} result={res} pub_win={est.pub_win}'
    if o: msg += f' Q=({o["Qx_est"]},{o["Qy_est"]}) R={math.hypot(o["ux"],o["uy"]):.1f} N={o["N"]} dist_to_ECC={math.hypot(o["Qx_est"]-469.7,o["Qy_est"]-417.2):.1f}'
    print(msg, flush=True)
for dt in (32, 16):
    real('roll', dt); real('pan', dt)
for tag, gen in (('single', lambda sc_, Q, sd: Y.gen_events(sc_, Q, sd)), ('depth', lambda sc_, Q, sd: DL.gen_events_depth(sc_, Q, sd))):
    for dt in (32, 16):
        ex, ey, n = [], [], 0
        for g in ('G1', 'G2', 'G3', 'G4'):
            for seed in (0, 1, 2):
                u_t = Y.GEOMS[g]; Q = (Y.C[0] - u_t[0], Y.C[1] - u_t[1]); x, y, f = gen(Y.make_scene(seed), Q, 100 + seed)
                est, sc = B.decide(x, y, f, 4, dt); mir = False
                if est.q[0] < 0: est, sc = B.decide(W - 1 - x, y, f, 4, dt); mir = True
                o = sc.out
                if o and M.RNAME[sc.res] == 'accept':
                    qx = o['Qx_est']; qx = W - 1 - qx if mir else qx; ex.append(qx - Q[0]); ey.append(o['Qy_est'] - Q[1]); n += 1
        print(f'SYNTH {tag} d_t={dt} accept {n}/12 x mean {S.mean(ex):+.1f} med|.| {S.median(abs(v) for v in ex):.1f} max|.| {max(abs(v) for v in ex):.0f}; y mean {S.mean(ey):+.1f} med|.| {S.median(abs(v) for v in ey):.1f} max|.| {max(abs(v) for v in ey):.0f}', flush=True)
