# Chip S self-calibration — stage 2/3 results (2026-11-16)

**Required execution scope completed; functional equivalence demonstrated under the tested models.
The new implementation is NOT physically clean or manufacturing-signoff complete.**

The automatic calibration RTL was frozen at `7aed741` (preceded by `1689a89`).
Stage 2/3 changed only isolated physical-flow scripts and gate testbenches, not DUT RTL.
Server work directory: `/home/aiasic26911/selfcal_20261115/phys`.
Source/reproducibility branch: `/home/aiasic26911/selfcal_20261115/code`, `selfcal-phys`.
Original `hyunsu_round2`, `redred-faer`, old final3, and submitted files were not changed.
No push or external submission.

## Implementation

| Item | New implementation | Evidence under phys/ |
|---|---:|---|
| Target clock | 8ns / 125MHz | full_8.0/syn/chip_s_full.sdc |
| Synthesis total cell/macro area | 4,457,451.573 µm² | full_8.0/syn/area.rpt |
| Hard macros | 46; 4,194,133.734 µm² | full_8.0/syn/gates.rpt |
| Synthesis setup slack | +5ps | full_8.0/syn/timing.rpt |
| Final cell/macro area | 4,564,050.496 µm² | full_8.0/pnr/area_final3.rpt |
| Die dimensions | 2923 × 1941.8 µm | full_8.0/innovus.out |
| Quantus signoff setup | +169ps, 0 violating paths | full_8.0/pnr/signoff_setup3/ |
| Quantus signoff hold | +15ps, 0 violating paths | full_8.0/pnr/signoff_hold3/ |
| Reported vectorless power | 12.82646580mW | full_8.0/pnr/signoff_power3_80.rpt |
| RTL → Genus fv_map | final hierarchical Equivalent | full_8.0/fv/chip_s_full/rtl_to_fv_map.log |
| fv_map → synthesized netlist | PASS | full_8.0/lec2_synthesis.log |
| fv_map → final routed netlist | PASS; 17,646 compared points | full_8.0/lec2.log |

The intermediate RTL LEC log contains 10 abort points that were subsequently analyzed;
the final hierarchical verdict is Equivalent. They were not waived.
Tool versions: Genus 23.14-s090_1, Innovus 23.14-s088_1, Xcelium 23.09-s013.

Old final3's documented total area was 4,521,228.334µm²; new area is about 0.95% higher.
This is contextual, not an isolated algorithm-cost comparison: old synthesis/P&R targeted a
shorter period and was retimed at 8ns; this candidate was freshly synthesized at 8ns.
Do not infer an energy improvement from the lower reported power. Both activity modeling and
macro internal-power omissions prevent such a conclusion.

## Required gate tests — new final3 netlist and Quantus SDF

| Test | Corner | Frames | Actual clock | Mismatches fp/window/world | Runtime | Timing violations |
|---|---|---:|---:|---|---:|---:|
| legacy roll_B | MIN | 32 | 8ns | 0 / 0 / 0 | 1,571s | 0 |
| legacy roll_B | MAX | 32 | 8ns | 0 / 0 / 0 | 2,387s | 1, startup |
| legacy pan_B | MIN | 64 | 8ns | 0 / 0 / 0 | 284s | 0 |
| legacy pan_B | MAX | 64 | 8ns | 0 / 0 / 0 | 400s | 1, startup |
| automatic roll_r1 | MIN | 745 | 8ns | 0 / 0 / 0 | 19,622s (5h27m02s) | 0 |

Selfcal: 177/177 windows, 39,552,733 actual clock cycles, 901,151 memory reads and writes.
Final state=2 (calibrated), result=1 (accept), N=89, r2q10=989, u=(9,35), pivot=(489,395).
Publication was observed; all final calibration-status checks passed. All 2,048 world words
matched the independent integer reference. Expected extra fp after the vector segment is
identified in the original test contract and is not included in the checked frame count.
This is evidence of calibration/pivot publication/roll-mode operation in a **new routed netlist**,
not merely applying an externally computed pivot to the old chip.

Both MAX startup violations are the same E→CK setup check at **7.654ns** on
`dut.u_est.u_dec_RC_CG_HIER_INST0.RC_CGIC_INST`: E falls at 7.562ns, giving 92ps versus
108ps required. They precede stream processing. Output equivalence is preserved, but the
strict runner correctly returns failure for those timing-warning runs. No timing checks were
disabled, and these MAX runs are not described as timing-clean.

SDF annotation is incomplete: 353,152/354,059 path delays (99.74%), 71,784/72,960 timing
checks (98.39%), disabled checks/paths 0. Missing annotations and negative-interconnect-delay
clamping warnings remain in the raw logs. Memory banks use behavioral `rtl/mem_bank_8k.sv`,
not physically timed macro models. Thus even MIN functional PASS is bounded by these models.

`gate_attempt_001/` preserves the initial elaboration failures: the old TB assumed the
flattened `dut.u_est_u_core` path. The new netlist preserves `dut.u_est.u_core` hierarchy.
Only the preload path in the generated TB was corrected; DUT logic and golden vectors were unchanged.
All gate TBs explicitly use `always #4.0`, assert the period, count real clock edges (not `$time/5`),
and contain a no-progress watchdog. Tests were detached, with status checks at 20–30min intervals.

## Residual physical issues — no blanket signoff claim

- DRC: reduced from 105 to **11 power-net MaxViaStack** violations; MinCut and spacing violations removed.
  Evidence: `pnr/drc_final3.rpt`. These are explicitly retained limitations, not a DRC-clean result.
- Connectivity: no opens/shorts in the report; **177 dangling power-wire informational findings** remain.
- Antenna: no violations (`pnr/antenna_final3.rpt`).
- Setup view electrical checks: **456 real nets / 920 terms with max-transition violations**,
  worst violation -0.075ns; total reported 503 nets / 1,014 terms including non-real categories.
  Max-capacitance and max-fanout violations: 0. **Glitch violations: 13**.
- Placement check: unplaced=0, but **9 out-of-core instances** reported (`pnr/checkplace3.rpt`).
  Their disposition is unresolved; placement-clean is not claimed.
- Power is vectorless; macro internal dynamic/leakage power is absent. It is not measured chip power.
- Legacy MAX startup timing warnings and incomplete SDF annotation, as above.

## Scope not executed

Per updated user instructions: roll_r1 MAX, pan_r1 gate, and roll_r0 gate were **not run (optional)**.
ECC accuracy of the accepted pivot was not measured. No estimator redesign, continuous recalibration,
post-switch 3-DOF fallback, or pan-coupled calibration was added. Stage-1 retry-policy limitations remain.
The physical artifacts do not prove improved geometric accuracy.

## Reproduction and retained evidence

Start in `phys/` after sourcing `~/control_digi.cshrc` in csh:
- Synthesis: `PER=8.0 bash flow/run_syn.sh` (bash syntax).
- Main implementation: `bash flow/stage2.sh` (original execution; do not overwrite existing outputs).
- PG DRC refinement + final signoff + postroute LEC: `bash flow/stage2b.sh`.
- TB generation: `python3 flow/prepare_gate.py`.
- Gate case: `bash flow/run_gate_case.sh roll_r1 MINIMUM` (requires a fresh output directory).
- RTL regression: `bash ../code/selfcal/sim/run_all.sh`.

Use a new attempt directory for re-execution to preserve these results. `final_evidence/` contains
selected raw logs, synthesis/physical reports, gate TBs, per-run SHA256 identities, and a manifest.
`evidence/FINAL3_SHA256.txt` binds the netlist/SDF/SPEF. PDK/library files are not included in Git.
Final full artifacts remain in `phys/full_8.0/pnr/`; the reproducibility commit contains only
flow scripts, small reports, and verification evidence.

Final RTL regression after the gate-TB change: **25/25 PASS**, no FAIL/TIMEOUT/tool errors.
