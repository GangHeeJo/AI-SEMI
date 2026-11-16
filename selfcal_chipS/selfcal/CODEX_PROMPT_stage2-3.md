You are taking over the physical implementation and gate-level verification of a modified digital IC (Chip S,
REDRED project). The RTL change (on-chip automatic pivot self-calibration) is finished and verified at RTL level.
Your job is stage 2 (full-chip synthesis, P&R, signoff STA, LEC) and stage 3 (gate-level simulation) for the NEW
RTL, reusing the team's existing job25 flow. Do not redesign the RTL. Keep progress reports concise and keep a
handoff file current so a new session can resume.

## 0. Access
Server: aiasic26911@210.126.11.79. From WSL:
  ssh -F /dev/null -o BatchMode=yes -o ConnectTimeout=10 aiasic26911@210.126.11.79 'hostname; pwd'
If authentication fails, report the exact error and ask the user to authenticate; never ask for passwords or keys,
never disable host-key checking. The remote login shell is csh: run scripts with explicit bash
(`ssh ... bash -s <<'EOF' ... EOF`). EDA environment (csh): `source ~/control_digi.cshrc; rehash`
(e.g. `csh -c "source ~/control_digi.cshrc >& /dev/null; rehash; <cmd>"`). Tools: Genus 23.1, Innovus, Conformal,
Xcelium 23.09, Quantus; GPDK045 (gsclib045 at /home/aiasic26911/gsclib045_all_v4.7). Server git is 1.8 (no `git -C`).

## 0.1 Token economy while server jobs run (mandatory)
Most of this task is long unattended server runtime (synthesis, P&R, signoff, gate sims). Do not spend tokens
while waiting:
- Launch every long job detached (`nohup ... &` with its own log) and have it write a completion marker
  (e.g. `touch DONE` / `echo EXIT=$?` at the end).
- Do not poll in short loops or repeatedly tail logs. Either block once with a single wait command until the marker
  appears (one tool call), or check at long intervals (>= 20-30 min for P&R/signoff, longer for gate sims).
- Read only what you need: grep/tail the specific lines (slack, violations, PASS/FAIL/RESULT, errors) instead of
  printing whole logs or reports; never cat multi-MB files.
- Do not re-read files or re-derive facts you already have; do not re-run steps that already passed.
- While jobs run, either do useful independent work (e.g. prepare the next script/TB) or stop and wait; no
  status chatter. Keep progress messages to a few lines.

## 1. Read first
- ~/selfcal_20261115/code/selfcal/HANDOFF.md   (what changed, results, open issues)
- ~/selfcal_20261115/code/selfcal/SPEC.md      (behaviour / arithmetic contract)
- ~/hyunsu_round2/code/results/job25_fullchip_pnr.md   (the previous full-chip flow and its pitfalls)
- ~/hyunsu_round2/job25/flow/ (run_syn.sh, genus_full.tcl, run_pnr.sh, innovus_full.tcl, fix_*.tcl,
  run_signoff3_80.sh, signoff_sta3_80.tcl, hold_*.tcl, lec_full.sh, gate_sim.sh, gate_sim8.sh, gen_gate_tb.py,
  mem_bank_8k_gs.sv) and the final3 artifacts in ~/hyunsu_round2/job25/full_5.0/pnr/ (reference only).

## 2. Source of truth for this task
- NEW RTL: ~/selfcal_20261115/code (branch `selfcal`, commit after 1689a89 — check `git log`), directory rtl/.
  Changed vs the signed-off job25 RTL: rtl/est_selfcal.sv (new), est_core.sv, est_top.sv, chip_s_full.sv.
  chip_s_full has NEW PORTS: inputs cfg_sc_en, cfg_sc_retry, cfg_rot_t; outputs sc_state[1:0], sc_res[2:0],
  sc_lv[1:0], sc_r2q10[9:0], sc_ux[15:0], sc_uy[15:0], sc_n[9:0], sc_pub, sc_px[11:0], sc_py[11:0].
- Baseline (signed-off) RTL for comparison: ~/selfcal_20261115/legacy_regress/rtl_baseline (= job25/rtl, b9e6888).
- Clock target: 8.0 ns (the signed-off job25 chip shipped at 8.0 ns; signoff setup was +2.406 ns, hold +0.007 ns).

## 3. Ownership and safety (mandatory)
- Do NOT modify anything under ~/hyunsu_round2, ~/redred-faer, ~/gf_chipS_cal, ~/gf_chipS_pwr or the final3 artifacts.
  Copy the job25 flow into a new directory, e.g. ~/selfcal_20261115/phys/ (flow/, rtl/ = copy of code/rtl, full_8.0/).
- Do not change the RTL behaviour. If a timing/LEC problem seems to require an RTL change, stop and report it with
  the exact path/evidence; a change must keep RTL-level bit-exactness (rerun section 6.A) and be documented.
- Do not push, publish, submit, or touch the team baseline. Do not copy PDK/library files or credentials into git.
- Do not kill jobs you did not start. Work alone (no tmux worker pool).

## 4. Stage 2 — implementation
1. Synthesis: adapt job25/flow/run_syn.sh + genus_full.tcl (TOP=chip_s_full, CG=1, MACRO_LIB = job23 mem_bank_8k
   slow .lib, same false paths `cfg_* init_*`) to read ~/selfcal_20261115/phys/rtl/*.sv, PER=8.0. Note the
   script's RTL list excludes mem_bank_8k and puts chip_s_top.sv last — keep that, and make sure est_selfcal.sv is
   included. Record area/timing/power and compare with the job25 numbers (expected pre-layout increase ~ +61k um2 of
   standard cells: est_selfcal ~42k, est_core +19k; see HANDOFF "Block synthesis screening"). Watch `sc_pub`
   (est_selfcal flop -> est_core e_mode mux, high fanout) and the est_core score stage-A paths.
2. LEC RTL->netlist with the job25 lec_full.sh approach (Conformal). Memory macros are black boxes as before.
   Non-equivalence must be explained, not waived.
3. P&R with innovus_full.tcl (+ fix_*.tcl, hold ECO scripts as job25 did). The new top-level pins must be placed
   (job25 uses place_global_place_io_pins; check pin assignment, and that the floorplan still fits).
   Iterate until: setup >= 0 and hold >= 0 in signoff STA (MMMC as signoff_sta3_80.tcl, Quantus SPEF, slow/fast),
   DRC clean (job25 accepted only the documented power-via-stack DRCs — anything else must be fixed or explained),
   no opens/shorts, antenna clean. Write the netlist, SPEF, SDF (as job25 final3) under phys/.
4. Post-route LEC (netlist after ECO vs synthesis netlist or RTL) as job25 did.

## 5. Stage 3 — gate-level simulation (verify the clock first!)
Known traps from the old flow (do not repeat):
- job25/tb/tb_chip_full_gate.sv has `always #2.75 clk = ~clk;` (5.5 ns), and job25/flow/gate_sim.sh does NOT use
  the HALF environment variable. The 8 ns passing runs used separately generated TBs with `always #4.0`
  (e.g. job25/gsim_roll_B_MAXIMUM_f8/tb_run.sv). Generate your gate TB with an explicit 8 ns clock and grep it.
- Some TBs print "cycles" as $time/5 even with an 8 ns clock — that is not a cycle count.
- Memory macros are behavioural models in gate sim (job25/flow/mem_bank_8k_gs.sv); say so in the report.
Runs (signoff SDF, 8 ns). REQUIRED scope (keep it to this to bound runtime):
  a. Legacy regression vectors roll_B and pan_B (vectors: ~/selfcal_20261115/legacy_regress/vec/), MIN and MAX
     corners, with the new netlist and new inputs tied 0 (cfg_sc_en, cfg_sc_retry, cfg_rot_t) — expect bit-exact
     PASS like job25 f8.
  b. Self-calibration from reset: ~/selfcal_20261115/code/selfcal/out/vec/roll_r1, MIN corner ONLY
     (745 frames; covers bootstrap, evidence retry, accept, publication, roll-mode switch and world continuity).
     Measure the gate-sim speed on (a) first and estimate the roll_r1 runtime before launching; run it in the
     background.
  OPTIONAL (do not start unless the user asks after seeing the required results): roll_r1 MAX, pan_r1
  (reject, 953 frames), roll_r0 (reject, 585 frames). List them as "not run (optional)" in the report.
  Expected values for (b): exp_fp/exp_win and the world memory image produced by
     `python3 sc_world.py <tag>` (mem_final_w.hex, wgrid.hex in the same vector dir). The RTL TB
     code/tb/tb_chip_full_sc.sv is the template (it ties the new ports from cfg.hex entries 53-55).
  If a vector dir is missing, regenerate on the server: `cd ~/selfcal_20261115/code/selfcal; python3 sc_vec.py roll
  roll_r1 1 20; python3 sc_world.py roll_r1` (python3 = the system python3 with numpy).
Any mismatch/timeout: first confirm TB clock, netlist/SDF versions and vector paths; then localise (first
mismatching frame/window) before changing anything.

## 6. Must-keep checks
A. RTL regression (must stay green; rerun after ANY RTL or TB touch):
   csh -c "source ~/control_digi.cshrc >& /dev/null; rehash; bash ~/selfcal_20261115/code/selfcal/sim/run_all.sh"
   -> ~/selfcal_20261115/sc_sim/final/*.txt : legacy 6/6, sc 4/4, full 2/2, unit 13/13 PASS.
B. Report every number with its source file. Do not reuse old final3 numbers for the new design.

## 7. Deliverables
- ~/selfcal_20261115/phys/REPORT.md: commands, tool versions, synthesis area/timing/power vs job25, LEC results,
  P&R summary (die/utilisation, setup/hold per corner, DRC/antenna/connectivity), gate-sim table (test, corner,
  clock period actually used, frames, mismatches, wall time), exact list of what was NOT done, open issues.
- Keep ~/selfcal_20261115/phys/HANDOFF.md updated (locations, commands, status, blockers, next steps).
- Commit flow scripts and reports (no PDK files, no large binaries/netlists if >50 MB) to the clone on a new branch
  `selfcal-phys`; do not push.
