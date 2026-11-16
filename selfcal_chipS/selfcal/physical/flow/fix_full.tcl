# job25: post-route hold ECO + DRC cleanup loop + filler + final outputs. env: TOP, FROM (route.enc | final.enc), HOLD_TGT, PASS (name)
set TOP $::env(TOP)
set FROM [expr {[info exists ::env(FROM)] ? $::env(FROM) : "route.enc"}]
set HT [expr {[info exists ::env(HOLD_TGT)] ? $::env(HOLD_TGT) : 0.05}]
set G /home/aiasic26911/gsclib045_all_v4.7/gsclib045
restoreDesign pnr/$FROM.dat $TOP
setMultiCpuUsage -localCpu 4
setAnalysisMode -analysisType onChipVariation -cppr both
catch {deleteFiller -prefix FILLER}
catch {report_clock_timing -type latency -view view_setup > pnr/latency_slow.rpt}
setExtractRCMode -engine postRoute -effortLevel high -coupled true
extractRC
catch {setOptMode -opt_hold_target_slack $HT -opt_hold_allow_setup_tns_degradation false -opt_setup_target_slack 0.02}
optDesign -postRoute -hold -outDir pnr/eco_hold
optDesign -postRoute -setup -hold -outDir pnr/eco_hold2
saveDesign pnr/eco.enc
# DRC cleanup loop (editDeleteViolations + ecoRoute), up to 3 passes
for {set k 1} {$k <= 3} {incr k} {
  verify_drc -report pnr/drc_pass$k.rpt -limit 10000
  set nv [llength [get_db markers -if {.subtype != Antenna}]]
  puts "DRC_PASS $k markers $nv"
  if {$nv == 0} { break }
  editDeleteViolations
  ecoRoute
}
setFillerMode -core {FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1} -corePrefix FILLER
addFiller
verify_drc -report pnr/drc_final.rpt -limit 10000
verify_connectivity -type all -report pnr/conn_final.rpt
verify_process_antenna -report pnr/antenna_final.rpt
extractRC
catch {timeDesign -postRoute -outDir pnr/timing_setup2}
catch {timeDesign -postRoute -hold -outDir pnr/timing_hold2}
catch {report_area > pnr/area_final.rpt}
catch {checkPlace > pnr/checkplace.rpt}
catch {set_default_switching_activity -input_activity 0.2 -seq_activity 0.1}
catch {report_power -view view_setup -outfile pnr/power_final.rpt}
saveNetlist pnr/${TOP}_pnr.v
defOut -floorplan -netlist -routing pnr/$TOP.def
write_sdf -view view_setup -min_view view_hold -max_view view_setup -typ_view view_setup pnr/$TOP.sdf
saveDesign pnr/final.enc
streamOut pnr/$TOP.gds -mapFile /tools/config/GPDK/gpdk045_v_6_0/soce/streamOut.map -merge [list $G/gds/gsclib045.gds $::env(MACRO_GDS)] -units 2000 -mode ALL
puts "FIX_DONE"
exit
