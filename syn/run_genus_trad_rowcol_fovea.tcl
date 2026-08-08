# Synthesize true_traditional + fixed-weight fovea(중심와 우선순위, WEIGHT=5) — final
# 1차 submission design. (arbiter4_tree swap tried and reverted — helped standalone but
# hurt full-design PPA, progress.md #28-1.) 자동 클록게이팅 추가(#32-3) — Fmax 무영향,
# 전력 -3.1%, 면적 +1.4%.
#   genus -files syn/run_genus_trad_rowcol_fovea.tcl

set DESIGN   aer_tx16_trad_rowcol_fovea
set RTL_LIST {rtl/arbiter2.v rtl/arbiter4_tree.v rtl/aer_tx16_trad_rowcol_fovea.v}
set SDC_FILE syn/constraints_5ns.sdc
set LIB_FILE /home/aiasic26911/gsclib045_all_v4.7/gsclib045/timing/slow_vdd1v0_basicCells.lib
set OUT_DIR  syn/reports

file mkdir $OUT_DIR

set_db library $LIB_FILE
set_db lp_insert_clock_gating true

read_hdl $RTL_LIST
elaborate $DESIGN
read_sdc $SDC_FILE

syn_generic
syn_map
syn_opt

report_area   > $OUT_DIR/${DESIGN}_area.rpt
report_timing > $OUT_DIR/${DESIGN}_timing.rpt
report_power  > $OUT_DIR/${DESIGN}_power.rpt
report_gates  > $OUT_DIR/${DESIGN}_gates.rpt

write_hdl > $OUT_DIR/${DESIGN}_netlist.v
write_sdc > $OUT_DIR/${DESIGN}_out.sdc

exit
