# true_traditional+fovea, 합성 노력도를 high로 올려서 (RTL 변경 없이) 순수 합성
# 최적화로 추가 절감 여지가 있는지 확인. 클록게이팅(#32-3)까지 포함한 현재 최종
# (169.632um²/12.4971uW/833.3MHz) 대비 비교.
#   genus -files syn/run_genus_trad_rowcol_fovea_high.tcl

set DESIGN   aer_tx16_trad_rowcol_fovea
set RTL_LIST {rtl/arbiter2.v rtl/arbiter4_tree.v rtl/aer_tx16_trad_rowcol_fovea.v}
set SDC_FILE syn/constraints_5ns.sdc
set LIB_FILE /home/aiasic26911/gsclib045_all_v4.7/gsclib045/timing/slow_vdd1v0_basicCells.lib
set OUT_DIR  syn/reports

file mkdir $OUT_DIR

set_db library $LIB_FILE
set_db lp_insert_clock_gating true
set_db syn_generic_effort high
set_db syn_map_effort high
set_db syn_opt_effort high

read_hdl $RTL_LIST
elaborate $DESIGN
read_sdc $SDC_FILE

syn_generic
syn_map
syn_opt

report_area   > $OUT_DIR/${DESIGN}_high_area.rpt
report_timing > $OUT_DIR/${DESIGN}_high_timing.rpt
report_power  > $OUT_DIR/${DESIGN}_high_power.rpt
report_gates  > $OUT_DIR/${DESIGN}_high_gates.rpt

exit
