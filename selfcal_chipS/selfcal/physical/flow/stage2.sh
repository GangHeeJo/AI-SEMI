#!/bin/bash
# Run from the isolated phys directory with the EDA environment loaded.
set -euo pipefail
P=/home/aiasic26911/selfcal_20261115/phys
cd "$P"
exec > logs/stage2.log 2>&1
trap 'r=$?; echo "$r" > logs/stage2.exit; date -Is; exit "$r"' EXIT
# This single detached waiter consumes no interactive polling turns.
while [ ! -f logs/synthesis.exit ]; do sleep 60; done
test "$(cat logs/synthesis.exit)" = 0
grep -q 'GENUS_DONE chip_s_full' full_8.0/genus.out
test -s full_8.0/syn/chip_s_full.v
date -Is
sha256sum full_8.0/syn/chip_s_full.v full_8.0/syn/chip_s_full.sdc > evidence/SYN_SHA256.txt
# LEC and P&R consume the frozen synthesis netlist independently.
(
 cd full_8.0
 bash ../flow/lec_full.sh syn/chip_s_full.v > ../logs/lec_synthesis.log 2>&1
 echo $? > ../logs/lec_synthesis.exit
) &
echo $! > logs/lec_synthesis.pid
export PER=8.0 UTIL=0.55 STAGES='pnr fix'
bash flow/run_pnr.sh > logs/pnr.log 2>&1
grep -q 'INNOVUS_DONE chip_s_full' full_8.0/innovus.out
grep -q FIX_DONE full_8.0/innovus_fix.out
test -s full_8.0/pnr/chip_s_full_pnr.v
# Fresh independent RC extraction and propagated-clock MMMC signoff.
export STAGES='quantus sta'
bash flow/run_pnr.sh > logs/signoff.log 2>&1
grep -q SELF_CAL_SIGNOFF_DONE full_8.0/signoff.out
test -s full_8.0/pnr/chip_s_full_signoff.sdf
wait
# Check LEC verdicts separately; no PASS inferred from a shell exit alone.
(
 cd full_8.0
 cp lec2.log lec2_synthesis.log
 cp lec2.do lec2_synthesis.do
 cp lec2.out lec2_synthesis.out
 SKIP1=1 bash ../flow/lec_full.sh pnr/chip_s_full_pnr.v > ../logs/lec_postroute.log 2>&1
 echo $? > ../logs/lec_postroute.exit
)
echo 'STAGE2_TOOLS_FINISHED_REVIEW_REQUIRED'
