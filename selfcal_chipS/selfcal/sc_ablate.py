"""ablation of integer 3-DOF bootstrap observation quality (config-only knobs, same RTL structure)."""
import sys, math
from pathlib import Path
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parent))
import sc_model as M
G = M.G
st = G.Stream(sys.argv[1])
P = (480, 360); U = 1 << 14
for name, kw in [('base', {}), ('nokey', dict(key_w=0)), ('minev967', dict(min_ev=967)), ('d0_9', dict(d0=9)),
                 ('nokey+minev', dict(key_w=0, min_ev=967)), ('nokey+minev+d0_9', dict(key_w=0, min_ev=967, d0=9)),
                 ('key4px_thr', dict(kthr_t=4 * 16))]:
    d = [kw.get('d0', 11), 32, 32]
    thr = [int(30 * U / 360), kw.get('kthr_t', 150 * 16), kw.get('kthr_t', 150 * 16)]
    sc = M.SelfCal(G.SW, P, P, P)
    est = M.EstSC('3d', G.SW, G.SH, P, d, kw.get('min_ev', 15000), S=3, key_thr=thr, key_w=kw.get('key_w', 4), sc=sc, wP=P, wO=P)
    M.run(est, st, 400)
    o = sc.out
    if not o:
        print(name, 'no decision'); continue
    r2 = (o['Bx'] ** 2 + o['By'] ** 2) / (o['Sd'] * o['T'])
    tstd = math.sqrt(o['T'] / o['N'] ** 2) / 16
    print('%-18s res=%-9s N=%3d Q=(%5d,%5d) R=%6.1f r2=%.4f t_std=%5.1f px' % (name, M.RNAME[o['res']], o['N'], o['Qx_est'], o['Qy_est'],
          math.hypot(o['ux'], o['uy']), r2, tstd), flush=True)
