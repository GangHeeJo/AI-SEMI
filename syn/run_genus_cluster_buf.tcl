# cluster + 소스별 2-deep 버퍼(cluster_buf) Genus 합성.
# cluster(146.034um²/10.6735uW, 5ns 기준)와 직접 비교하려고 같은 SDC/effort/클록게이팅 사용.
#   genus -batch -files syn/run_genus_cluster_buf.tcl

set DESIGN   aer_tx16_trad_rowcol_fovea_cluster_buf
set RTL_LIST {rtl/arbiter2.v rtl/arbiter4_tree.v rtl/aer_tx16_trad_rowcol_fovea_cluster_buf.v}
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
