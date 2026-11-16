# Selfcal physical handoff — 2026-11-16, active
Server /home/aiasic26911/selfcal_20261115/phys; source clone ../code branch selfcal-phys @7aed741.
No DUT RTL changes; source snapshots and stage1 test evidence in phys/evidence.
Full synthesis at 8ns completed; area 4,457,451.573 um2 including 46 macros 4,194,133.734 um2; setup +5ps.
P&R + hold repair + PG DRC repair completed, new final3 in phys/full_8.0/pnr (NOT old job25 final3).
Quantus signoff: setup +0.169ns, hold +0.015ns, violating paths 0.
DRC 105 -> 11, all PG MaxViaStack. Connectivity: no opens/shorts reported, 177 dangling PG-wire infos.
Antenna no violations. RTL->fv_map final hierarchical Equivalent (10 intermediate aborts resolved);
fv_map->synthesis and fv_map->final3 LEC PASS (17,646 compare points in latter).
Current netlist/SDF/SPEF hashes: evidence/FINAL3_SHA256.txt.
Legacy gate tests in gate/: roll_B/pan_B MIN/MAX bit-exact fp/window/2048 world words.
MIN strict PASS; both MAX have 1 identical reset/startup timing warning at 7654ps,
u_est.u_dec_RC_CG_HIER_INST0.RC_CGIC_INST setup E->CK (108ps required,92ps available).
Do NOT call those timing-clean. No checker disabled. Original failed elaboration logs in gate_attempt_001.
Gate TB changed preload hierarchy dut.u_est_u_core -> dut.u_est.u_core to match new hierarchical netlist.
New TB has explicit 8ns clock, real cycle counter, stall watchdog, selfcal final-publication checks.
Legacy roll MIN 1571s / 2,861,065 cycles; selfcal roll_r1 MIN ~39.55M cycles -> estimated 6h.
Required remaining: roll_r1 MIN gate run, inspect warning scope, final RTL regression after latest TB change,
report limitations, archive receipts locally, commit scripts/reports (no push, no PDK/binaries).
Optional roll_r1 MAX, pan_r1 gate, roll_r0 gate are NOT authorized; do not run.
User requires minimal tokens: detached jobs and status checks every 20–30min only. Do not end turn while waiting.

## Completion update
Required selfcal roll_r1 MIN finished in 19,622s: 745frames,177windows,39,552,733cycles, status/pivot/world bit-exact PASS.
Strict MIN timing violations 0; SDF annotation is incomplete (99.74% paths,98.39% checks), negative-delay warnings retained.
Legacy MAX both functional PASS with one identical startup timing violation; not timing-clean.
Physical NOT_CLEAN: PG DRC11, transition456 real nets, glitch13, out-of-core9. No DUT RTL modification.
See REPORT.md and RESULTS.json; final regression/evidence/commit are the last packaging steps.

Final RTL regression after the gate-TB change: **25/25 PASS**, no FAIL/TIMEOUT/tool errors.
