# 최소 수신부(RX) Genus 합성 -- 순수 조합논리(레지스터 없음)라 비용이 얼마나 작은지 확인.
#   genus -batch -files syn/run_genus_rx16_steal_buf.tcl

set DESIGN   aer_rx16_steal_buf
set RTL_LIST {rtl/aer_rx16_steal_buf.v}
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
