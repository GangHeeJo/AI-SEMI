"""Chip-S automatic pivot self-calibration: bit-exact integer reference model (the RTL spec).

Extends job24_est.EstS (unchanged import) with
  (1) rot_t   : in 3-DOF mode the translation difference is rotated into the plane frame (job24 TODO 'rot_t'),
                RTL-friendly form: base rotated per frame, candidate offsets rotated per window
                  dt = rot12(ref0, base) + (c-4) * rot12-floor(ref0, d e_k)
  (2) SelfCal : bootstrap FSM of job26 EstU._maybe_calibrate in exact integer arithmetic (see SPEC.md)
  (3) publication into roll mode (1 DOF about the estimated pivot Q) with a world-frame continuity offset.
Conventions (chip): world = R(-th)(p - P) + P - t/16, th in 2^-14 turn, t in Q4 px.
Rotation about Q  =>  t/16 = (R(-th) - I)(Q - P) + t_off,  u = Q - P.
"""
import sys, math
from pathlib import Path
import numpy as np
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / 'results'))
import job6_golden as G
import job24_est as E

AM = G.AMASK


def cord(a, F=12):
    return G.cordic_cs(int(a) & AM, F)


def rot12(ref, x, y):
    cr, sr = cord(ref, 12)
    return (cr * x - sr * y) >> 12, (sr * x + cr * y) >> 12


def sat16(v):
    return max(-32767, min(32767, v)), abs(v) > 32767


# ----------------------------------------------------------------------------------------------- self-calibration
ST_OFF, ST_BOOT, ST_ROT1, ST_GEN = 0, 1, 2, 3
R_NONE, R_ACCEPT, R_R2LOW, R_NOMOT, R_SING, R_RANGE, R_OVF, R_NOTRIG = range(8)
RNAME = ['none', 'accept', 'r2low', 'nomotion', 'singular', 'range', 'overflow', 'notrigger']


class SelfCal:
    NMAX = 1023
    R2N, R2D = 9, 10                                   # accept iff r2 >= 9/10  (job26 r2_min = 0.9)

    LVMAX = 3                                          # retry checkpoints at MTHR << 1..3

    def __init__(self, SW, P, wP, wO, retry=False):
        self.SW, self.P, self.wP, self.wO = SW, tuple(P), tuple(wP), tuple(wO)
        self.retry = retry; self.lv = 0
        self.KM = int(round(math.pi * SW))              # |th| W/2 in Q4 px per angle unit, Q10
        self.MTHR = (2 * SW * 16) // 5                  # 0.4 W in Q4 px
        self.TMIN = (16 * SW) // 100                    # 0.01 W in Q4 px
        self.st = ST_BOOT
        self.N = 0; self.Sa = self.Ss = self.Saa = self.Stx = self.Sty = self.Sbx = self.Sby = self.Stt = 0
        self.ovf = False; self.res = R_NONE; self.out = {}; self.acc_log = []

    def observe(self, q):
        """one 'score' window of the 3-DOF bootstrap; returns True when the fit must be evaluated now."""
        assert self.st == ST_BOOT
        cs, sn = cord(-q[0], 12)
        a, s = cs - 4096, sn
        tx, o1 = sat16(q[1]); ty, o2 = sat16(q[2])
        self.ovf |= o1 or o2
        self.N += 1; self.Sa += a; self.Ss += s; self.Saa += a * a + s * s
        self.Stx += tx; self.Sty += ty; self.Sbx += a * tx + s * ty; self.Sby += -s * tx + a * ty
        self.Stt += tx * tx + ty * ty
        m16 = abs(tx) + abs(ty) + ((min(abs(q[0]), 65535) * self.KM) >> 10)
        trig = m16 >= (self.MTHR << self.lv)
        self.acc_log.append([self.N, self.Sa, self.Ss, self.Saa, self.Stx, self.Sty, self.Sbx, self.Sby, self.Stt, m16, int(trig)])
        return trig or self.N >= self.NMAX, trig

    def solve(self, q, trig):
        N = self.N
        Sd = N * self.Saa - self.Sa * self.Sa - self.Ss * self.Ss
        T = N * self.Stt - self.Stx * self.Stx - self.Sty * self.Sty
        Bx = N * self.Sbx - self.Sa * self.Stx - self.Ss * self.Sty
        By = N * self.Sby + self.Ss * self.Stx - self.Sa * self.Sty
        B2 = Bx * Bx + By * By; D = Sd * T
        # width guards (must match the RTL register widths in SPEC.md)
        assert 0 <= Sd < 1 << 48 and 0 <= T < 1 << 52 and abs(Bx) < 1 << 52 and abs(By) < 1 << 52 and B2 <= D
        r2q10 = min(1023, (1024 * B2) // D) if D > 0 else 0
        ux = uy = 0
        if Sd > 0:
            ux = (256 * abs(Bx) + (Sd >> 1)) // Sd; ux = -ux if Bx < 0 else ux
            uy = (256 * abs(By) + (Sd >> 1)) // Sd; uy = -uy if By < 0 else uy
        Qx, Qy = self.P[0] + ux, self.P[1] + uy
        rng_ok = abs(ux) <= 4095 and abs(uy) <= 4095 and -2048 <= Qx <= 2047 and -2048 <= Qy <= 2047
        if not trig:
            res = R_NOTRIG
        elif self.ovf:
            res = R_OVF
        elif T < N * N * self.TMIN * self.TMIN:
            res = R_NOMOT
        elif Sd <= 0:
            res = R_SING
        elif self.R2D * B2 < self.R2N * D:
            res = R_R2LOW
        elif not rng_ok:
            res = R_RANGE
        else:
            res = R_ACCEPT
        O10 = (0, 0)
        if res == R_ACCEPT:
            cs, sn = cord(-q[0], 12)
            dx, dy = Qx - self.wP[0], Qy - self.wP[1]
            O10 = (((cs * dx - sn * dy) >> 2) + (self.wO[0] << 10) - (q[1] << 6),
                   ((sn * dx + cs * dy) >> 2) + (self.wO[1] << 10) - (q[2] << 6))
        self.res = res
        if self.retry and res in (R_NOMOT, R_SING) and self.lv < self.LVMAX and N < self.NMAX:
            self.lv += 1; self.st = ST_BOOT                # insufficient evidence: keep accumulating
        else:
            self.st = ST_ROT1 if res == R_ACCEPT else ST_GEN
        self.out = dict(res=res, N=N, Sd=Sd, T=T, Bx=Bx, By=By, r2q10=r2q10, ux=ux, uy=uy,
                        Qx=Qx if res == R_ACCEPT else 0, Qy=Qy if res == R_ACCEPT else 0, O10x=O10[0], O10y=O10[1],
                        Qx_est=Qx, Qy_est=Qy, lv=self.lv, final=self.st != ST_BOOT)
        return res == R_ACCEPT


# ----------------------------------------------------------------------------------------------- estimator
class EstSC(E.EstS):
    """EstS + rot_t (3-DOF) + self-calibration. sc=None -> legacy behaviour (rot_t selectable)."""

    def __init__(self, *a, rot_t=False, sc=None, wP=None, wO=None, **k):
        super().__init__(*a, **k)
        self.rot_t = rot_t or (sc is not None)
        self.sc = sc
        self.wP = tuple(wP if wP is not None else self.pivot); self.wO = tuple(wO if wO is not None else self.pivot)
        self.O10 = (self.wO[0] << 10, self.wO[1] << 10)
        self.pub_win = None

    # geometry with explicit translation (already in plane frame)
    def cells2(self, x, y, dth, dt):
        X = x.astype(np.int64); Y = y.astype(np.int64)
        if 0 in self.dof:
            cs, sn = cord(-dth, 12); self.cnt['cordic'] += 1
            px, py = self.pivot
            dx = X - px; dy = Y - py
            X = ((cs * dx - sn * dy) >> 12) + px; Y = ((sn * dx + cs * dy) >> 12) + py
        if 1 in self.dof:
            X = ((X << 4) - dt[0]) >> 4
        if 2 in self.dof:
            Y = ((Y << 4) - dt[1]) >> 4
        ok = (X >= 0) & (Y >= 0) & (X < self.SW) & (Y < self.SH)
        cx = (np.maximum(X, 0) * self.rec) >> self.sh; cy = (np.maximum(Y, 0) * self.rec) >> self.sh
        return np.where(ok, cy * self.W + cx, -1)

    def _offk(self, ref):
        """per-window rotated candidate steps: tx candidate c -> (c-4)*(kx0,ky0), ty candidate -> (c-4)*(kx1,ky1)."""
        cr, sr = cord(ref, 12)
        d1, d2 = self.d[1], self.d[2]
        return ((cr * d1) >> 12, (sr * d1) >> 12), (-((sr * d2) >> 12), (cr * d2) >> 12)

    def score(self, sx, sy, sj, qc, L):
        if not (self.mode == '3d' and self.rot_t):
            return super().score(sx, sy, sj, qc, L)
        cps = self.cand_poses(qc)
        sc = np.zeros(len(cps), np.int64); ks = np.zeros(len(cps), np.int64)
        refs = [('p', self.q_ref, self.prev)] + ([('k', self.q_key, self.kplane)] if self.kplane is not None else [])
        offs = {nm: self._offk(r[0]) for nm, r, _ in refs}
        for ci, (k, c, p) in enumerate(cps):
            for j in range(L):
                m = sj == j
                if not m.any():
                    continue
                w = self.warps(j, L)
                for nm, r, pl in refs:
                    dth = (qc[0] + (self.d[0] * (c - 4) if k == 0 else 0)) + w[0] - r[0]
                    bx, by = rot12(r[0], qc[1] + w[1] - r[1], qc[2] + w[2] - r[2])
                    if k == 1:
                        bx += (c - 4) * offs[nm][0][0]; by += (c - 4) * offs[nm][0][1]
                    elif k == 2:
                        bx += (c - 4) * offs[nm][1][0]; by += (c - 4) * offs[nm][1][1]
                    cc = self.cells2(sx[m], sy[m], dth, (bx, by))
                    hits = int(pl[cc[cc >= 0]].astype(np.int64).sum())
                    if nm == 'p':
                        sc[ci] += hits
                    else:
                        ks[ci] += hits
        self.cnt['score_reads'] += len(cps) * len(sx)
        return sc, ks, sc + ((self.key_w * ks) >> 2)

    def fill_cur(self, x, y, jj, L):
        if not (self.mode == '3d' and self.rot_t):
            return super().fill_cur(x, y, jj, L)
        self.cur[:] = 0
        sel = slice(None, None, self.wk)
        xs, ys, js = x[sel], y[sel], jj[sel]
        for j in range(L):
            m = js == j
            if m.any():
                w = self.warps(j, L)
                fx, fy = rot12(self._applied[0], w[1], w[2])
                cc = self.cells2(xs[m], ys[m], w[0], (fx, fy)); self.cur[cc[cc >= 0]] = 1
        self.cnt['map_writes'] += len(xs)

    # world frame params for one frame pose p (job23 port, F=10), 28-bit two's complement as the RTL
    def wparams(self, p):
        cs, sn = cord(-p[0], 10)
        Px, Py = self.wP
        if self.mode == '3d':
            dx, dy = p[1], p[2]
        else:
            dx = dy = 0
        bx = self.O10[0] - (cs * Px - sn * Py) - (dx << 6)
        by = self.O10[1] - (sn * Px + cs * Py) - (dy << 6)
        w28 = lambda v: ((v + (1 << 27)) & ((1 << 28) - 1)) - (1 << 27)
        return cs, sn, w28(bx), w28(by)

    def end(self, i, frames, ev, n):
        r = super().end(i, frames, ev, n)
        rec = self.trace[-1]
        sc = self.sc
        if sc is not None and sc.st == ST_BOOT and rec['branch'] == 'score':
            ev_now, trig = sc.observe(self.q)
            rec['sc_acc'] = list(sc.acc_log[-1])
            if ev_now:
                if sc.solve(self.q, trig):
                    self._publish(sc.out)
                rec["sc_out"] = dict(sc.out); self.sc_hist = getattr(self, "sc_hist", []) + [dict(sc.out, win=len(self.trace) - 1)]
                self.pub_win = len(self.trace) - 1
        return r

    def _publish(self, o):
        self.mode = 'roll'; self.dof = [0]
        self.pivot = (o['Qx'], o['Qy']); self.wP = (o['Qx'], o['Qy']); self.O10 = (o['O10x'], o['O10y'])
        self.v[1] = 0; self.v[2] = 0


def make_sc(ds, P=None, rot_t=True, selfcal=True, min_ev=None, retry=False):
    """self-calibrating chip config: 3-DOF bootstrap about P (sensor centre unless given), d = (11, 32, 32)."""
    B = G.EST_C_BASE[ds]
    P = tuple(P or (G.SW // 2, G.SH // 2))
    U = 1 << G.ABITS
    d = [11, 32, 32]
    thr = [int(30 * U / 360), 150 * 16, 150 * 16]
    sc = SelfCal(G.SW, P, P, P, retry=retry) if selfcal else None
    return EstSC('3d', G.SW, G.SH, P, d, min_ev or B['min_ev'], S=3, key_thr=thr, key_w=4, rot_t=rot_t, sc=sc, wP=P, wO=P)


def run(est, st, maxw=10 ** 9, fp_cb=None):
    nf = st.nf; f = 1; wi = 0
    while f < nf and wi < maxw:
        L = est.next_len()
        frames = list(range(f, min(f + L, nf)))
        evs = [st.frame(k) for k in frames]
        n = sum(len(e[0]) for e in evs)
        wev = (np.concatenate([e[0] for e in evs]), np.concatenate([e[1] for e in evs]),
               np.concatenate([np.full(len(e[0]), j, np.int8) for j, e in enumerate(evs)]))
        qc, per = est.begin_poses(len(frames)); est._applied = qc
        if fp_cb is not None:
            fp_cb(wi, frames, [est.wparams(p) for p in per])
        est.end(wi, frames, wev, n)
        wi += 1; f += len(frames)
    return wi, f
