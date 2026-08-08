# Standalone synthesis of arbiter4_greedy for direct area/timing comparison
# against arbiter4 (rotating) — verifies whether Boahen(2000)'s greedy/locality
# speed advantage actually shows up at our small (4-way, single-level) scale.
set DESIGN   arbiter4_greedy
set RTL_LIST {rtl/arbiter4_greedy.v}
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

exit
