"""Job3: hardware-friendly on-chip motion estimator (candidate C) — map-alignment 1D search.

Per window of WIN frames (3.1 ms):
  predict  : q_pred = q_prev + w_hat*1          (alpha-beta, integer-friendly)
  score    : N candidates q_pred + d*(i-(N-1)/2); each maps M sampled events into the
             world grid (saturating B-bit counters) and sums the counters it hits
             -> N parallel scorers, N*M memory reads, N*M adds, N-1 compares
  refine   : optional 3-point parabolic sub-step (1 divide per window)
  update   : all window events written at the chosen q (1 read-modify-write per event)
  abs-fix  : optional rod-verticality correction (roll only): dominant edge angle mod 90
             from a coarse count image (doubled-angle x4 trick), complementary gain g
roll: q = theta (deg), world = R(-theta)(p-c)+c, c=(480,352)
pan : q = tx (px),     world = p - (tx, 0)
"""
import numpy as np, time, json, sys

WIN = 4
C = np.array([480.0, 352.0])


def load(name):
    z = np.load(f'data/ev_{name}.npz')
    x = z['x']; y = z['y']; f = z['f']
    return x, y, f


def gt_track(name):
    a = np.load('data/roll_ecc.npy' if name == 'roll' else 'data/pan_ecc_0915.npy')
    k, t, n, ok, dth, tx, ty, cc = a.T
    ok = ok.astype(bool)
    k0 = np.concatenate([[1], k]).astype(int)
    if name == 'roll':
        q = np.concatenate([[0.0], np.cumsum(np.where(ok, dth, 0.0))])
        q2 = None
    else:
        q = np.concatenate([[0.0], np.cumsum(np.where(ok, tx, 0.0))])
        q2 = np.concatenate([[0.0], np.cumsum(np.where(ok, ty, 0.0))])
    nwin = np.concatenate([[n[0]], n]).astype(int)
    return k0, q, q2, np.concatenate([[False], ok])


def to_world(xs, ys, q, name, S, off):
    if name == 'roll':
        th = np.radians(-q)
        dx = xs - C[0]; dy = ys - C[1]
        c, s = np.cos(th), np.sin(th)
        X = c * dx - s * dy; Y = s * dx + c * dy
    else:
        X = xs - q; Y = ys
    gx = np.floor((X + off[0]) / S).astype(np.int32)
    gy = np.floor((Y + off[1]) / S).astype(np.int32)
    return gx, gy


def edge_angle(xs, ys):
    """dominant edge orientation mod 90 deg (doubled-angle x4), coarse 4x downsample."""
    img = np.zeros((180, 240), np.float32)
    np.add.at(img, (ys // 4, xs // 4), 1.0)
    img = np.minimum(img, 3)
    gx = img[1:-1, 2:] - img[1:-1, :-2]; gy = img[2:, 1:-1] - img[:-2, 1:-1]
    m2 = gx * gx + gy * gy
    ang = np.arctan2(gy, gx)
    z = (m2 * np.exp(4j * ang)).sum()
    conf = abs(z) / (m2.sum() + 1e-9)
    return np.degrees(np.angle(z)) / 4.0, conf


def run(name, x, y, f, N=9, span=None, S=4, bits=4, M=2048, refine=True, absfix=False,
        g=0.1, min_ev=15000, alpha=0.5, mapmode='stamp', R=6, sbits=4, fwarp=False):
    k0, qgt, qgt2, okgt = gt_track(name)
    nf = int(f.max()) + 1
    first = np.searchsorted(f, np.arange(nf + WIN + 1))
    if span is None:
        span = 2.0 if name == 'roll' else 8.0
    d = span / (N - 1)
    cap = (1 << bits) - 1
    if name == 'roll':
        ext = 1400; off = np.array([ext / 2, ext / 2]); W = H = int(ext / S)
    else:
        off = np.array([150.0, 90.0]); W = int(2900 / S); H = int(900 / S)
    world = np.zeros((H, W), np.uint8)          # 'count' mode: saturating counters
    stamp = np.zeros((H, W), np.uint8)          # 'stamp' mode: last-hit window index mod 2^sbits
    valid_c = np.zeros((H, W), bool)            #   + 1 valid bit per cell
    MOD = 1 << sbits
    widx = 0
    q = 0.0; w_hat = 0.0; started = False
    est = np.full(len(k0), np.nan); nev = np.zeros(len(k0), int)
    reads = adds = cmps = rmw = 0
    phi0 = None
    offs = d * (np.arange(N) - (N - 1) / 2)

    def write(gx, gy, v):
        if mapmode == 'count':
            np.add.at(world, (gy[v], gx[v]), 1); np.minimum(world, cap, out=world)
        else:
            stamp[gy[v], gx[v]] = widx % MOD; valid_c[gy[v], gx[v]] = True

    def score(gx, gy, v):
        if mapmode == 'count':
            return world[gy[v], gx[v]].astype(np.int64).sum()
        age = (widx - stamp[gy[v], gx[v]].astype(np.int64)) % MOD
        w = np.where(valid_c[gy[v], gx[v]] & (age >= 1) & (age <= R), R + 1 - age, 0)
        return w.sum()
    for i, kk in enumerate(k0):
        s, e = first[kk], first[min(kk + WIN, nf)]
        n = e - s; nev[i] = n
        xs = x[s:e].astype(np.float32); ys = y[s:e].astype(np.float32)
        fj = (f[s:e] - kk).astype(np.float32) - (WIN - 1) / 2.0   # frame offset inside window
        if not started:
            if n >= min_ev:
                started = True; q = qgt[i]  # align start
                gx, gy = to_world(xs, ys, q, name, S, off)
                v = (gx >= 0) & (gx < W) & (gy >= 0) & (gy < H)
                write(gx, gy, v); widx += 1
                rmw += n
                if absfix and name == 'roll':
                    a, c_ = edge_angle(x[s:e], y[s:e]); phi0 = a - q
                est[i] = q
            continue
        q_pred = q + w_hat
        if n < min_ev:           # sparse: coast on prediction, no map update
            q = q_pred; est[i] = q; widx += 1; continue
        stp = max(1, n // M)
        sx = xs[::stp][:M]; sy = ys[::stp][:M]; sf = fj[::stp][:M]
        wf = (w_hat / WIN) * sf if fwarp else 0.0
        sc = np.empty(N)
        for j in range(N):
            gx, gy = to_world(sx, sy, q_pred + offs[j] + wf, name, S, off)
            v = (gx >= 0) & (gx < W) & (gy >= 0) & (gy < H)
            sc[j] = score(gx, gy, v)
        reads += N * len(sx); adds += N * len(sx); cmps += N - 1
        jb = int(np.argmax(sc))
        qm = q_pred + offs[jb]
        if refine and 0 < jb < N - 1:
            a_, b_, c_ = sc[jb - 1], sc[jb], sc[jb + 1]
            den = a_ - 2 * b_ + c_
            if den < 0:
                qm += d * 0.5 * (a_ - c_) / den
        if absfix and name == 'roll' and phi0 is not None:
            a, conf = edge_angle(x[s:e], y[s:e])
            if conf > 0.15:
                eabs = ((a - phi0 - qm) + 45) % 90 - 45
                qm += g * eabs
        w_hat = alpha * (qm - q) + (1 - alpha) * w_hat
        q = qm; est[i] = q
        gx, gy = to_world(xs, ys, q + ((w_hat / WIN) * fj if fwarp else 0.0), name, S, off)
        v = (gx >= 0) & (gx < W) & (gy >= 0) & (gy < H)
        write(gx, gy, v); widx += 1
        rmw += n
    err = est - qgt
    valid = ~np.isnan(est)
    tot_ev = int(nev[valid].sum())
    t_ms = (np.arange(len(k0)) * WIN * 0.773)
    sparse = valid & (t_ms > 800) & (t_ms < 1000) if name == 'roll' else np.zeros_like(valid)
    res = dict(name=name, N=N, span=span, step=d, S=S, bits=bits, M=M, refine=refine, absfix=absfix,
               mean_abs=float(np.nanmean(np.abs(err[valid]))), max_abs=float(np.nanmax(np.abs(err[valid]))),
               final=float(err[valid][-1]), rms=float(np.sqrt(np.nanmean(err[valid] ** 2))),
               sparse_mean=float(np.nanmean(np.abs(err[sparse]))) if sparse.any() else None,
               reads_per_ev=(reads + rmw) / tot_ev, score_reads_per_ev=reads / tot_ev,
               adds_per_win=adds / valid.sum(), cmps_per_win=cmps / valid.sum(),
               world_bits=int(W * H * (bits if mapmode == 'count' else sbits + 1)), mapmode=mapmode, R=R, fwarp=fwarp, W=W, H=H)
    return res, est, qgt, qgt2, k0


def sharpness(name, x, y, f, k0, q, q2=None, S=2, stride=3):
    nf = int(f.max()) + 1
    qf = np.interp(np.arange(nf), k0[~np.isnan(q)], q[~np.isnan(q)])
    q2f = np.interp(np.arange(nf), k0, q2) if q2 is not None else None
    start = k0[~np.isnan(q)][0]
    sel = np.arange(np.searchsorted(f, start), len(f), stride)
    xs = x[sel].astype(np.float32); ys = y[sel].astype(np.float32); fr = f[sel]
    if name == 'roll':
        off = np.array([700.0, 700.0]); W = H = int(1400 / S)
        th = np.radians(-qf[fr]); dx = xs - C[0]; dy = ys - C[1]
        X = np.cos(th) * dx - np.sin(th) * dy; Y = np.sin(th) * dx + np.cos(th) * dy
    else:
        off = np.array([150.0, 150.0]); W = int(2900 / S); H = int(1000 / S)
        X = xs - qf[fr]; Y = ys - (q2f[fr] if q2f is not None else 0)
    gx = ((X + off[0]) / S).astype(np.int32); gy = ((Y + off[1]) / S).astype(np.int32)
    v = (gx >= 0) & (gx < W) & (gy >= 0) & (gy < H)
    img = np.zeros((H, W), np.float64)
    np.add.at(img, (gy[v], gx[v]), 1.0)
    return float((img ** 2).sum() / img.sum()), img


if __name__ == '__main__':
    name = sys.argv[1]
    x, y, f = load(name)
    out = []
    grid = []
    for N in (5, 9, 17):
        grid.append(dict(N=N))
    grid += [dict(N=9, refine=False), dict(N=9, S=2), dict(N=9, R=3), dict(N=9, R=12), dict(N=9, sbits=3, R=4),
             dict(N=9, M=512), dict(N=9, M=8192), dict(N=9, mapmode='count')]
    if name == 'roll':
        grid += [dict(N=9, absfix=True), dict(N=9, absfix=True, g=0.02)]
    best = None
    for cfg in grid:
        t0 = time.time()
        r, est, qgt, qgt2, k0 = run(name, x, y, f, **cfg)
        r['sec'] = round(time.time() - t0, 1)
        out.append(r)
        print(json.dumps(r, ensure_ascii=False))
        sys.stdout.flush()
        if cfg == dict(N=9):
            best = est.copy()
            np.save(f'results/job3_est_{name}_N9.npy', np.stack([k0, est, qgt]))
    # sharpness with estimated vs GT trajectory (N=9 default)
    k0 = gt_track(name)[0]
    qgt = gt_track(name)[1]
    s_est, _ = sharpness(name, x, y, f, k0, best, None)
    gt_masked = np.where(np.isnan(best), np.nan, qgt)
    s_gt, _ = sharpness(name, x, y, f, k0, gt_masked, None)
    s_none, _ = sharpness(name, x, y, f, k0, np.where(np.isnan(best), np.nan, 0.0), None)
    sh = dict(name=name, sharp_est=s_est, sharp_gt=s_gt, sharp_none=s_none, ratio=s_est / s_gt)
    print(json.dumps(sh))
    json.dump(dict(runs=out, sharp=sh), open(f'results/job3_{name}.json', 'w'), indent=1)
