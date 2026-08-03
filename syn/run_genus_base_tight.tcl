# base(aer_tx16) timing-optimization pass: re-synthesize under a tight clock
# (see constraints_tight.sdc) to find the real max frequency instead of the
# loose 5ns number that left 2883ps of unused slack.
# Run from the repo root on the contest server:
#   genus -files syn/run_genus_base_tight.tcl

set DESIGN   aer_tx16
set RTL_LIST {rtl/arbiter4.v rtl/aer_tx16.v}
set SDC_FILE syn/constraints_tight.sdc
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

report_area   > $OUT_DIR/${DESIGN}_tight_area.rpt
report_timing > $OUT_DIR/${DESIGN}_tight_timing.rpt
report_power  > $OUT_DIR/${DESIGN}_tight_power.rpt
report_gates  > $OUT_DIR/${DESIGN}_tight_gates.rpt

write_hdl > $OUT_DIR/${DESIGN}_tight_netlist.v
write_sdc > $OUT_DIR/${DESIGN}_tight_out.sdc

exit
