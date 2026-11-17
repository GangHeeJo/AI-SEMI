#!/bin/bash
# Extension of selfcal/physical/flow/run_gate_case.sh: same TB/netlist/SDF/xrun command, only the case whitelist and output root differ.
# Reads ~/selfcal_20261115 read-only; writes only under ~/redred_gate_ext.
set -euo pipefail
P=/home/aiasic26911/selfcal_20261115/phys
DS=$1; MODE=$2
case "$DS:$MODE" in roll_r0:MINIMUM|pan_r1:MINIMUM|pan_r1:MAXIMUM) T=selfcal; V=$P/../code/selfcal/out/vec/$DS;; *) echo Outside; exit 2;; esac
O=/home/aiasic26911/redred_gate_ext/fix_${DS}_${MODE}
mkdir "$O"
cd "$O"
trap 'r=$?; echo "$r" > EXIT; date -Is > FINISHED; exit "$r"' EXIT
NET=$P/full_8.0/pnr/chip_s_full_pnr3.v
SDF=$P/full_8.0/pnr/chip_s_full3_signoff.sdf
CELL=/home/aiasic26911/gsclib045_all_v4.7/gsclib045/verilog/slow_vdd1v0_basicCells.v
cp /home/aiasic26911/redred_gate_ext/tb_fix/gate_selfcal_fix.sv tb_run.sv
sha256sum tb_run.sv "$NET" "$SDF" "$P/rtl/mem_bank_8k.sv" "$V/cfg.hex" "$V/exp_fp.hex" "$V/exp_win.hex" "$V/mem_final_w.hex" > SHA256.txt
grep -F 'always #4.0 clk = ~clk;' tb_run.sv > CLOCK.txt
date -Is > STARTED
start=$(date +%s)
xrun -64bit -sv -timescale 1ns/1ps -define "SDF=\"$SDF\"" -define "SDFMODE=\"$MODE\"" +VDIR="$V" +neg_tchk -access +r tb_run.sv "$CELL" "$P/rtl/mem_bank_8k.sv" "$NET" -l xrun.log < /dev/null > xrun.out 2>&1 || true
echo $(( $(date +%s)-start )) > WALL_SECONDS
grep -E '^(RESULT|PASS|FAIL|TIMEOUT|SELFCAL_FINAL)|Timing violation|\*E,|\*F,' xrun.log > SUMMARY.txt || true
