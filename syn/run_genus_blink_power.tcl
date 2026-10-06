# §217: blink(유휴 클록 차단) 코어 vs 항상 켠 코어, 둘 다 행 게이팅 메모리 포함. 같은 VCD(sim/vcd/blink_idle6000.vcd, tb_blink: 인스턴스 A=항상 켬, B=blink)에서 활동도 전력.
# 실행: VARIANT=rg|blink genus -batch -files syn/run_genus_blink_power.tcl
set V $::env(VARIANT)
set INST [expr {$V eq "rg" ? "A" : "B"}]
set_db library /home/aiasic26911/gsclib045_all_v4.7/gsclib045/timing/slow_vdd1v0_basicCells.lib
set_db lp_insert_clock_gating true
set_db hdl_search_path rtl
set_db init_hdl_search_path .
read_hdl -sv {rtl/arbiter2.v rtl/arbiter4_tree.v rtl/arbiter8.v rtl/small_fifo.v rtl/aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_pose.v rtl/coord_transform_rmcm_v1.v rtl/world_mem_writer.v rtl/aer_tx16_coord_transform_v1.v rtl/world_mem_ff_rg.v rtl/aer_tx16_coord_transform_v1_rg.v rtl/aer_tx16_coord_transform_v1_blink.v}
elaborate aer_tx16_coord_transform_v1_$V
read_sdc syn/constraints_5ns.sdc
syn_generic
syn_map
syn_opt
file mkdir syn/reports
report_area > syn/reports/blink_${V}_area.rpt
report_timing > syn/reports/blink_${V}_timing.rpt
report_power > syn/reports/blink_${V}_vectorless_power.rpt
read_stimulus -file sim/vcd/blink_idle6000.vcd -format vcd -dut_instance /tb_blink/$INST
report_power > syn/reports/blink_${V}_vcd_power.rpt
exit
