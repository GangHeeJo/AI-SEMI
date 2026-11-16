# selfcal handoff — Chip S automatic pivot self-calibration (2026-11-15)

## Locations
| what | where |
|---|---|
| authoritative source (read-only) | server `~/hyunsu_round2/code` @ b9e6888 (= signed-off job25 RTL) |
| isolated working clone | server `~/selfcal_20261115/code`, branch `selfcal` (local commit only, not pushed) |
| professor data (symlinks) | `~/selfcal_20261115/code/data/*.dvs` -> `~/redred-faer/Q&A/...` (roll 09-22, pan 09-15) |
| legacy regression | `~/selfcal_20261115/legacy_regress/` (README, frozen baseline RTL/TB/vectors + sha256) |
| vectors (not in git) | `~/selfcal_20261115/code/selfcal/out/{vec,unit}/` (regenerate with the scripts below) |
| block synthesis screening | `~/selfcal_20261115/syn_screen/` (timing-only, stub planes) |
| Codex prompt (stage 2/3) | `selfcal/CODEX_PROMPT_stage2-3.md` (local: `results/selfcal-20261115/`) |
| local copy of scripts/docs | `/home/chickgoose/projects/a1/results/selfcal-20261115/work/` (WSL) |
| redred-faer HEAD seen | 022bf84 (§237); submission package untouched |

## Implemented behaviour (details: selfcal/SPEC.md)
- `cfg_sc_en=1` + `cfg_mode=2`: 3-DOF bootstrap about cfg_px/py from q = 0 (no GT/pivot input), rot_t enabled,
  integer centred 2x2 LS on score windows, trigger m >= 0.4W, decision 10 B^2 >= 9 Sd T (r2 >= 0.9), checks
  nomotion / singular / range / overflow / notrigger, publication into roll mode about Q = P + u with a Q10 world
  offset so the world frame is continuous; v1 = v2 = 0. Estimator stalls at its window start while the calibrator works.
- `cfg_sc_retry=1`: re-evaluate after insufficient evidence (nomotion/singular) at 2x, 4x, 8x the motion threshold.
- `cfg_sc_en=0, cfg_rot_t=0`: legacy chip, bit- and cycle-identical.
- Status outputs: sc_state (0 off/1 boot/2 calibrated/3 general), sc_res, sc_lv, sc_r2q10, sc_ux/uy, sc_n, sc_pub, sc_px/py.

## Changed files (clone)
`rtl/est_selfcal.sv` (new), `rtl/est_core.sv`, `rtl/est_top.sv`, `rtl/chip_s_full.sv` (new ports: cfg_sc_en,
cfg_sc_retry, cfg_rot_t in; sc_* out), `tb/tb_est_sc.sv`, `tb/tb_sc_unit.sv`, `tb/tb_chip_full_sc.sv` (new),
`selfcal/*` (model, vector generators, analysis, sim scripts, SPEC). `selfcal/patch_*.py` = provenance of the
RTL/TB edits against b9e6888 (written for the local layout).

## Results (Xcelium 23.09 RTL, 5 ns TB clock; all from reset unless noted)
| test | scope | result |
|---|---|---|
| legacy est roll_A/B pan_A/B, full roll_B/pan_B on new RTL (sc off) | job25 vectors, TB with new inputs tied 0 | 6/6 PASS, same cycle counts |
| sc roll_r0 (job26 one-shot) | 585 frames, 59 obs | PASS; nomotion at window 126 -> stays 3-DOF |
| sc roll_r1 (retry) | 745 frames, 89 obs, 2 solves | PASS; accept at window 156, Q = (489, 395), r2q10 989, O10 (500652, 409322) |
| sc roll_r1 + reset inside the first solve | restart from reset | PASS |
| sc pan_r1 (retry) | 953 frames, 131 obs | PASS; r2low (r2 0.746) -> stays 3-DOF |
| chip_s_full end-to-end roll_r1 / pan_r1 | fp, windows, final world memory 2048 words | PASS / PASS |
| est_selfcal edge cases (13) | still/notrigger, rotation about P (nomotion, retry), translation only (singular), accept (2 geometries, mixed coast/idle windows), r2 just above / just below 0.9, far pivot (range), overflow, |q0| extremes, retry->accept, off-centre world regs | 13/13 PASS |
Each sc test compares per-frame world params, per-window estimator state, 54 scores/window, end planes, every
accumulator after every observation, and every solve field (Sd, T, Bx, By, r2q10, u, lv, state, Q, O10).
Throughput (estimator, 8 ns): bootstrap 81.7k cycles/frame (0.654 ms), roll after publication 90.6k (0.725 ms);
frame period 0.773 ms.

## Key numbers / findings
- r2 boundary root cause: integer 3-DOF observations, not the threshold. Without rot_t: Q (472,386) R 27 r2 0.904;
  with rot_t: r2 0.93 at trigger, 0.95 later. job26's own t_std >= 0.01W check rejects at 43 deg (t_std 6.4 px < 9.6).
- float job26 (unmodified) on the same data: Q (474.6, 414.5), R 54.7, r2 0.993 -> integer Jacobi 3-DOF underestimates
  the pivot radius (R 28-39 for every config-only variant). Accepted integer pivot (489, 395) is therefore biased.
- pan: theta span 4.3 deg -> r2 0.75, stays 3-DOF (as job26 reported); its pivot (R ~ 21.7k) would not fit the
  s12 register anyway (range).

## Reproduce (server, bash)
```
cd ~/selfcal_20261115/code/selfcal
python3 sc_vec.py roll roll_r1 1 20; python3 sc_vec.py roll roll_r0 0 10; python3 sc_vec.py pan pan_r1 1 10
python3 sc_world.py roll_r1; python3 sc_world.py pan_r1; python3 sc_unit_vec.py
csh -c "source ~/control_digi.cshrc >& /dev/null; rehash; bash ~/selfcal_20261115/code/selfcal/sim/run_all.sh"
#  -> ~/selfcal_20261115/sc_sim/final/*.txt ; analysis: sc_obs.py, sc_fit.py, sc_float.py, sc_ablate.py, sc_retry.py
```

## Open issues
1. Pivot accuracy: integer Jacobi bias (above); ECC accuracy of the auto pivot not measured (roll_ecc.npy is not on
   the server). Fix would be coordinate-descent bootstrap scoring (sample buffer) — estimator redesign, out of scope.
2. Roll needs cfg_sc_retry=1 to calibrate on the integer chip; the exact job26 one-shot rule rejects (nomotion).
3. No rot1 -> 3-DOF monitor/fallback, no in-flight recalibration (reset only).
4. Pan coupling mode (cfg_mode 1, KA/KX/KY/BY16) is not produced by selfcal; pan stays 3-DOF.
5. Physical: only block-level synthesis screening (see below); no full-chip synth/P&R/LEC/gate sim of the new design.
   chip_s_full has new pins. Old final3 results do not apply to this RTL.

## Block synthesis screening (Genus 23.1, slow corner, 8 ns, CG off, est_plane stubbed)
| block | baseline (b9e6888) | new | worst setup path at 8 ns |
|---|---|---|---|
| est_core (planes stubbed) | 88,606 um2 | 107,732 um2 (+21.6%) | met (0 ps; Genus stops at 0, baseline also 1 ps); starts at port `sc_pub` screened as an input with 1.6 ns input delay — in the chip it is a flop in est_selfcal (high fanout: drives e_mode -> dofm/xyf) |
| est_selfcal | — | 42,161 um2 | +537 ps (op_reg -> dv_n_reg[119]) |

Estimated standard-cell increase ~ +61k um2 on the job25 total of 0.327 mm2 (~ +19%), ~ +1.4% of the 4.52 mm2 chip.
Timing/area fixes already applied (bit-identical, full regression re-run): registered 18x18 product, registered signed
56x56 product, one shared rotation unit and k-step unit for rot_t. Screening: `~/selfcal_20261115/syn_screen/`
(job24_flow/genus.tcl, slow_vdd1v0, CG off, est_plane replaced by `selfcal/syn_stub/est_plane_stub.sv`).

## Next steps (stage 2/3, handed to Codex)
Full-chip Genus/Innovus/signoff/LEC with the job25 flow on the clone RTL, then gate-level sims with a verified 8 ns
TB clock (job25 gate_sim.sh ignores HALF; tb_chip_full_gate.sv is 5.5 ns) — legacy vectors + selfcal vectors.
