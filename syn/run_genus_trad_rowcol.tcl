# Synthesize the "true traditional AER" (Mahowald 1992 row-then-column
# hierarchical arbitration, no Boahen-2004 burst batching) — third PPA
# comparison point alongside naive(flat) and base(row-col+burst).
#   genus -files syn/run_genus_trad_rowcol.tcl

set DESIGN   aer_tx16_trad_rowcol
set RTL_LIST {rtl/arbiter4.v rtl/aer_tx16_trad_rowcol.v}
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
