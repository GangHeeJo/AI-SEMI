# 가변길이 주소 부호화(addr_encode16+addr_decode16) 단독 PPA — 순수 조합논리라
# 얼마나 싼지 확인.
#   genus -files syn/run_genus_addr_codec16.tcl

set DESIGN   addr_codec16_pair
set RTL_LIST {rtl/addr_codec16.v}
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
