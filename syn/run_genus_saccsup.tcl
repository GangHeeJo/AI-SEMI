# 사카드 억제(aer_tx16_trad_rowcol_fovea_saccsup) PPA — req 게이팅 한 줄뿐이라
# 최종 설계(167.238um²/833.3MHz/12.89uW) 대비 비용이 거의 없을 것으로 예상.
#   genus -files syn/run_genus_saccsup.tcl

set DESIGN   aer_tx16_trad_rowcol_fovea_saccsup
set RTL_LIST {rtl/arbiter4_tree.v rtl/arbiter2.v rtl/aer_tx16_trad_rowcol_fovea.v rtl/aer_tx16_trad_rowcol_fovea_saccsup.v}
set SDC_FILE syn/constraints_5ns.sdc
set LIB_FILE /home/aiasic26911/gsclib045_all_v4.7/gsclib045/timing/slow_vdd1v0_basicCells.lib
set OUT_DIR  syn/reports

file mkdir $OUT_DIR

set_db library $LIB_FILE

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
