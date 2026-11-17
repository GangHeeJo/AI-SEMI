"""integer bootstrap on synthetic scenes with per-element depth factor s~U[0.5,1.5] (prereg 2026-11-17)."""
import sys, math, statistics as S
import numpy as np
sys.path.insert(0, '/home/aiasic26911/redred_gate_ext/trans'); sys.path.insert(0, '/home/aiasic26911/redred_gate_ext/synth')
import sc_synth_int as B
Y = B.Y; W, H = Y.W, Y.H; C = Y.C

def gen_events_depth(scene, Q, seed, smin=0.5, smax=1.5):
    rng = np.random.default_rng(seed); Sg, D = scene; nseg = len(Sg)
    L = np.hypot(Sg[:, 2] - Sg[:, 0], Sg[:, 3] - Sg[:, 1]); w_el = np.concatenate([L, np.full(len(D), 12.0)]); w_el /= w_el.sum()
    sel = rng.uniform(smin, smax, len(w_el))                      # depth factor per element
    X, Yy, F = [], [], []
    def place(wx, wy, s, th):                                      # p = C + R(-th)(w-C) - s (R(-th)-I)(Q-C)
        rx, ry = Y.rot(wx - C[0], wy - C[1], -th); qx, qy = Y.rot(Q[0] - C[0], Q[1] - C[1], -th)
        return C[0] + rx - s * (qx - (Q[0] - C[0])), C[1] + ry - s * (qy - (Q[1] - C[1]))
    for fr in range(Y.NF):
        got, xs, ys = 0, [], []
        while got < Y.PER:
            m = max(12 * (Y.PER - got), 20000)
            el = rng.choice(len(w_el), m, p=w_el); seg = el < nseg
            sg = Sg[np.minimum(el, nseg - 1)]; u = rng.random(m)
            wx = np.where(seg, sg[:, 0] + u * (sg[:, 2] - sg[:, 0]), D[np.maximum(el - nseg, 0), 0])
            wy = np.where(seg, sg[:, 1] + u * (sg[:, 3] - sg[:, 1]), D[np.maximum(el - nseg, 0), 1])
            dx, dy = sg[:, 2] - sg[:, 0], sg[:, 3] - sg[:, 1]; Ln = np.maximum(np.hypot(dx, dy), 1e-9)
            nx, ny = -dy / Ln, dx / Ln; s = sel[el]
            tau = fr + rng.random(m); th = Y.theta(tau)
            px, py = place(wx, wy, s, th); th2 = Y.theta(tau + 0.25); px2, py2 = place(wx, wy, s, th2)
            vx, vy = (px2 - px) * 4, (py2 - py) * 4
            nxp, nyp = Y.rot(nx, ny, -th)
            acc = np.where(seg, np.minimum(np.abs(vx * nxp + vy * nyp) / 3.0, 1.0), 0.5)
            px = px + rng.normal(0, 0.6, m); py = py + rng.normal(0, 0.6, m)
            ok = (rng.random(m) < acc) & (px >= 0) & (px < W) & (py >= 0) & (py < H)
            xs.append(px[ok]); ys.append(py[ok]); got += int(ok.sum())
        px = np.concatenate(xs)[:Y.PER]; py = np.concatenate(ys)[:Y.PER]
        nb = int(0.03 * Y.PER); px[:nb] = rng.uniform(0, W, nb); py[:nb] = rng.uniform(0, H, nb)
        X.append(np.floor(px).astype(np.int32)); Yy.append(np.floor(py).astype(np.int32)); F.append(np.full(Y.PER, fr, np.int32))
    return np.concatenate(X), np.concatenate(Yy), np.concatenate(F)

rows = []; rr = []
for g in ('G1', 'G2', 'G3', 'G4'):
    for seed in (0, 1, 2):
        u_t = Y.GEOMS[g]; Q = (C[0] - u_t[0], C[1] - u_t[1]); Rt = math.hypot(*u_t)
        x, y, f = gen_events_depth(Y.make_scene(seed), Q, 100 + seed)
        est, sc = B.decide(x, y, f, 4); mir = False
        if est.q[0] < 0: est, sc = B.decide(W - 1 - x, y, f, 4); mir = True
        o = sc.out; res = B.M.RNAME[sc.res] if o else 'none'
        if o and res == 'accept':
            Qx = o['Qx_est']; Qx = W - 1 - Qx if mir else Qx; Qy = o['Qy_est']; R = math.hypot(o['ux'], o['uy'])
            rows.append((Qx - Q[0], Qy - Q[1])); rr.append(R / max(Rt, 1e-9))
            print(f'{g} s{seed} accept Q=({Qx},{Qy}) true=({Q[0]:.0f},{Q[1]:.0f}) err=({Qx-Q[0]:+.1f},{Qy-Q[1]:+.1f}) R={R:.1f} true R={Rt:.1f} ratio={rr[-1]:.2f}', flush=True)
        else:
            print(f'{g} s{seed} result={res}', flush=True)
ex = [a for a, _ in rows]; ey = [b for _, b in rows]
if rows:
    print(f'SUMMARY n={len(rows)} x mean {S.mean(ex):+.1f} median|.| {S.median(abs(v) for v in ex):.1f}; y mean {S.mean(ey):+.1f} median|.| {S.median(abs(v) for v in ey):.1f}; R ratio median {S.median(rr):.2f}, ratio<0.8: {sum(r<0.8 for r in rr)}/{len(rr)}')
