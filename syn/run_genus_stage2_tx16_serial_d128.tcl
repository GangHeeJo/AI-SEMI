# Stage-2 4x4 measured UZH-lossless K=1 point with FIFO_DEPTH=128.
# The first seven positional parameters retain defaults through TIMESTAMP_W.

set DESIGN aer_tx16_pose_affine2d_serial
set RUN_NAME ${DESIGN}_d128
set PARAMS {4 10 16 16 24 14 32 128}
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

read_hdl $RTL_LIST
elaborate $DESIGN -parameters $PARAMS
read_sdc $SDC_FILE
syn_generic
syn_map
syn_opt

report_area   > $OUT_DIR/${RUN_NAME}_area.rpt
report_timing > $OUT_DIR/${RUN_NAME}_timing.rpt
# No activity file is read here: this is vectorless smoke power only.
report_power  > $OUT_DIR/${RUN_NAME}_power_vectorless.rpt
report_gates  > $OUT_DIR/${RUN_NAME}_gates.rpt
write_hdl     > $OUT_DIR/${RUN_NAME}_netlist.v
write_sdc     > $OUT_DIR/${RUN_NAME}_out.sdc
exit
