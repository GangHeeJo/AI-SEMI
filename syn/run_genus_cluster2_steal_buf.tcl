# cluster2_steal + cluster_buf 결합판 Genus 합성. cluster2(138.852um²/11.8744uW),
# cluster2_steal(161.082um²/13.0080uW), cluster_buf(650.826um²/43.9977uW) 대비 비교용.
#   genus -batch -files syn/run_genus_cluster2_steal_buf.tcl

set DESIGN   aer_tx16_trad_rowcol_fovea_cluster2_steal_buf
set RTL_LIST {rtl/arbiter2.v rtl/arbiter4_tree.v rtl/aer_tx16_trad_rowcol_fovea_cluster2_steal_buf.v}
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

exit
