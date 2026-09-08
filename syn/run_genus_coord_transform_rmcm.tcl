# Digital 2차 1단계 좌표변환(coord_transform_rmcm) Genus 합성 -- baseline/CORDIC과 PPA 3자 비교용.
#   genus -batch -files syn/run_genus_coord_transform_rmcm.tcl

set DESIGN   coord_transform_rmcm
set RTL_LIST {rtl/coord_transform_rmcm.v}
set SDC_FILE syn/constraints_5ns.sdc
set LIB_FILE /home/aiasic26911/gsclib045_all_v4.7/gsclib045/timing/slow_vdd1v0_basicCells.lib
set OUT_DIR  syn/reports

file mkdir $OUT_DIR

set_db library $LIB_FILE
set_db lp_insert_clock_gating true
set_db hdl_search_path rtl
set_db init_hdl_search_path .

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
