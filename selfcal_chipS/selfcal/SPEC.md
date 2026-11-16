# Chip S automatic pivot self-calibration — specification (selfcal, 2026-11-15)

Bit-exact reference: `selfcal/sc_model.py` (`SelfCal`, `EstSC`). RTL: `rtl/est_selfcal.sv` (new), `rtl/est_core.sv`,
`rtl/est_top.sv`, `rtl/chip_s_full.sv` (modified). Baseline: `hyunsu_round2/code` b9e6888 (= signed-off job25 RTL).

## 1. Source algorithm and chip convention
- Source: job26 `EstU._maybe_calibrate` / `_enter_rot1` (`results/job26_est.py`, float, world = R(th)(p-c)+c+t, u = c-Q).
- Chip (job24 EstS, 3-DOF mode): world = R(-th)(p - P) + P - t/16, th in 2^-14 turn, t in Q4 px.
  Rotation about Q gives **t/16 = (R(-th) - I)(Q - P) + t_off**, so the chip unknown is u = Q - P (opposite sign to job26).
- Bootstrap runs the existing 3-DOF estimator (cfg_mode = 2) about P = cfg_px/py (sensor centre in all tests),
  starting from q = 0 (no GT, no tuned pivot).

## 2. rot_t (3-DOF observation consistency fix)
job24 3-DOF applies translation differences in the plane frame without rotation (documented TODO `rot_t`).
With large roll rotation this makes the bootstrap observations inconsistent (integer roll: Q drifts, r2 over the
whole sequence 0.39; with rot_t 0.82). selfcal enables rot_t (`cfg_rot_t | cfg_sc_en`) in mode 2 only:
- per window: (cr,sr) = CORDIC12(+qr0) [prev], CORDIC12(+qk0) [key], CORDIC12(+qc0) [fill]
- per frame: base (qc+w-qr)[1:2] rotated by R(qr0) (prev), by R(qk0) (key); fill warp (w1,w2) by R(qc0); `(c*x - s*y) >>> 12`
- candidate offsets: tx cand c -> (c-4)*((cr*d1)>>>12, (sr*d1)>>>12); ty cand -> (c-4)*(-((sr*d2)>>>12), (cr*d2)>>>12)
  (rotated step times the small integer, not the rotated product: deterministic, <= 4 Q4 units from the exact rotation)
- legacy (cfg_rot_t = 0, cfg_sc_en = 0): identical to job24 (verified, same cycle counts).

## 3. Observation and statistics (per 'score' window while bootstrapping)
(cs, sn) = CORDIC12(-q0); a = cs - 4096, s = sn (A = R(-th) - I = [[a,-s],[s,a]], Q12); tx, ty = sat(q1), sat(q2) to
+-32767 Q4 (|q| > 32767 sets sticky overflow). Accumulate N, Sa, Ss, Saa = sum(a^2+s^2), Stx, Sty,
Sbx = sum(a tx + s ty), Sby = sum(-s tx + a ty), Stt = sum(tx^2+ty^2). Only branch == score windows (job26 boot_q).
| reg | width | bound |
|---|---|---|
| N | u10 | <= 1023 (NMAX) |
| Sa, Ss | s24 | |
| Saa | u37 | 1023 * 2^26 |
| Stx, Sty | s26 | |
| Sbx, Sby | s40 | |
| Stt | u42 | |

Trigger (job26 m >= 0.4 W): m16 = |tx| + |ty| + ((min(|q0|,65535) * KM) >> 10), KM = round(pi*SW) = 3016,
MTHR = 0.4*W*16 = 6144 (u20 m16). Evaluate when m16 >= MTHR << lv, or N == 1023 (-> notrigger).

## 4. Solve (exact integers; centred 2x2 LS with S = s_c I)
Sd = N Saa - Sa^2 - Ss^2 (>= 0), T = N Stt - Stx^2 - Sty^2 (>= 0), Bx = N Sbx - Sa Stx - Ss Sty,
By = N Sby + Ss Stx - Sa Sty.  r2 = (Bx^2+By^2)/(Sd T) exactly (centred, = job26 r2).
- decision r2 >= 0.9  <=>  10 (Bx^2 + By^2) >= 9 Sd T (no division; up to 109-bit compare)
- u = round_half_away(256 B / Sd) px; Q = P + u; r2q10 = min(1023, floor(1024 B2 / D)) (status only)
- result priority: notrigger > overflow > nomotion (T < N^2 TMIN^2, TMIN = 0.01 W Q4 = 153; job26 t_std >= 0.01 W)
  > singular (Sd <= 0) > r2low > range (|u| > 4095 or Q outside the s12 pivot register) > accept
- arithmetic: 18x18 signed multiplier (8 products/window), 56x56 shift-add multiplier (17 products), 120-bit restoring
  divider (3 quotients); ~1.3k cycles per solve; estimator held at its window start meanwhile (sc_busy).

## 5. Acceptance / retry policy
- cfg_sc_retry = 0: one-shot exactly as job26 (any non-accept -> keep 3-DOF for good).
- cfg_sc_retry = 1 (deviation, documented): **insufficient evidence** (nomotion, singular) keeps accumulating and
  re-evaluates at MTHR<<1, <<2, <<3; **contradicting evidence** (r2low), range, overflow, notrigger are final.
  Thresholds (0.9, 0.01 W) unchanged. A rejected estimate is reported (sc_ux/uy, sc_r2q10, sc_res) but never published.

## 6. Publication, mode transition, world frame
Accept -> at the same window boundary (estimator stalled in S_WSTART): e_mode = roll(0), estimator pivot = Q,
world pivot wP = Q, world offset O10 (Q10) = ((R12(-th)(Q - wP_cfg)) >>> 2) + (wO_cfg << 10) - (t << 6) using the pose
of the triggering window, v1 = v2 = 0 (job26 _enter_rot1). The world frame is continuous across the switch (same frame
before/after, error = CORDIC F12 vs F10 rounding), so bootstrap map data stays valid; sc_state tells the host which
frames were bootstrap. Planes/keyframe are kept (sensor-frame snapshots, consistent under the 1-DOF model).

## 7. Reset / recalibration
rst clears all calibration state (bootstrap restarts from window 1); the estimator restarts from preroll as before.
World memory is not cleared by rst (same as the legacy chip); after a reset the host treats it as a new frame.
No in-flight re-calibration and no rot1 -> 3-DOF monitor (job26 `_monitor`) in this version (see open issues).

## 8. Deliberate deviations from job26
1. rot_t in the integer 3-DOF (observation consistency). 2. retry option (cfg). 3. d_th unchanged at publication
(job26 rescales d_th by rcorner/|u| only for |u| > rcorner = 600 px). 4. Q limited to the s12 pivot register
(far pivots such as pan R ~ 21.7k -> range). 5. NMAX = 1023 observations. 6. no rot1 monitor/fallback.
7. KM via 355/113 (exact round(pi*SW) for SW = 960, 240).
