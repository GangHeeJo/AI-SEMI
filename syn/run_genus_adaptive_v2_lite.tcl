# adaptive v2 "lite" — same algorithm, activity/round bit widths trimmed to what
# DECAY_SHIFT=6/WEIGHT=3 actually need (see rtl/aer_tx16_adaptive_v2_lite.v).
# Tests whether v2's PPA loss (+688% area vs base) was the hot/cold dual-arbiter
# architecture itself, or just unoptimized 16-bit counters/comparators.
# Run from the repo root:
#   genus -files syn/run_genus_adaptive_v2_lite.tcl

set DESIGN   aer_tx16_adaptive_v2_lite
set RTL_LIST {rtl/arbiter4.v rtl/aer_tx16_adaptive_v2_lite.v}
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
