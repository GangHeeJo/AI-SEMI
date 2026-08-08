# Dendritic coincidence filter T=2(2사이클 창) Genus 합성. T=1(§50, 97.128um²/3.055uW)
# 대비 비용 확인.
#   genus -batch -files syn/run_genus_coincidence_filter_t2.tcl

set DESIGN   aer_coincidence_filter_t2
set RTL_LIST {rtl/aer_coincidence_filter_t2.v}
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
