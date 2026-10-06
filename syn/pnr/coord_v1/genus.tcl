# Digital 2차 1단계 통합판(aer_tx16_coord_transform_v1) P&R 입력용 합성. progress.md §115와 같은 RTL/SDC, 산출물만 이 폴더로.
#   cd ~/redred-faer && genus -batch -files syn/pnr/coord_v1/genus.tcl
set DESIGN   aer_tx16_coord_transform_v1
set RTL_LIST {
  rtl/arbiter2.v
  rtl/arbiter4_tree.v
  rtl/arbiter8.v
  rtl/small_fifo.v
  rtl/aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_pose.v
  rtl/coord_transform_rmcm_v1.v
  rtl/world_mem_writer.v
  rtl/aer_tx16_coord_transform_v1.v
}
set SDC_FILE syn/constraints_5ns.sdc
set LIB_FILE /home/aiasic26911/gsclib045_all_v4.7/gsclib045/timing/slow_vdd1v0_basicCells.lib
set OUT_DIR  syn/pnr/coord_v1
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
report_timing > $OUT_DIR/${DESIGN}_gtiming.rpt
report_power  > $OUT_DIR/${DESIGN}_gpower.rpt
write_hdl > $OUT_DIR/${DESIGN}_netlist.v
write_sdc > $OUT_DIR/${DESIGN}_out.sdc
exit
