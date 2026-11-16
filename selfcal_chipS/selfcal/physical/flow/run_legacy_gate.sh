#!/bin/bash
set -u
P=/home/aiasic26911/selfcal_20261115/phys
mkdir -p "$P/gate"
for ds in roll_B pan_B; do
 for mode in MINIMUM MAXIMUM; do
  bash "$P/flow/run_gate_case.sh" "$ds" "$mode" > "$P/logs/gate_${ds}_${mode}.log" 2>&1 &
 done
done
wait
date -Is > "$P/logs/legacy_gate.DONE"
