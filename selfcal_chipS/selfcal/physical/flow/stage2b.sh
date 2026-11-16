#!/bin/bash
set -euo pipefail
P=/home/aiasic26911/selfcal_20261115/phys
cd "$P/full_8.0"
exec > ../logs/stage2b.log 2>&1
trap 'r=$?; echo "$r" > ../logs/stage2b.exit; exit "$r"' EXIT
export TOP=chip_s_full
export MACRO_GDS=/home/aiasic26911/hyunsu_round2/job23/macro_bank/pnr/mem_bank_8k.gds
export EXTRA_LEF=/home/aiasic26911/hyunsu_round2/job23/macro_bank/pnr/mem_bank_8k.lef
innovus -no_gui -files ../flow/fix_drc.tcl -log fix_drc < /dev/null > fix_drc.out 2>&1
grep -q FIX2_DONE fix_drc.out
innovus -no_gui -files ../flow/fix_drc3.tcl -log fix_drc3 < /dev/null > fix_drc3.out 2>&1
grep -q FIX3_DONE fix_drc3.out
cp syn/chip_s_full.sdc syn/chip_s_full_80.sdc
bash ../flow/run_signoff3_80.sh > ../logs/signoff3.log 2>&1
grep -q SIGNOFF3_DONE signoff3.out
test -s pnr/chip_s_full3_signoff.sdf
cp lec2.log lec2_initial_route.log
SKIP1=1 bash ../flow/lec_full.sh pnr/chip_s_full_pnr3.v > ../logs/lec_final3.log 2>&1
sha256sum pnr/chip_s_full_pnr3.v pnr/chip_s_full3_signoff.sdf pnr/chip_s_full3_quantus.spef > ../evidence/FINAL3_SHA256.txt
echo STAGE2B_TOOLS_FINISHED_REVIEW_REQUIRED
