"""job26: self-calibrating, world-anchored generic chip-S estimator (float replica, algorithm-equivalent to job24 EstS).

One estimator class for all six sequences (professor roll/pan 960x720, UZH shapes/boxes/poster/dynamic 240x180).
Nothing below is tuned per recording: every size-dependent number is derived from the sensor dimensions
(S=3 px cells, d_t = 2 px = 2/3 cell, d_th = d_t / r_corner) or from the first windows of the stream (min_ev).

Pose model (image plane, world = first window):   world = R(th) (p - c) + c + t        (c = sensor centre)

MODES
  '3d'   : th, tx, ty searched (coordinate-free Jacobi scoring like job18/job24 3d).
  'rot1' : ONE DOF, rotation th about a pivot Q (possibly very far away):
               t(th) = (R(th) - I)(c - Q) + t_off .
           This reparameterises the professor pan 'KA/KX/KY/BY16' coupling:  the sensor orbits a rod, so the image
           motion is a rotation about the rod's image Q (pan: |c-Q| ~ 21 000 px, roll: Q ~ c).  Instead of four fitted
           constants there is one 2-vector u = c - Q (or the scalar orbit radius R = |u|).

SELF-CALIBRATION (bootstrap FSM, identical for every sequence)
  phase 0  collect the first 12 non-empty windows -> min_ev = 0.3 * median(n)
  phase 1  run '3d' until the pose has moved an edge displacement m = |t| + |th| W/2 >= boot_frac * W
  phase 2  fit u = sum A_k^T t_k / sum |A_k|^2 (A_k = R(th_k) - I): two accumulators + one divide;
           explained fraction r2 = 1 - sum |t_k - A_k u|^2 / sum(|t_k|^2 + (th_k W/2)^2).
           r2 >= r2_min  -> freeze 'rot1' with u, d_th = d_t / max(|u|, r_corner)   else stay '3d'.

DUPLICATION FIX (optional, all 1-bit planes, same datapath as the keyframe plane)
  world plane  : 1-bit map of everything registered so far in the WORLD frame (canvas 3W x 3H); the score of a
                 candidate adds  w_world * hits on the world plane, so a window is matched against the accumulated
                 world, not only against the previous window  (events are written to the world only when the
                 window's peak confidence >= conf_write).
  loop closure : when the track is 'lost' (coast or best-score fraction < f_lost for n_lost windows) a wide
                 translation/rotation grid is scored against the world plane + keyframe bank; if the best cell beats the
                 predicted pose by `lc_margin` the pose snaps to it (re-attach at the SAME world position instead of
                 starting a second copy).
"""
import numpy as np, math, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import job18_est as E


class EstU(E.EstGeneric):
    def __init__(self, W, H, c, S=3, N=9, M=2048, wk=1, d_t=2.0, L=4, slowL=8, slow_div=4, tracker='base',
                 min_ev=None, min_ev_frac=0.3, auto_boot=True, boot_frac=0.4, r2_min=0.9, rot1=None, phase=0,
                 key=None, world=None, lc=None, force_mode=None, monitor=True):
        rc = max(math.hypot(x - c[0], y - c[1]) for x in (0, W) for y in (0, H))
        self.rcorner = rc
        super().__init__(W, H, c, dof='3d', S=S, N=N, d=(d_t / rc, d_t, d_t), M=M, wk=wk, min_ev=min_ev or 10 ** 9,
                         L=L, slowL=slowL, slow_div=slow_div, tracker=tracker, phase=phase)
        self.d_t = d_t
        self.min_ev_frac = min_ev_frac
        self.auto_min = min_ev is None
        self.n_hist = []
        self.boot = auto_boot
        self.boot_frac, self.r2_min = boot_frac, r2_min
        self.mode = '3d'
        self.u = np.zeros(2); self.t_off = np.zeros(2)
        self.boot_q = []
        self.calib = None
        self.vth_only = False
        if rot1 is not None:                           # preset u (frozen / refit experiments)
            self._enter_rot1(np.asarray(rot1, float)); self.boot = False
        if force_mode == '3d':
            self.boot = False
        self.key = key
        self.kplane = None; self.q_key = np.zeros(3); self.bank = []
        self.world_cfg = world
        self.lc = lc
        self.lost = 0
        self.mon_every = 8; self.mon_margin = 0.05; self.viol = []; self.monitor = monitor
        self.cnt.update(mon_checks=0, mon_fallback=0, key_reads=0, key_swaps=0, world_reads=0, lc_tries=0, lc_snaps=0, world_writes=0)
        self.mem_bits = 2 * self.CW * self.CH
        if key:
            self.mem_bits += key.get('K', 1) * self.CW * self.CH
        if world:
            self.padx, self.pady = int(world.get('pad', 1.0) * W), int(world.get('pad', 1.0) * H)
            self.WW = -(-(W + 2 * self.padx) // S); self.WH = -(-(H + 2 * self.pady) // S)
            self.wplane = np.zeros(self.WW * self.WH, np.uint8); self.wmin = int(world.get('minc', 1)); self.wcap = int(world.get('cap', 1))
            self.mem_bits += self.WW * self.WH
        self.mode_log = []
        self.rot1_calibrated = rot1 is None

    # ------------------------------------------------------------------ pose models
    def _A(self, th):
        ca, sa = math.cos(th), math.sin(th)
        return np.array([[ca - 1, -sa], [sa, ca - 1]])

    def full(self, th):
        """full pose from the single rotation DOF (rot1)."""
        return np.array([th, *(self._A(th) @ self.u + self.t_off)])

    def _enter_rot1(self, u):
        self.mode = 'rot1'; self.dof = [0]; self.u = u
        r = max(float(np.hypot(*u)), self.rcorner)
        self.d = np.array([self.d_t / r, self.d_t, self.d_t])
        self.t_off = np.zeros(2)
        self.t_off = self.q[1:3] - self._A(self.q[0]) @ self.u        # continuity at the switch
        self.v[1:] = 0

    def pose_at(self, thc, vth, s, off=0.0):
        """pose of a frame at offset s from the window centre (rot1)."""
        return self.full(thc + off + vth * s)

    # ------------------------------------------------------------------ scoring helpers
    def _hits(self, plane, sx, sy, sj, qfun, q_ref, L, ref_zero=False):
        tot = 0
        for jj in np.unique(sj):
            m = sj == jj
            X, Y = self.to_ref(sx[m], sy[m], qfun(jj), q_ref)
            cc = self.cells(X, Y); tot += int(plane[cc[cc >= 0]].sum())
        return tot

    def _wcells(self, X, Y):
        cx = np.floor((X + self.padx) / self.S).astype(np.int64); cy = np.floor((Y + self.pady) / self.S).astype(np.int64)
        ok = (cx >= 0) & (cy >= 0) & (cx < self.WW) & (cy < self.WH)
        return np.where(ok, cy * self.WW + cx, -1)

    def _world_hits(self, sx, sy, sj, qfun):
        tot = 0
        for jj in np.unique(sj):
            m = sj == jj
            X, Y = self.to_ref(sx[m], sy[m], qfun(jj), np.zeros(3))
            cc = self._wcells(X, Y); tot += int((self.wplane[cc[cc >= 0]] >= self.wmin).sum())
        return tot

    def _world_write(self, x, y, j, L, qf):
        sl = slice(None, None, max(1, self.wk * self.world_cfg.get('wstep', 1)))
        xs, ys, js = x[sl], y[sl], j[sl]
        allc = []
        for jj in np.unique(js):
            m = js == jj
            X, Y = self.to_ref(xs[m], ys[m], qf(jj), np.zeros(3))
            cc = self._wcells(X, Y); allc.append(cc[cc >= 0])
        if allc:
            cc = np.unique(np.concatenate(allc))          # one increment per cell per window
            self.wplane[cc] = np.minimum(self.wplane[cc] + 1, self.wcap)
        self.cnt['world_writes'] += len(xs)

    # ------------------------------------------------------------------ key bank (job21_uzh semantics)
    def _key_maybe(self):
        k = self.key
        if not k:
            return
        th, t = k['th'], k['t']
        d = [max(abs(self.q_ref[0] - b[1][0]) / th, abs(self.q_ref[1] - b[1][1]) / t, abs(self.q_ref[2] - b[1][2]) / t) for b in self.bank]
        if not d or min(d) > 1.0:
            if len(self.bank) >= k.get('K', 1):
                self.bank.pop(int(np.argmin([b[2] for b in self.bank])))
            self.bank.append([self.prev.copy(), self.q_ref.copy(), self.cnt['windows']]); self.cnt['key_swaps'] += 1
        if self.kplane is None:
            self.kplane, self.q_key = self.bank[-1][0], self.bank[-1][1]

    def _pick_key(self, qc):
        if self.key and self.bank:
            dist = [abs(qc[0] - b[1][0]) * 120 + abs(qc[1] - b[1][1]) + abs(qc[2] - b[1][2]) for b in self.bank]
            kb = int(np.argmin(dist)); self.kplane, self.q_key = self.bank[kb][0], self.bank[kb][1]
            self.bank[kb][2] = self.cnt['windows']

    def _fill2(self, x, y, j, L, qc, qfun0):
        self.cur[:] = False
        sl = slice(None, None, self.wk)
        xs, ys, js = x[sl], y[sl], j[sl]
        for jj in np.unique(js):
            m = js == jj
            qe = qfun0(jj) if qfun0 is not None else qc + self.v * (jj - (L - 1) / 2.0)
            X, Y = self.to_ref(xs[m], ys[m], qe, qc)
            cc = self.cells(X, Y); self.cur[cc[cc >= 0]] = True
        self.cnt['map_writes'] += len(xs)

    # ------------------------------------------------------------------ one window
    def step(self, x, y, j, L):
        self.cnt['windows'] += 1; n = len(x); self.cnt['events'] += n
        # ---- phase 0: event-density calibration
        if self.auto_min and self.min_ev >= 10 ** 9:
            if n >= 50:
                self.n_hist.append(n)
            if len(self.n_hist) >= 12:
                self.min_ev = max(50, int(self.min_ev_frac * float(np.median(self.n_hist)))); self.calib = dict(min_ev=self.min_ev)
            self.Lprev = L
            return [self.q.copy() for _ in range(L)]
        if not self.started:
            if n >= self.min_ev:
                self.started = True
                self._fill(x, y, j, L, self.q)
                self.prev, self.cur = self.cur, self.prev; self.q_ref = self.q.copy()
                self._key_maybe()
                if self.world_cfg:
                    self._world_write(x, y, j, L, lambda jj: self.q)
            self.Lprev = L
            return [self.q.copy() for _ in range(L)]
        rot1 = self.mode == 'rot1'
        if rot1:
            thc = self.q[0] + self.v[0] * (self.Lprev + L) / 2.0
            vth = self.v[0]
            qc = self.full(thc)
            qfun0 = lambda jj, off=0.0: self.pose_at(thc, vth, jj - (L - 1) / 2.0, off)
        else:
            qc = self.predict(L)
            qfun0 = None
        applied = [qfun0(jj) if rot1 else qc + self.v * (jj - (L - 1) / 2.0) for jj in range(L)]
        if n < self.min_ev:
            self.cnt['coast'] += 1; self.lost += 1
            if rot1:
                self.q = qc
            else:
                self.q = qc
            self.Lprev = L
            return applied
        self._fill2(x, y, j, L, qc, qfun0)
        stp = max(1, n // self.M)
        ph = (self.phase * 7919 + self.cnt['windows'] * 31) % stp if self.phase else 0
        sel = np.arange(ph, n, stp)[:self.M]
        sx, sy, sj = x[sel], y[sel], j[sel]
        self._pick_key(qc)
        kw = self.key['w'] / 4.0 if self.key else 0.0
        ww = self.world_cfg['w'] / 4.0 if self.world_cfg else 0.0
        z = qc.copy(); conf = np.zeros(3)
        score_cache = {}

        def total(qfun, ref=None):
            t = self._hits(self.prev, sx, sy, sj, qfun, self.q_ref, L)
            if self.kplane is not None and kw:
                t += kw * self._hits(self.kplane, sx, sy, sj, qfun, self.q_key, L); self.cnt['key_reads'] += len(sx)
            if ww:
                t += ww * self._world_hits(sx, sy, sj, qfun); self.cnt['world_reads'] += len(sx)
            return t

        best_frac = 1.0
        for k in self.dof:
            offs = self.d[k] * (np.arange(self.N) - (self.N - 1) // 2)
            sc = np.zeros(self.N)
            for i, o in enumerate(offs):
                if rot1:
                    qfun = lambda jj, o=o: self.pose_at(thc, vth, jj - (L - 1) / 2.0, o)
                else:
                    qq = z.copy(); qq[k] += o
                    qfun = lambda jj, qq=qq: qq + self.v * (jj - (L - 1) / 2.0)
                sc[i] = total(qfun)
            self.cnt['score_reads'] += self.N * len(sel)
            b = int(np.argmax(sc)); best = (thc if rot1 else z[k]) + offs[b]
            if 0 < b < self.N - 1:
                a_, b_, c_ = sc[b - 1], sc[b], sc[b + 1]; den = a_ - 2 * b_ + c_
                if den < 0:
                    best += self.d[k] * (a_ - c_) / (2 * den)
            if rot1:
                thc_new = best
            else:
                z[k] = best
            s = np.sort(sc); conf[k] = (s[-1] - np.median(s)) / s[-1] if s[-1] > 0 else 0.0
            best_frac = s[-1] / max(1.0, float(len(sel)))
        if rot1:
            z = self.full(thc_new)
            if self.monitor and self.rot1_calibrated and self.cnt['windows'] % self.mon_every == 0:
                self._monitor(total, thc_new, vth, L)
        # ---- loop closure: re-attach to the world when the track is weak
        weak = best_frac < (self.lc['f_lost'] if self.lc else 0.0) or conf[self.dof[0]] < (self.lc['c_lost'] if self.lc else -1)
        self.lost = self.lost + 1 if weak else 0
        if self.lc and self.world_cfg and self.lost >= self.lc['n_lost']:
            z = self._loop_close(sx, sy, sj, L, z, qc, thc if rot1 else None, vth if rot1 else None)
            if rot1:
                thc_new = z[0]
        # ---- tracker
        if rot1:
            r = thc_new - thc
            if self.tracker == 'ab':
                a16, b16 = self.ab_hi if conf[0] >= self.c_thr else self.ab_lo
                thq = thc + a16 * r / 16.0
                self.v[0] = self.v[0] + b16 * r / 16.0 / ((self.Lprev + L) / 2.0)
            else:
                self.v[0] = 0.5 * (thc_new - self.q[0]) / ((self.Lprev + L) / 2.0) + 0.5 * self.v[0]
                thq = thc_new
            self.q = self.full(thq)
        else:
            if self.tracker == 'ab':
                for k in self.dof:
                    r = z[k] - qc[k]
                    a16, b16 = self.ab_hi if conf[k] >= self.c_thr else self.ab_lo
                    self.q[k] = qc[k] + a16 * r / 16.0
                    self.v[k] = self.v[k] + b16 * r / 16.0 / ((self.Lprev + L) / 2.0)
            else:
                for k in self.dof:
                    self.v[k] = 0.5 * (z[k] - self.q[k]) / ((self.Lprev + L) / 2.0) + 0.5 * self.v[k]
                    self.q[k] = z[k]
        # ---- world write (gated by confidence)
        if self.world_cfg and conf[self.dof[0]] >= self.world_cfg.get('conf_write', 0.0) and self.lost == 0:
            if rot1:
                qf = lambda jj: self.pose_at(self.q[0], self.v[0], jj - (L - 1) / 2.0)
            else:
                qf = lambda jj: self.q + self.v * (jj - (L - 1) / 2.0)
            self._world_write(x, y, j, L, qf)
        self.prev, self.cur = self.cur, self.prev; self.q_ref = self.q.copy(); self.Lprev = L
        self._key_maybe()
        # ---- bootstrap FSM
        if self.boot and self.mode == '3d':
            self.boot_q.append(self.q.copy())
            self._maybe_calibrate()
        return applied

    # ------------------------------------------------------------------ bootstrap fit
    def _maybe_calibrate(self):
        Q = np.array(self.boot_q)
        m = np.abs(Q[:, 1]) + np.abs(Q[:, 2]) + np.abs(Q[:, 0]) * self.W / 2.0
        if m.max() < self.boot_frac * self.W:
            return
        th, t = Q[:, 0], Q[:, 1:3]
        # centred least squares (model t = t_off + A(th) u):  2x2 normal equations, 2 accumulators + one 2x2 solve
        As = np.array([self._A(a) for a in th]); Ac = As - As.mean(0); tc = t - t.mean(0)
        S = np.einsum('kji,kjl->il', Ac, Ac); b_ = np.einsum('kji,kj->i', Ac, tc)
        tot = float((tc ** 2).sum())
        ok = tot / len(th) >= (0.01 * self.W) ** 2 and abs(np.linalg.det(S)) > 1e-12
        u = np.linalg.solve(S, b_) if ok else np.zeros(2)
        res = float(((tc - np.einsum('kij,j->ki', Ac, u)) ** 2).sum()) if ok else tot
        r2 = 1.0 - res / tot if tot > 0 else 0.0
        self.calib = dict(self.calib or {}, u=u.tolist(), r2=float(r2), R=float(np.hypot(*u)), windows=len(Q), t_std=float(np.sqrt(tot / len(th))))
        self.boot = False
        if ok and r2 >= self.r2_min:
            self._enter_rot1(u); self.calib['mode'] = 'rot1'
        else:
            self.calib['mode'] = '3d'
        self.mode_log.append((self.cnt['windows'], self.mode))

    # ------------------------------------------------------------------ model-validity monitor (rot1 -> 3d fallback)
    def _monitor(self, total, thc_new, vth, L):
        offs = self.d_t * np.arange(-2, 3)
        viol = 0
        for k in (1, 2):
            sc = []
            for o in offs:
                def qf(jj, o=o, k=k):
                    p = self.pose_at(thc_new, vth, jj - (L - 1) / 2.0).copy(); p[k] += o; return p
                sc.append(total(qf))
            sc = np.array(sc); b = int(np.argmax(sc))
            if b != 2 and sc[b] > sc[2] * (1.0 + self.mon_margin):
                viol += 1
        self.viol.append(viol > 0)
        self.cnt['mon_checks'] += 1
        if len(self.viol) >= 4 and sum(self.viol[-4:]) >= 3:
            self.mode = '3d'; self.dof = [0, 1, 2]
            self.d = np.array([self.d_t / self.rcorner, self.d_t, self.d_t])
            q0 = self.q[0]; self.v = self.full(q0 + self.v[0]) - self.full(q0)
            self.mode_log.append((self.cnt['windows'], 'fallback3d')); self.cnt['mon_fallback'] += 1

    # ------------------------------------------------------------------ loop closure
    def _loop_close(self, sx, sy, sj, L, z, qc, thc, vth):
        lc = self.lc; self.cnt['lc_tries'] += 1
        rot1 = self.mode == 'rot1'
        sub = np.arange(0, len(sx), max(1, len(sx) // lc.get('M', 512)))
        sx, sy, sj = sx[sub], sy[sub], sj[sub]
        wk_ = self.world_cfg['w'] / 4.0
        kw = self.key['w'] / 4.0 if self.key else 0.0

        def sc_of(qq):
            f = (lambda jj, q=qq: q + self.v * (jj - (L - 1) / 2.0))
            t = self._world_hits(sx, sy, sj, f)
            return t
        cur = sc_of(z)
        best, bq = cur, z.copy()
        if rot1:
            ths = z[0] + self.d[0] * np.arange(-lc['n_th'], lc['n_th'] + 1) * lc.get('step_th', 4)
            for th in ths:
                s_ = sc_of(self.full(th))
                if s_ > best:
                    best, bq = s_, self.full(th)
        else:
            gt = lc['range_t']; st = lc['step_t']
            offs = np.arange(-gt, gt + 1e-9, st)
            for dth in lc['ths']:
                for dx in offs:
                    for dy in offs:
                        qq = z + np.array([dth, dx, dy])
                        s_ = sc_of(qq)
                        if s_ > best:
                            best, bq = s_, qq
        if best > lc['margin'] * max(cur, 1) and best >= lc['min_frac'] * len(sx):
            self.cnt['lc_snaps'] += 1; self.lost = 0
            return bq
        return z
