"""Per-window roll estimate by registering consecutive event-count images (Euclidean ECC).

A Euclidean warp's rotation angle does not depend on where the rotation center is, so the
chained angle is the camera roll even though the optical center orbits the axis at 4 cm.
Translation (tx, ty) absorbs the off-center pivot and parallax.
"""
import numpy as np, cv2
from scipy.ndimage import gaussian_filter

WIN = 4          # frames per window (~3.1 ms)
DS = 2           # downsample factor for registration
MIN_EV = 15000   # windows with fewer events are not registered

ev = np.load('data/events.npy').view(np.recarray)
fr = ev.frame; nf = int(fr.max()) + 1
first = np.searchsorted(fr, np.arange(nf + 1))
t_frame = ev.t[np.minimum(first[:-1], len(ev) - 1)].astype(np.int64)


def window_img(k):
    s, e = first[k], first[min(k + WIN, nf)]
    img = np.zeros((720 // DS, 960 // DS), np.float32)
    np.add.at(img, (ev.y[s:e] // DS, ev.x[s:e] // DS), 1.0)
    img = gaussian_filter(np.minimum(img, 4), 1.2)
    return (img / (img.max() + 1e-6)).astype(np.float32), e - s


starts = list(range(1, nf - WIN, WIN))
rows = []
prev_img, prev_n = window_img(starts[0])
warp = np.eye(2, 3, dtype=np.float32)
crit = (cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT, 100, 1e-5)
for k in starts[1:]:
    img, n = window_img(k)
    ok, dth, tx, ty, cc = False, np.nan, np.nan, np.nan, np.nan
    if n >= MIN_EV and prev_n >= MIN_EV:
        try:
            cc, W = cv2.findTransformECC(prev_img, img, warp.copy(), cv2.MOTION_EUCLIDEAN, crit, None, 5)
            dth = np.degrees(np.arctan2(W[1, 0], W[0, 0]))
            tx, ty = W[0, 2] * DS, W[1, 2] * DS
            ok = True
            warp = W  # warm start for next pair
        except cv2.error:
            warp = np.eye(2, 3, dtype=np.float32)
    rows.append((k, t_frame[k], n, ok, dth, tx, ty, cc))
    prev_img, prev_n = img, n

a = np.array(rows, dtype=float)
np.save('data/roll_ecc.npy', a)
k, t, n, ok, dth, tx, ty, cc = a.T
ok = ok.astype(bool)
theta = np.cumsum(np.where(ok, dth, 0.0))
tt = (t - t_frame[1]) / 1e3
print(f'windows {len(a)}, registered {ok.sum()}, median ECC corr {np.nanmedian(cc):.3f}')
print(f'total roll {theta[-1]:.1f} deg; skipped windows (low events) {(~ok).sum()}')
w = np.where(ok)[0]
vel = dth[ok] / (WIN * 0.773e-3)
print(f'angular vel deg/s: median |w| {np.median(np.abs(vel)):.0f}, p95 {np.percentile(np.abs(vel), 95):.0f}, max {np.abs(vel).max():.0f}')
for i in range(0, len(a), 40):
    print(f'{tt[i]:7.0f} ms  theta {theta[i]:8.1f}  dth {dth[i]:6.2f}  t=({tx[i]:6.1f},{ty[i]:6.1f})px  cc {cc[i]:.2f}  n {int(n[i])}')

import matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt
fig, ax = plt.subplots(3, 1, figsize=(10, 8), sharex=True)
ax[0].plot(tt, theta); ax[0].set_ylabel('cumulative roll (deg)'); ax[0].grid()
ax[1].plot(tt[ok], vel, '.', ms=3); ax[1].set_ylabel('deg/s'); ax[1].grid()
ax[2].plot(tt[ok], tx[ok], '.', ms=3, label='tx'); ax[2].plot(tt[ok], ty[ok], '.', ms=3, label='ty')
ax[2].set_ylabel('px per window'); ax[2].set_xlabel('ms'); ax[2].legend(); ax[2].grid()
plt.tight_layout(); plt.savefig('viz_roll_ecc.png', dpi=70)
