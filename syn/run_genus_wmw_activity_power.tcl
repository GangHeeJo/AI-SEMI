# §216: 월드 메모리 포함 쓰기 경로 3종의 활동도(VCD) 기반 전력. 실행: VARIANT=base|c64|c256 genus -batch -files syn/run_genus_wmw_activity_power.tcl
set V $::env(VARIANT)
set_db library /home/aiasic26911/gsclib045_all_v4.7/gsclib045/timing/slow_vdd1v0_basicCells.lib
set_db lp_insert_clock_gating true
set_db hdl_search_path rtl
set_db init_hdl_search_path .
read_hdl -sv {rtl/arbiter2.v rtl/arbiter4_tree.v rtl/arbiter8.v rtl/small_fifo.v rtl/world_mem_writer.v rtl/world_mem_writer_gain.v rtl/world_mem_ff.v rtl/world_mem_ff_rg.v syn/wmw_mem_tops.v}
elaborate wmw_$V
read_sdc syn/constraints_5ns.sdc
syn_generic
syn_map
syn_opt
file mkdir syn/reports
report_area > syn/reports/wmw_${V}_area.rpt
report_power > syn/reports/wmw_${V}_vectorless_power.rpt
read_stimulus -file sim/vcd/wmw_$V.vcd -format vcd -dut_instance /tb_power_real/dut
report_power > syn/reports/wmw_${V}_vcd_power.rpt
exit
