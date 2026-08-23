# cluster2_steal_buf 활동도(VCD) 기반 전력, 부하 2단계(15%, 3%). vectorless(19.9182uW)와 비교용.
#   genus -batch -files syn/run_genus_steal_buf_activity_power.tcl
set SDC_FILE syn/constraints_5ns.sdc
set LIB_FILE /home/aiasic26911/gsclib045_all_v4.7/gsclib045/timing/slow_vdd1v0_basicCells.lib
set OUT_DIR  syn/reports
file mkdir $OUT_DIR

set_db library $LIB_FILE
set_db lp_insert_clock_gating true

read_hdl {rtl/arbiter2.v rtl/arbiter4_tree.v rtl/aer_tx16_trad_rowcol_fovea_cluster2_steal_buf.v}
elaborate aer_tx16_trad_rowcol_fovea_cluster2_steal_buf
read_sdc $SDC_FILE
syn_generic
syn_map
syn_opt

read_stimulus -file sim/vcd/steal_buf_l15.vcd -format vcd -dut_instance /tb_steal_buf_vcd/dut
report_power > $OUT_DIR/steal_buf_vcd_l15_power.rpt

read_stimulus -file sim/vcd/steal_buf_l3.vcd -format vcd -dut_instance /tb_steal_buf_vcd/dut
report_power > $OUT_DIR/steal_buf_vcd_l3_power.rpt

exit
