"""float EstU (hyunsu job26, unmodified copy) on the real roll events: bootstrap observations vs ECC model (prereg 2026-11-17).
usage: python3 sc_float_obs.py [F1]"""
import sys, math, json, time
import numpy as np
sys.path.insert(0, '/home/aiasic26911/redred-faer/scripts/external/hyunsu_job26')
import job18_est as E, job26_est as U
F1 = int(sys.argv[1]) if len(sys.argv) > 1 else 1000
ev = np.load('/home/aiasic26911/redred_gate_ext/ecc/work/data/events.npy').view(np.recarray)
n = np.searchsorted(ev.frame, F1 + 1)
x = ev.x[:n].astype(np.int32); y = ev.y[:n].astype(np.int32); f = ev.frame[:n].astype(np.int32)
print('events', n, 'frames', f.max() + 1, flush=True)
est = U.EstU(960, 720, (480, 360))
t0 = time.time(); rec = E.run(est, x, y, f, 0, F1, log_every=0)
print('ran %.0fs windows %d mode %s calib %s' % (time.time() - t0, len(rec), est.mode, est.calib), flush=True)
np.save('/home/aiasic26911/redred_gate_ext/trans/float_rec.npy', rec); json.dump(dict(calib=est.calib, boot_q=[list(map(float, q)) for q in est.boot_q]), open('/home/aiasic26911/redred_gate_ext/trans/float_boot.json', 'w'))
# slope vs ECC model on the bootstrap observations
Ee = np.load('/home/aiasic26911/redred_gate_ext/ecc/work/data/roll_ecc.npy'); k, ok, dth = Ee[:, 0], Ee[:, 3].astype(bool), Ee[:, 4]; thc = np.cumsum(np.where(ok, dth, 0.0))
Q = np.array(est.boot_q); nb = len(Q)
fc = rec[:nb, 0] + 0.5 * rec[:nb, 1]                      # window end frame
idx = np.array([int(np.argmin(np.abs(k - v))) for v in fc]); sel = np.abs(k[idx] - fc) <= 4
th_f = np.degrees(Q[:, 0]); sg = 1.0 if np.corrcoef(thc[idx][sel], th_f[sel])[0, 1] > 0 else -1.0
def Am(a): c, s = math.cos(a), math.sin(a); return np.array([[c - 1, -s], [s, c - 1]])   # float convention A(th)
u = np.array([-5.4, 54.5])
for nm, uu in (('u_float(-5.4,54.5)', np.array([-5.4, 54.5])), ('u_ecc(-10.3,57.2)', np.array([-10.3, 57.2]))):
    ang = np.radians(sg * thc[idx][sel]); tm = np.array([Am(a) @ uu for a in ang]); tc = Q[sel][:, 1:3]
    tm = tm - tm.mean(0); tc = tc - tc.mean(0)
    s = (tm * tc).sum() / (tm * tm).sum(); r = np.corrcoef(tm.ravel(), tc.ravel())[0, 1]
    print(f'FLOAT slope vs {nm}: {s:.3f} corr {r:.3f}  (windows {int(sel.sum())}/{nb}; th slope {np.polyfit(thc[idx][sel], th_f[sel], 1)[0]:.3f})')
