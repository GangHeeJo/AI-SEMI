# arbiter4_tree(2-way 공정중재기 3개로 만든 4-way 트리) PPA — arbiter4(회전식, 54.036um²)
# 및 arbiter4_greedy(고정우선순위, 7.182um²)와 비교. 목표: greedy만큼 싸면서
# round-robin만큼(혹은 그보다 더) 공정한지 확인.
#   genus -files syn/run_genus_arbiter4_tree.tcl

set DESIGN   arbiter4_tree
set RTL_LIST {rtl/arbiter2.v rtl/arbiter4_tree.v}
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
report_gates  > $OUT_DIR/${DESIGN}_gates.rpt

write_hdl > $OUT_DIR/${DESIGN}_netlist.v
write_sdc > $OUT_DIR/${DESIGN}_out.sdc

exit
