# Stage-2 4x4 endpoint with an event FIFO and one shared affine lane (K=1).
# Compare this report with run_genus_stage2_tx16_parallel.tcl under the same SDC.

set DESIGN aer_tx16_pose_affine2d_serial
set RTL_LIST {
  rtl/arbiter2.v
  rtl/arbiter4_tree.v
  rtl/aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_pose.v
  rtl/aer_bitmap_to_event8_pose.v
  rtl/event_batch_fifo.v
  rtl/pose_inflight_guard8.v
  rtl/pose_history_affine8.v
  rtl/coord_transform_affine2d.v
  rtl/aer_tx16_pose_affine2d_serial.v
}
set SDC_FILE syn/constraints_5ns.sdc
set LIB_FILE /home/aiasic26911/gsclib045_all_v4.7/gsclib045/timing/slow_vdd1v0_basicCells.lib
set OUT_DIR syn/reports/stage2

file mkdir $OUT_DIR
set_db library $LIB_FILE
set_db lp_insert_clock_gating true

read_hdl -sv $RTL_LIST
elaborate $DESIGN
read_sdc $SDC_FILE
syn_generic
syn_map
syn_opt

report_area   > $OUT_DIR/${DESIGN}_area.rpt
report_timing > $OUT_DIR/${DESIGN}_timing.rpt
# No activity file is read here: this is vectorless smoke power only.
report_power  > $OUT_DIR/${DESIGN}_power_vectorless.rpt
report_gates  > $OUT_DIR/${DESIGN}_gates.rpt
write_hdl     > $OUT_DIR/${DESIGN}_netlist.v
write_sdc     > $OUT_DIR/${DESIGN}_out.sdc
exit
