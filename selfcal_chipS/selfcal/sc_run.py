"""run the integer self-calibration model on a professor sequence and print the decision + intermediates."""
import sys, json, time, math
from pathlib import Path
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parent))
import sc_model as M
G = M.G
ds = sys.argv[1]; maxw = int(sys.argv[2]) if len(sys.argv) > 2 else 10 ** 9
est = M.make_sc(ds); st = G.Stream(ds); t0 = time.time()
nw, f = M.run(est, st, maxw)
sc = est.sc
print(ds, 'windows', nw, 'frames', f, 'state', sc.st, 'result', M.RNAME[sc.res], 'pub_win', est.pub_win, '%.0fs' % (time.time() - t0))
o = sc.out
if o:
    print(' ', {k: v for k, v in o.items()})
    r2 = (o['Bx'] ** 2 + o['By'] ** 2) / (o['Sd'] * o['T']) if o['Sd'] * o['T'] > 0 else 0
    print('  exact r2 = %.5f  u = (%.3f, %.3f) px  R = %.2f' % (r2, 256 * o['Bx'] / max(o['Sd'], 1), 256 * o['By'] / max(o['Sd'], 1), math.hypot(256 * o['Bx'] / max(o['Sd'], 1), 256 * o['By'] / max(o['Sd'], 1))))
q = [r['q_out'] for r in est.trace]
print('  final q', est.q, 'mode', est.mode, 'pivot', est.pivot)
OUT = Path(__file__).resolve().parent / 'out'; OUT.mkdir(exist_ok=True)
json.dump(dict(out=o, acc=sc.acc_log, q=[list(map(int, x)) for x in q], br=[r['branch'] for r in est.trace], pub=est.pub_win),
          open(OUT / f'sc_{ds}.json', 'w'))
