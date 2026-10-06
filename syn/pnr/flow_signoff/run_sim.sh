#!/bin/bash
# usage: run_sim.sh <workdir> <TOP> <tb.sv> <rtl files...>  (run after run_flow.sh; uses pnr/<TOP>_pnr.v + pnr/<TOP>.sdf)
set -u
W=$1; TOP=$2; TB=$(readlink -f $3); shift 3; DEFS="${TBDEFS:-}"; RTL=""; for f in "$@"; do RTL="$RTL $(readlink -f $f)"; done
CELLS=/home/aiasic26911/gsclib045_all_v4.7/gsclib045/verilog/slow_vdd1v0_basicCells.v
cd $W; mkdir -p sim && cd sim
xrun -64bit -sv -timescale 1ns/1ps $DEFS -define OUTF=\"rtl.txt\" $TB $RTL $CELLS ${EXTRA_SIM:-} -l rtl.log > /dev/null 2>&1
rm -rf xcelium.d
xrun -64bit -sv -timescale 1ns/1ps $DEFS -define OUTF=\"gate.txt\" -define SDF=\"../pnr/$TOP${SDFSUF:-}.sdf\" \
     +neg_tchk -access +r $TB $CELLS ${EXTRA_SIM:-} ../pnr/${TOP}_pnr.v -l gate.log > /dev/null 2>&1
echo "rtl:  $(grep TB_DONE rtl.log)"; echo "gate: $(grep TB_DONE gate.log)"
echo "timing violations: $(grep -c 'Timing violation' gate.log)"
grep -iE "SDFA|annotat" gate.log | head -5
if cmp -s rtl.txt gate.txt && [ -s rtl.txt ]; then echo "SIM_MATCH lines=$(wc -l < rtl.txt)"; else echo "SIM_MISMATCH"; diff rtl.txt gate.txt | head -5; fi
