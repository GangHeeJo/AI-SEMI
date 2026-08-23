# cluster2+Dir7(redundancy suppression) 활동도(VCD) 기반 전력, 부하 2단계(15%, 3%).
# cluster2 순정(8.580uW@15%, 4.687uW@3%)과 비교용.
#   genus -batch -files syn/run_genus_cluster2_redundancy_activity_power.tcl
set SDC_FILE syn/constraints_5ns.sdc
set LIB_FILE /home/aiasic26911/gsclib045_all_v4.7/gsclib045/timing/slow_vdd1v0_basicCells.lib
set OUT_DIR  syn/reports
file mkdir $OUT_DIR

set_db library $LIB_FILE
set_db lp_insert_clock_gating true

read_hdl {rtl/arbiter2.v rtl/arbiter4_tree.v rtl/aer_tx16_trad_rowcol_fovea_cluster2.v rtl/aer_tx16_trad_rowcol_fovea_cluster2_redundancy.v}
elaborate aer_tx16_trad_rowcol_fovea_cluster2_redundancy
read_sdc $SDC_FILE
syn_generic
syn_map
syn_opt

report_area   > $OUT_DIR/cluster2_redundancy_area.rpt
report_timing > $OUT_DIR/cluster2_redundancy_timing.rpt

read_stimulus -file sim/vcd/cluster2_redundancy_l15.vcd -format vcd -dut_instance /tb_cluster2_redundancy_vcd/dut
report_power > $OUT_DIR/cluster2_redundancy_vcd_l15_power.rpt

read_stimulus -file sim/vcd/cluster2_redundancy_l3.vcd -format vcd -dut_instance /tb_cluster2_redundancy_vcd/dut
report_power > $OUT_DIR/cluster2_redundancy_vcd_l3_power.rpt

exit
