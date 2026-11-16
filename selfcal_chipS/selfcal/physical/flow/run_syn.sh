#!/bin/bash
# job25: Genus for chip_s_full (all memories = mem_bank_8k black-box macros). usage: PER=5.0 bash flow/run_syn.sh   (in ~/hyunsu_round2/job25)
set -u
J=$(pwd); F=$J/flow; M=/home/aiasic26911/hyunsu_round2/job23/macro_bank/pnr
W=$J/full_${PER:-5.0}; mkdir -p $W && cd $W
export TOP=chip_s_full PER=${PER:-5.0} CG=1
export MACRO_LIB=$M/mem_bank_8k_slow.lib
export RTL="$(ls $J/rtl/*.sv | grep -v -e mem_bank_8k -e chip_s_top.sv | tr '\n' ' ') $J/rtl/chip_s_top.sv"
ls $J/rtl/*.sv > /dev/null
t=$(date +%s); genus -no_gui -files $F/genus_full.tcl -log genus < /dev/null > genus.out 2>&1
echo "genus $(( $(date +%s)-t ))s $(grep -c GENUS_DONE genus.out)"
grep -m1 -E "^ *$TOP " syn/area.rpt; grep -E "mem_bank_8k" syn/gates.rpt | head -2
grep -m1 -E "Slack|VIOLATED|MET" syn/timing.rpt; grep -m2 -E "Startpoint|Endpoint" syn/timing.rpt
grep -iE "^Error" genus.out | head -5
