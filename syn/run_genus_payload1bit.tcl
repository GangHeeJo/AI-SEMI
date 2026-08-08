# fovea + 1bit payload(polarity급) Genus 합성. 16bit 버전(637.830um²)과 비교해서
# "딱 극성 1비트만 실으면 얼마나 싼지" 측정.
#   genus -batch -files syn/run_genus_payload1bit.tcl

set DESIGN   aer_tx16_trad_rowcol_fovea_payload
set RTL_LIST {rtl/arbiter2.v rtl/arbiter4_tree.v rtl/aer_tx16_trad_rowcol_fovea_payload.v}
set SDC_FILE syn/constraints_5ns.sdc
set LIB_FILE /home/aiasic26911/gsclib045_all_v4.7/gsclib045/timing/slow_vdd1v0_basicCells.lib
set OUT_DIR  syn/reports

file mkdir $OUT_DIR

set_db library $LIB_FILE
set_db lp_insert_clock_gating true

read_hdl $RTL_LIST
elaborate $DESIGN -parameters {5 1}
read_sdc $SDC_FILE

syn_generic
syn_map
syn_opt

report_area   > $OUT_DIR/${DESIGN}_1bit_area.rpt
report_timing > $OUT_DIR/${DESIGN}_1bit_timing.rpt
report_power  > $OUT_DIR/${DESIGN}_1bit_power.rpt

exit
