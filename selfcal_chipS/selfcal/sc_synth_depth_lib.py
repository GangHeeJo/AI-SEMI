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

