# Synthesize our best candidate — the adaptive FAER (v2). This is the real
# PPA risk-check: does the extra activity-tracking/rank/dual-arbiter logic
# cost too much area/power/frequency, the way the teammate's round-robin+FIFO
# design did (see teammate_handoff_summary.txt)? Run from the repo root:
#   genus -files syn/run_genus_adaptive_v2.tcl

set DESIGN   aer_tx16_adaptive_v2
set RTL_LIST {rtl/arbiter4.v rtl/aer_tx16_adaptive_v2.v}
set SDC_FILE syn/constraints_5ns.sdc
set LIB_FILE /home/aiasic26911/gsclib045_all_v4.7/gsclib045/timing/slow_vdd1v0_basicCells.lib
set OUT_DIR  syn/reports

file mkdir $OUT_DIR

set_db library $LIB_FILE

read_hdl $RTL_LIST
elaborate $DESIGN
read_sdc $SDC_FILE

syn_generic
syn_map
syn_opt

report_area   > $OUT_DIR/${DESIGN}_area.rpt
report_timing > $OUT_DIR/${DESIGN}_timing.rpt
report_power  > $OUT_DIR/${DESIGN}_power.rpt
report_gates  > $OUT_DIR/${DESIGN}_gates.rpt

write_hdl > $OUT_DIR/${DESIGN}_netlist.v
write_sdc > $OUT_DIR/${DESIGN}_out.sdc

exit
