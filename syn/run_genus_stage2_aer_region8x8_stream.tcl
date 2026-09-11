# One 8x8 raw-AER region frontend through its merged event stream.
# Coefficient lookup, coordinate transformation, and world memory are excluded.

set DESIGN aer_region8x8_event_stream
set RTL_LIST {
  rtl/arbiter2.v
  rtl/arbiter4_tree.v
  rtl/aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_pose.v
  rtl/aer_bitmap_to_event8_pose.v
  rtl/event_batch_fifo.v
  rtl/rr_stream_arbiter4.v
  rtl/aer_region8x8_event_stream.v
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
