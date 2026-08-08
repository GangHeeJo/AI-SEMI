# cluster2 + refractory(R=1) Genus 합성. cluster2(138.852um²/11.8744uW)와 비교.
#   genus -batch -files syn/run_genus_cluster2_refractory_r1.tcl

set DESIGN   aer_tx16_trad_rowcol_fovea_cluster2_refractory
set RTL_LIST {rtl/arbiter2.v rtl/arbiter4_tree.v rtl/aer_tx16_trad_rowcol_fovea_cluster2_refractory.v}
set SDC_FILE syn/constraints_5ns.sdc
set LIB_FILE /home/aiasic26911/gsclib045_all_v4.7/gsclib045/timing/slow_vdd1v0_basicCells.lib
set OUT_DIR  syn/reports

file mkdir $OUT_DIR

set_db library $LIB_FILE
set_db lp_insert_clock_gating true

read_hdl $RTL_LIST
elaborate $DESIGN -parameters {2}
read_sdc $SDC_FILE

syn_generic
syn_map
syn_opt

report_area   > $OUT_DIR/${DESIGN}_r2_area.rpt
report_timing > $OUT_DIR/${DESIGN}_r2_timing.rpt
report_power  > $OUT_DIR/${DESIGN}_r2_power.rpt

exit
