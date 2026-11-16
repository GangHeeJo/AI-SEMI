"""job26 float EstU (unmodified) on the professor stream decoded by job6_golden.Stream; dumps calib + boot observations."""
import sys, json, time
from pathlib import Path
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / 'results'))
import job6_golden as G
import job18_est as E
import job26_est as U
ds = sys.argv[1]
st = G.Stream(ds)
xs, ys, fs = [], [], []
for k in range(st.nf):
    x, y = st.frame(k)[:2]
    xs.append(np.asarray(x)); ys.append(np.asarray(y)); fs.append(np.full(len(x), k, np.int32))
x = np.concatenate(xs).astype(np.int32); y = np.concatenate(ys).astype(np.int32); f = np.concatenate(fs)
W, H = 960, 720
est = U.EstU(W, H, (W / 2.0, H / 2.0))
t0 = time.time()
rec = E.run(est, x, y, f, 0, st.nf)
Q = np.array(est.boot_q)
print(ds, 'float EstU mode', est.mode, 'calib', est.calib, 'boot windows', len(Q), '%.0fs' % (time.time() - t0))
OUT = Path(__file__).resolve().parent / 'out'
json.dump(dict(calib=est.calib, mode=est.mode, boot_q=Q.tolist(), mode_log=est.mode_log), open(OUT / f'float_{ds}.json', 'w'))
