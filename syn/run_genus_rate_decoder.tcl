# rate 디코더(16소스 카운터) Genus 합성 -- payload 방식(637.830um²)과 하드웨어
# 비용을 직접 비교하려는 목적. 디코더 단독 비용만 잰다(TX 쪽은 fovea 그대로 무수정
# 이므로 169.632um² 그대로 추가됨).
#   genus -batch -files syn/run_genus_rate_decoder.tcl

set DESIGN   aer_rate_decoder
set RTL_LIST {rtl/aer_rate_decoder.v}
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
