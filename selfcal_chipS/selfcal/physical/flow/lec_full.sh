#!/bin/bash
# job25 two-step LEC for chip_s_full: (1) RTL -> Genus fv_map (Genus-written dofile), (2) fv_map -> post-route netlist.
# macros = black boxes from the macro .lib on both sides. usage (in ~/hyunsu_round2/job25/full_5.0): bash ../flow/lec_full.sh [netlist]
set -u
TOP=chip_s_full; NET=${1:-pnr/${TOP}_pnr.v}
LIB="/home/aiasic26911/gsclib045_all_v4.7/gsclib045/timing/slow_vdd1v0_basicCells.lib /home/aiasic26911/hyunsu_round2/job23/macro_bank/pnr/mem_bank_8k_slow.lib"
if [ "${SKIP1:-0}" != 1 ]; then
  lec -XL -nogui -dofile fv/$TOP/rtl_to_fv_map.do < /dev/null > lec1.out 2>&1
  echo "== step1 RTL->fv_map"; grep -E "^(Equivalent|Non-equivalent|Abort|Not-compared) " fv/$TOP/rtl_to_fv_map.log | tail -4; grep -m2 -iE "Compare Results|Error:" fv/$TOP/rtl_to_fv_map.log lec1.out | head -4
fi
gunzip -c fv/$TOP/fv_map.v.gz > fv/$TOP/fv_map.v
cat > lec2.do <<EOD
set log file lec2.log -replace
read library -liberty $LIB
read design -verilog -golden -root $TOP fv/$TOP/fv_map.v
read design -verilog -revised -root $TOP $NET
set flatten model -seq_constant
set system mode lec
add compared points -all
compare
report verification
exit -force
EOD
lec -XL -nogui -dofile lec2.do < /dev/null > lec2.out 2>&1
echo "== step2 fv_map->$NET"; grep -E "^(Equivalent|Non-equivalent|Abort|Not-compared) " lec2.log | tail -4; grep -m3 -E "Compare Results|Mapped points|Warning: Golden" lec2.log
