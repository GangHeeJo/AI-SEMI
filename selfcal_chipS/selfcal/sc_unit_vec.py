"""edge-case vectors for est_selfcal alone (expected values from sc_model.SelfCal).
Each case: cfg.hex [en retry px py wPx wPy wOx wOy n_obs n_acc n_sol final_state], obs.hex (branch q0 q1 q2),
exp_acc.hex, exp_sol.hex (same layouts as sc_vec.py).   python3 sc_unit_vec.py -> out/unit/<case>/
"""
import sys, math, json
from pathlib import Path
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parent))
import sc_model as M
OUT = Path(__file__).resolve().parent / 'out/unit'
M64 = (1 << 64) - 1
h64 = lambda v: format(int(v) & M64, '016x')
SW = 960
U = 1 << 14


def pose_about(u, th_units, noise=None, rng=None):
    """chip convention: t/16 = (R(-th) - I) u  (u = Q - P, px)  -> q = (th, tx, ty) integers."""
    out = []
    for k, a in enumerate(th_units):
        th = 2 * math.pi * a / U
        c, s = math.cos(th), math.sin(th)
        tx = 16 * ((c - 1) * u[0] + s * u[1]); ty = 16 * (-s * u[0] + (c - 1) * u[1])
        if noise is not None:
            tx += noise[k][0]; ty += noise[k][1]
        out.append((3, int(a), int(round(tx)), int(round(ty))))
    return out


def run_case(obs, retry, P=(480, 360), wP=None, wO=None):
    wP = wP or P; wO = wO or P
    sc = M.SelfCal(SW, P, wP, wO, retry=retry)
    sols = []
    for b, q0, q1, q2 in obs:
        if sc.st == M.ST_BOOT and b == 3:
            ev, trig = sc.observe((q0, q1, q2))
            if ev:
                sc.solve((q0, q1, q2), trig)
                sols.append(dict(sc.out))
    return sc, sols


def write(name, obs, retry, P=(480, 360), wP=None, wO=None):
    sc, sols = run_case(obs, retry, P, wP, wO)
    wP = wP or P; wO = wO or P
    d = OUT / name; d.mkdir(parents=True, exist_ok=True)
    cfg = [1, int(retry), P[0], P[1], wP[0], wP[1], wO[0], wO[1], len(obs), len(sc.acc_log), len(sols), sc.st]
    (d / 'cfg.hex').write_text(''.join(h64(v) + '\n' for v in cfg))
    (d / 'obs.hex').write_text(''.join(' '.join(h64(v) for v in o) + '\n' for o in obs))
    (d / 'exp_acc.hex').write_text(''.join(' '.join(h64(v) for v in r) + '\n' for r in sc.acc_log))
    sat = lambda v: max(-32767, min(32767, v))
    lines = []
    for o in sols:
        stt = M.ST_BOOT if not o['final'] else (M.ST_ROT1 if o['res'] == M.R_ACCEPT else M.ST_GEN)
        lines.append(' '.join(h64(v) for v in [o['res'], o['N'], o['Sd'], o['T'], o['Bx'], o['By'], o['r2q10'], sat(o['ux']), sat(o['uy']),
                                               o['lv'], stt, o['Qx'], o['Qy'], o['O10x'], o['O10y']]) + '\n')
    (d / 'exp_sol.hex').write_text(''.join(lines))
    info = dict(case=name, n_obs=len(obs), n_acc=len(sc.acc_log), final=sc.st,
                solves=[dict(res=M.RNAME[o['res']], N=o['N'], lv=o['lv'], u=(o['ux'], o['uy']), r2q10=o['r2q10'],
                             margin=(10 * (o['Bx'] ** 2 + o['By'] ** 2) - 9 * o['Sd'] * o['T'])) for o in sols])
    print(json.dumps(info))
    return info


rng = np.random.default_rng(12345)
ramp = lambda n, a1: [int(round(a1 * k / (n - 1))) for k in range(n)]       # 0 .. a1 angle units
cases = []
# 1 no motion at all -> never triggers -> N cap -> notrigger
cases.append(('still_notrigger', [(3, 0, 0, 0)] * 1030, False))
# 2 pure rotation about P (no translation) -> nomotion (one-shot), with retry -> 3 retries then final nomotion
rot = [(3, a, 0, 0) for a in ramp(200, 4000)]
cases.append(('rot_aboutP_nomotion', rot, False))
cases.append(('rot_aboutP_retry', rot, True))
# 3 translation only (no rotation) -> singular
cases.append(('trans_only_singular', [(3, 0, 16 * 3 * k, -16 * 2 * k) for k in range(200)], False))
# 4 clean rotation about Q = P + (120, -110) with small noise -> accept
nz = rng.normal(0, 16 * 0.8, (120, 2))
cases.append(('rot_aboutQ_accept', pose_about((120, -110), ramp(120, 2400), nz), False))
# 5 negative rotation direction, pivot left of centre, interleaved non-score windows (ignored)
o = pose_about((-60, 45), ramp(100, -2600), rng.normal(0, 16 * 0.5, (100, 2)))
mix = []
for k, x in enumerate(o):
    mix.append(x)
    if k % 7 == 3:
        mix.append((2, 99999, 12345, -999))      # coast window: must not be accumulated
    if k % 11 == 5:
        mix.append((0, -77, 5, 5))               # idle window
cases.append(('rot_neg_mixed_branches', mix, False))
# 6 threshold-adjacent: same geometry, noise scaled so 10 B2 - 9 Sd T crosses zero (bisection on the scale)
base = (90, 70); th6 = ramp(110, 2300); g = rng.normal(0, 1, (110, 2))


def margin(scale):
    _, s = run_case(pose_about(base, th6, g * scale), False)
    o = s[-1]
    return 10 * (o['Bx'] ** 2 + o['By'] ** 2) - 9 * o['Sd'] * o['T'], o['res']


lo, hi = 0.0, 400.0
assert margin(lo)[0] > 0 and margin(hi)[0] < 0
for _ in range(60):
    mid = (lo + hi) / 2
    if margin(mid)[0] >= 0:
        lo = mid
    else:
        hi = mid
cases.append(('r2_just_above', pose_about(base, th6, g * lo), False))
cases.append(('r2_just_below', pose_about(base, th6, g * hi), False))
# 7 far pivot -> r2 fine but Q outside the 12-bit pivot register -> range
cases.append(('far_pivot_range', pose_about((3000, 200), ramp(150, 600), rng.normal(0, 16, (150, 2))), False))
# 8 signed extrema: translation beyond +-32767 Q4 -> overflow; huge |q0| clamps the trigger term
ext = [(3, -(1 << 31) + 5 + k, (-1) ** k * (40000 + k), 32767 - k) for k in range(6)]
cases.append(('extrema_overflow', ext, False))
ext2 = [(3, (1 << 31) - 1 - k, -32767 + k, 32767 - 3 * k) for k in range(3)]
cases.append(('extrema_bigq0_noovf', ext2, False))
# 9 retry then accept: slow start (tiny pivot effect) then large rotation about a real pivot
s1 = pose_about((25, 20), ramp(60, 1100), rng.normal(0, 16 * 1.2, (60, 2)))
s2 = pose_about((25, 20), [1100 + a for a in ramp(120, 3500)], rng.normal(0, 16 * 1.2, (120, 2)))
cases.append(('retry_then_accept', s1 + s2, True))
# 10 world offset / pivot at register extremes, non-centre wP/wO
cases.append(('accept_offset_world', pose_about((-500, 300), ramp(100, 2500), rng.normal(0, 8, (100, 2))), False, (100, -50), (7, 9), (-300, 2000)))

summary = []
for c in cases:
    name, obs, retry = c[:3]
    if len(c) > 3:
        summary.append(write(name, obs, retry, c[3], c[4], c[5]))
    else:
        summary.append(write(name, obs, retry))
json.dump(summary, open(OUT / 'summary.json', 'w'), indent=1)
