# Dendritic coincidence filter Genus 합성 -- 4x4를 2x2 블록 4개로 나눠 블록당
# popcount>=2일 때만 통과시키는 조합논리(레지스터 없음). 순수 conceptual 비용 확인용.
#   genus -batch -files syn/run_genus_coincidence_filter.tcl

set DESIGN   aer_coincidence_filter
set RTL_LIST {rtl/aer_coincidence_filter.v}
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
