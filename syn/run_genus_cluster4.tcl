# fovea_cluster4(4레인, 행마다 전용레인, arbiter 없음) Genus 합성.
# cluster2(138.852um²/11.8744uW, Genus)와 비교.
#   genus -batch -files syn/run_genus_cluster4.tcl

set DESIGN   aer_tx16_trad_rowcol_fovea_cluster4
set RTL_LIST {rtl/aer_tx16_trad_rowcol_fovea_cluster4.v}
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
