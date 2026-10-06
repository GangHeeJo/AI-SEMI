# Parametric Genus synthesis. env: TOP, RTL (space-separated files), PER (ns), EXTRA_LIB (optional .lib list)
set TOP $::env(TOP)
set PER $::env(PER)
set LIBDIR /home/aiasic26911/gsclib045_all_v4.7/gsclib045/timing
set LIBS [list $LIBDIR/slow_vdd1v0_basicCells.lib]
if {[info exists ::env(EXTRA_LIB)] && $::env(EXTRA_LIB) ne ""} { foreach l $::env(EXTRA_LIB) { lappend LIBS $l } }
file mkdir syn
set_db library $LIBS
# cells on CoreSiteDouble (double-height, retention/level-shifter/BUFX2) -> no rows for them in a plain floorplan
set DBL {BUFX2 FSWNX1 FSWX1 HSWDNX1 HSWDX1 HSWNX1 HSWX1 PINVX1 RDFF* SRDFF* RTLAT* ISO* LSHL* LSLH*}
foreach p $DBL { foreach c [get_db lib_cells */$p] { set_db $c .dont_use true } }
# CG=1 -> Genus inserts clock gating (row-enable ICGs for memory banks)
set_db lp_insert_clock_gating [expr {[info exists ::env(CG)] && $::env(CG) eq "1"}]
set_db use_scan_seqs_for_non_dft false
read_hdl -sv $::env(RTL)
elaborate $TOP
check_design -unresolved
create_clock -name clk -period $PER [get_ports clk]
set_clock_uncertainty 0.10 [get_clocks clk]
set_input_delay  0.25 -clock clk [remove_from_collection [all_inputs] [get_ports clk]]
set_output_delay 0.25 -clock clk [all_outputs]
set_load 0.01 [all_outputs]
syn_generic
syn_map
syn_opt
report_area   > syn/area.rpt
report_timing > syn/timing.rpt
report_power  > syn/power.rpt
report_gates  > syn/gates.rpt
write_hdl > syn/$TOP.v
write_sdc > syn/$TOP.sdc
puts "GENUS_DONE $TOP"
exit
