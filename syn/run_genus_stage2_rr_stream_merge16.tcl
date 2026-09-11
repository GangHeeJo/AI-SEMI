# Two-level 16-input ready/valid arbitration scaling proof.
# This merge preserves per-source order but does not timestamp-sort sources.

set DESIGN rr_stream_merge16
set RTL_LIST {
  rtl/rr_stream_arbiter4.v
  rtl/rr_stream_merge16.v
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
