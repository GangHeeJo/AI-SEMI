"""job18: generic (any sensor size) float replica of the chip-S estimator family, for external benchmarks.

Same algorithm as the golden-model chain (job6 EstFOV -> job11 slow-only L8 -> job14 integer alpha-beta 2-class):
  * window = L frames (L=4; L=8 when slow: |v|/frame < d/4), events carry only their FRAME index (one timestamp
    per frame, like the NRV stream), intra-window warp by the tracked velocity,
  * two binary planes of S-px cells in the sensor FOV (prev = previous window in its own reference pose,
    cur = this window), score of a candidate = number of sampled events (<= M) that land on a set prev cell,
  * N candidates per DOF spaced d, parabolic refine, integer-style alpha-beta (Q4 gains, 2 confidence classes),
  * coasting (no update, planes kept) when a window has < min_ev events.
Pose model (image plane, world = first window):  world = R(th) (p - c) + c + (tx, ty).
DOF modes: 'roll' (th), 'pan' (tx), 'pan2' (tx, ty), '3d' (th, tx, ty; coordinate descent th -> tx -> ty).
This is NOT the bit-exact golden model (float, generic sensor); it reproduces its algorithm for comparison.
"""
import numpy as np, math

DOF_IDX = {'roll': [0], 'pan': [1], 'pan2': [1, 2], '3d': [0, 1, 2]}


def _rnd(a):
    return np.floor(a + 0.5)


class EstGeneric:
    def __init__(self, W, H, c, dof='3d', S=3, N=9, d=(0.01, 2.0, 2.0), M=2048, wk=1, min_ev=300, L=4, slowL=8,
                 slow_div=4, ab_hi=(15, 18), ab_lo=(14, 15), c_thr=0.09, sweeps=1, phase=0, tracker='ab'):
        self.W, self.H, self.c = W, H, np.asarray(c, float)
        self.dof = DOF_IDX[dof]
        self.S, self.N, self.d = S, N, np.asarray(d, float)
        self.M, self.wk, self.min_ev, self.Lb, self.slowL, self.slow_div = M, wk, min_ev, L, slowL, slow_div
        self.ab_hi, self.ab_lo, self.c_thr, self.sweeps, self.phase, self.tracker = ab_hi, ab_lo, c_thr, sweeps, phase, tracker
        self.CW, self.CH = -(-W // S), -(-H // S)
        self.prev = np.zeros(self.CW * self.CH, bool); self.cur = np.zeros_like(self.prev)
        self.q = np.zeros(3); self.v = np.zeros(3)       # v = pose change per frame
        self.q_ref = np.zeros(3); self.started = False; self.Lprev = L
        self.mem_bits = 2 * self.CW * self.CH
        self.cnt = dict(windows=0, coast=0, score_reads=0, map_writes=0, events=0)

    # ---------------------------------------------------------------- geometry
    def to_ref(self, x, y, qe, qr):
        """sensor event at pose qe -> its pixel position in a plane whose reference pose is qr."""
        c = self.c
        a = qe[0] - qr[0]
        ca, sa = math.cos(a), math.sin(a)
        dx, dy = x - c[0], y - c[1]
        tx, ty = qe[1] - qr[1], qe[2] - qr[2]
        cr, sr = math.cos(-qr[0]), math.sin(-qr[0])
        X = ca * dx - sa * dy + c[0] + (cr * tx - sr * ty)
        Y = sa * dx + ca * dy + c[1] + (sr * tx + cr * ty)
        return X, Y

    def cells(self, X, Y):
        cx = np.floor(X / self.S).astype(np.int64); cy = np.floor(Y / self.S).astype(np.int64)
        ok = (cx >= 0) & (cy >= 0) & (cx < self.CW) & (cy < self.CH)
        return np.where(ok, cy * self.CW + cx, -1)

    def window_len(self):
        if not self.started:
            return self.Lb
        slow = all(abs(self.v[k]) * self.slow_div < self.d[k] for k in self.dof)
        return self.slowL if (self.slowL and slow) else self.Lb

    # ---------------------------------------------------------------- per window
    def predict(self, L):
        """pose at the centre of the coming window (L frames) and per-frame pose offsets."""
        qc = self.q + self.v * (self.Lprev + L) / 2.0
        return qc

    def step(self, x, y, j, L):
        """x,y float sensor coords of the window's events, j = frame offset within window (0..L-1).
        Returns the per-frame poses actually applied (causal) for these frames."""
        self.cnt['windows'] += 1; n = len(x); self.cnt['events'] += n
        if not self.started:
            if n >= self.min_ev:
                self.started = True
                self._fill(x, y, j, L, self.q)
                self.prev, self.cur = self.cur, self.prev; self.q_ref = self.q.copy()
            self.Lprev = L
            return [self.q.copy() for _ in range(L)]
        qc = self.predict(L)
        applied = [qc + self.v * (jj - (L - 1) / 2.0) for jj in range(L)]
        if n < self.min_ev:
            self.cnt['coast'] += 1
            self.q = qc; self.Lprev = L
            return applied
        self._fill(x, y, j, L, qc)
        # samples
        stp = max(1, n // self.M)
        ph = (self.phase * 7919 + self.cnt['windows'] * 31) % stp if self.phase else 0
        sel = np.arange(ph, n, stp)[:self.M]
        sx, sy, sj = x[sel], y[sel], j[sel]
        z = qc.copy(); conf = np.zeros(3)
        for _ in range(self.sweeps):
            for k in self.dof:
                offs = self.d[k] * (np.arange(self.N) - (self.N - 1) // 2)
                sc = np.zeros(self.N)
                for i, o in enumerate(offs):
                    qq = z.copy(); qq[k] += o
                    tot = 0
                    for jj in np.unique(sj):
                        m = sj == jj
                        X, Y = self.to_ref(sx[m], sy[m], qq + self.v * (jj - (L - 1) / 2.0), self.q_ref)
                        cc = self.cells(X, Y); tot += int(self.prev[cc[cc >= 0]].sum())
                    sc[i] = tot
                self.cnt['score_reads'] += self.N * len(sel)
                b = int(np.argmax(sc)); best = z[k] + offs[b]
                if 0 < b < self.N - 1:
                    a_, b_, c_ = sc[b - 1], sc[b], sc[b + 1]; den = a_ - 2 * b_ + c_
                    if den < 0:
                        best += self.d[k] * (a_ - c_) / (2 * den)
                z[k] = best
                s = np.sort(sc); conf[k] = (s[-1] - np.median(s)) / s[-1] if s[-1] > 0 else 0.0
        # tracker
        if self.tracker == 'ab':
            for k in self.dof:
                r = z[k] - qc[k]
                a16, b16 = self.ab_hi if conf[k] >= self.c_thr else self.ab_lo
                self.q[k] = qc[k] + a16 * r / 16.0
                self.v[k] = self.v[k] + b16 * r / 16.0 / ((self.Lprev + L) / 2.0)
        else:                       # BASE (job6): q = z, v blended an/10
            for k in self.dof:
                self.v[k] = 0.5 * (z[k] - self.q[k]) / ((self.Lprev + L) / 2.0) + 0.5 * self.v[k]
                self.q[k] = z[k]
        for k in range(3):
            if k not in self.dof:
                self.q[k] = 0.0; self.v[k] = 0.0
        self.prev, self.cur = self.cur, self.prev; self.q_ref = self.q.copy(); self.Lprev = L
        return applied

    def _fill(self, x, y, j, L, qc):
        self.cur[:] = False
        sl = slice(None, None, self.wk)
        xs, ys, js = x[sl], y[sl], j[sl]
        for jj in np.unique(js):
            m = js == jj
            # event at pose qc + v*(jj-centre), plane reference = qc
            X, Y = self.to_ref(xs[m], ys[m], qc + self.v * (jj - (L - 1) / 2.0), qc)
            cc = self.cells(X, Y); self.cur[cc[cc >= 0]] = True
        self.cnt['map_writes'] += len(xs)


def run(est, x, y, f, f0=0, f1=None, log_every=0):
    """drive the estimator over frames [f0, f1). Returns per-window records (frame centre, q, v, applied pose)."""
    f1 = int(f[-1]) + 1 if f1 is None else f1
    fs = np.searchsorted(f, np.arange(f0, f1 + 9))       # event index of frame starts
    recs = []
    fr = f0
    while fr < f1:
        L = est.window_len()
        a, b = fs[fr - f0], fs[min(fr + L, f1) - f0]
        jj = (f[a:b] - fr).astype(np.int64)
        app = est.step(x[a:b], y[a:b], jj, L)
        recs.append((fr + (L - 1) / 2.0, L, b - a, *est.q, *est.v, *app[(L - 1) // 2]))
        fr += L
    return np.array(recs)
