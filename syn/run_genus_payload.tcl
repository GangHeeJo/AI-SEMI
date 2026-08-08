# fovea + 16bit payload(16:1 mux) Genus 합성. plain fovea(169.632um²)와 비교해서
# "페이로드 실을 수 있게 만들면 진짜 얼마나 커지나"를 측정.
#   genus -batch -files syn/run_genus_payload.tcl

set DESIGN   aer_tx16_trad_rowcol_fovea_payload
set RTL_LIST {rtl/arbiter2.v rtl/arbiter4_tree.v rtl/aer_tx16_trad_rowcol_fovea_payload.v}
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
