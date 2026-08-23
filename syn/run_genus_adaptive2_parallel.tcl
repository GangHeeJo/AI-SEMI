# aer_tx16_adaptive2_parallel(§84, raw/bitmap 단일사이클 병렬 적응형, 0%손실) Genus 합성.
# cluster2(138.852um²/11.8744uW)와 같은 조건(5ns SDC)으로 비교.
#   genus -batch -files syn/run_genus_adaptive2_parallel.tcl

set DESIGN   aer_tx16_adaptive2_parallel
set RTL_LIST {rtl/aer_tx16_adaptive2_parallel.v}
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
