"""integer bootstrap (sc_model) on synthetic known-pivot scenes (prereg 2026-11-17).
usage: python3 sc_synth_int.py   (from ~/redred_gate_ext/trans; needs ~/redred_gate_ext/synth/{hyunsu_selfcal_synth.py,external})"""
import sys, math, statistics as S
import numpy as np
sys.path.insert(0, '/home/aiasic26911/redred_gate_ext/trans'); sys.path.insert(0, '/home/aiasic26911/redred_gate_ext/synth')
import sc_model as M
import hyunsu_selfcal_synth as Y
G = M.G; W, H = Y.W, Y.H; U = 1 << 14

class FakeStream:
    def __init__(s, x, y, f): s.nf = int(f.max()) + 1; s.idx = np.argsort(f, kind='stable'); s.x = x[s.idx]; s.y = y[s.idx]; s.b = np.searchsorted(f[s.idx], np.arange(s.nf + 1))
    def frame(s, k): a, b = s.b[k], s.b[k + 1]; return s.x[a:b].astype(np.int64), s.y[a:b].astype(np.int64)

def decide(x, y, f, key_w):
    P = (W // 2, H // 2); sc = M.SelfCal(G.SW, P, P, P, retry=True)
    est = M.EstSC('3d', G.SW, G.SH, P, [11, 32, 32], 2500, S=3, key_thr=[int(30 * U / 360), 2400, 2400], key_w=key_w, rot_t=True, sc=sc, wP=P, wO=P)
    M.run(est, FakeStream(x, y, f)); return est, sc

def main():
    rows = []
    for g in ('G1', 'G2', 'G3', 'G4'):
        for seed in (0, 1, 2):
            u_t = Y.GEOMS[g]; Q = (Y.C[0] - u_t[0], Y.C[1] - u_t[1])
            x, y, f = Y.gen_events(Y.make_scene(seed), Q, 100 + seed)
            for kw in (4, 0):
                est, sc = decide(x, y, f, kw); mir = False
                if est.q[0] < 0:
                    est, sc = decide(W - 1 - x, y, f, kw); mir = True
                o = sc.out; res = M.RNAME[sc.res] if o else 'none'
                if o and res == 'accept':
                    Qx = o['Qx_est']; Qx = W - 1 - Qx if mir else Qx; Qy = o['Qy_est']
                    ex, ey = Qx - Q[0], Qy - Q[1]; rows.append((g, seed, kw, ex, ey))
                    print(f'{g} s{seed} key_w={kw} mir={mir} accept Q=({Qx},{Qy}) true=({Q[0]:.0f},{Q[1]:.0f}) err=({ex:+.1f},{ey:+.1f}) R={math.hypot(o["ux"],o["uy"]):.1f} N={o["N"]}', flush=True)
                else:
                    print(f'{g} s{seed} key_w={kw} mir={mir} result={res} q0={est.q[0]}', flush=True)
    for kw in (4, 0):
        r = [(a, b) for (_, _, k, a, b) in rows if k == kw]
        if r:
            ex = [a for a, _ in r]; ey = [b for _, b in r]
            print(f'SUMMARY key_w={kw} n={len(r)} x: mean {S.mean(ex):+.1f} median|.| {S.median(abs(v) for v in ex):.1f} same-sign {max(sum(v>0 for v in ex), sum(v<0 for v in ex))}/{len(ex)}; y: mean {S.mean(ey):+.1f} median|.| {S.median(abs(v) for v in ey):.1f}')

if __name__ == '__main__':
    main()
