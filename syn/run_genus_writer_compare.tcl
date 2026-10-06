# world_mem_writer(기존) vs world_mem_writer_gain(이득 조절) 같은 조건 합성 비교. 실행: DESIGN=<module> genus -batch -files syn/run_genus_writer_compare.tcl
set DESIGN $::env(DESIGN)
set RTL_LIST {rtl/arbiter4_tree.v rtl/arbiter2.v rtl/arbiter8.v rtl/small_fifo.v rtl/world_mem_writer.v rtl/world_mem_writer_gain.v}
set_db library /home/aiasic26911/gsclib045_all_v4.7/gsclib045/timing/slow_vdd1v0_basicCells.lib
set_db lp_insert_clock_gating true
set_db hdl_search_path rtl
set_db init_hdl_search_path .
read_hdl -sv $RTL_LIST
elaborate $DESIGN
read_sdc syn/constraints_5ns.sdc
syn_generic
syn_map
syn_opt
file mkdir syn/reports
report_area   > syn/reports/${DESIGN}_cmp_area.rpt
report_timing > syn/reports/${DESIGN}_cmp_timing.rpt
report_power  > syn/reports/${DESIGN}_cmp_power.rpt
exit
