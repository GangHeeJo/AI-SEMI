#!/bin/bash
# run in ~/hyunsu_round2/job25/full_5.0 after ". ../runenv.sh"; syn/chip_s_full_80.sdc = chip_s_full_55.sdc with the clock period 8.0 ns
G=/home/aiasic26911/gsclib045_all_v4.7/gsclib045
sed -e "s#@TOP@#chip_s_full3#g" -e "s#@G@#$G#g" -e "s#@FLOW@#/home/aiasic26911/hyunsu_round2/job7/flow#g" -e "s#@EXTRA_LEF@#$EXTRA_LEF#g" \
    /home/aiasic26911/hyunsu_round2/job7/flow/quantus.ccl.tmpl > quantus3.ccl
quantus -cmd quantus3.ccl < /dev/null > quantus3.out 2>&1; echo quantus rc=$?
innovus -no_gui -files ../flow/signoff_sta3_80.tcl -log signoff3 < /dev/null > signoff3.out 2>&1
zcat pnr/signoff_setup3/*.summary.gz | grep -E "WNS|Violating" | head -2; zcat pnr/signoff_hold3/*.summary.gz | grep -E "WNS|Violating" | head -2
echo SIGNOFF3_ALLDONE
