#!/bin/bash
# job25 P&R driver. usage (in ~/hyunsu_round2/job25): STAGES="pnr fix quantus sta" PER=5.0 bash flow/run_pnr.sh
set -u
J=$(pwd); F=$J/flow; M=/home/aiasic26911/hyunsu_round2/job23/macro_bank/pnr; W=$J/full_${PER:-5.0}; cd $W
export TOP=chip_s_full UTIL=${UTIL:-0.55}
export MACRO_SLOW=$M/mem_bank_8k_slow.lib MACRO_FAST=$M/mem_bank_8k_fast.lib MACRO_GDS=$M/mem_bank_8k.gds MACRO_LEF=$M/mem_bank_8k.lef EXTRA_LEF=$M/mem_bank_8k.lef
ST=${STAGES:-"pnr fix quantus sta"}
has() { [[ " $ST " == *" $1 "* ]]; }
cp $F/mmmc_b.tcl mmmc.tcl
if has pnr; then
  t=$(date +%s); innovus -no_gui -files $F/innovus_full.tcl -log innovus < /dev/null > innovus.out 2>&1
  echo "innovus $(( $(date +%s)-t ))s $(grep -c INNOVUS_DONE innovus.out)"; grep -E "MACROS|FLOORPLAN|DIE_BBOX" innovus.out
  grep -q INNOVUS_DONE innovus.out || { grep -iE "^\*\*ERROR" innovus.out | head; exit 1; }
  zcat pnr/timing_hold_a/*hold.summary.gz | grep -E "WNS|Violating" | head -2
fi
if has fix; then
  t=$(date +%s); innovus -no_gui -files $F/fix_full.tcl -log innovus_fix < /dev/null > innovus_fix.out 2>&1
  echo "fix $(( $(date +%s)-t ))s $(grep -c FIX_DONE innovus_fix.out)"; grep -E "DRC_PASS" innovus_fix.out
  zcat pnr/timing_hold2/*hold.summary.gz | grep -E "WNS|Violating" | head -2
fi
if has quantus; then
  G=/home/aiasic26911/gsclib045_all_v4.7/gsclib045
  sed -e "s#@TOP@#$TOP#g" -e "s#@G@#$G#g" -e "s#@FLOW@#/home/aiasic26911/hyunsu_round2/job7/flow#g" -e "s#@EXTRA_LEF@#$EXTRA_LEF#g" \
      /home/aiasic26911/hyunsu_round2/job7/flow/quantus.ccl.tmpl > quantus.ccl
  t=$(date +%s); quantus -cmd quantus.ccl < /dev/null > quantus.out 2>&1; echo "quantus $(( $(date +%s)-t ))s rc=$?"
  ls -la pnr/${TOP}_quantus.spef | awk '{print $5, $9}'
fi
if has sta; then
  t=$(date +%s); innovus -no_gui -files $F/signoff_sta_b.tcl -log signoff < /dev/null > signoff.out 2>&1
  echo "signoff sta $(( $(date +%s)-t ))s $(grep -c SIGNOFF_STA_DONE signoff.out)"
  zcat pnr/signoff_setup/*.summary.gz | grep -E "WNS|Violating" | head -2; zcat pnr/signoff_hold/*.summary.gz | grep -E "WNS|Violating" | head -2
fi
echo PNR_DONE
