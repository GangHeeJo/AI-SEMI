# Parametric Innovus P&R + extraction + signoff-ish checks.
# env: TOP, UTIL (core util, e.g. 0.6), EXTRA_LEF (optional macro LEF list), MACRO_PLACE (optional tcl file)
set TOP $::env(TOP)
set UTIL $::env(UTIL)
set G /home/aiasic26911/gsclib045_all_v4.7/gsclib045
file mkdir pnr
set lefs [list $G/lef/gsclib045_tech.lef $G/lef/gsclib045_macro.lef]
if {[info exists ::env(EXTRA_LEF)] && $::env(EXTRA_LEF) ne ""} { foreach l $::env(EXTRA_LEF) { lappend lefs $l } }
set init_lef_file $lefs
set init_verilog syn/$TOP.v
set init_top_cell $TOP
set init_pwr_net VDD
set init_gnd_net VSS
set init_mmmc_file mmmc.tcl
if {[info exists ::env(RESUME)] && $::env(RESUME) eq "route"} {
  restoreDesign pnr/route.enc.dat $TOP
} else {
init_design
setDesignMode -process 45
foreach p {BUFX2 FSWNX1 FSWX1 HSWDNX1 HSWDX1 HSWNX1 HSWX1 PINVX1} { catch {setDontUse $p true} }
setMultiCpuUsage -localCpu 4
floorPlan -site CoreSite -r 1.0 $UTIL 12 12 12 12
if {[info exists ::env(MACRO_PLACE)] && $::env(MACRO_PLACE) ne ""} { source $::env(MACRO_PLACE) }
globalNetConnect VDD -type pgpin -pin VDD -inst * 
globalNetConnect VSS -type pgpin -pin VSS -inst *
globalNetConnect VDD -type tiehi
globalNetConnect VSS -type tielo
addRing -nets {VDD VSS} -type core_rings -layer {top Metal9 bottom Metal9 left Metal8 right Metal8} -width 2 -spacing 1 -offset 1
addStripe -nets {VDD VSS} -layer Metal8 -direction vertical -width 1 -spacing 1 -set_to_set_distance 40 -start_from left -start_offset 10
sroute -nets {VDD VSS} -connect {corePin blockPin} -allowJogging 1 -allowLayerChange 1
setPlaceMode -place_global_place_io_pins true
place_opt_design
saveDesign pnr/place.enc
clock_opt_design
optDesign -postCTS -hold
routeDesign
setAnalysisMode -analysisType onChipVariation -cppr both
optDesign -postRoute -setup -hold
setFillerMode -core {FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1} -corePrefix FILLER
addFiller
ecoRoute
saveDesign pnr/route.enc
}
# --- extraction: signoff (Quantus) -> high (IQuantus) -> low; record which one worked
set ext none
foreach eff {signoff high low} {
  if {![catch {setExtractRCMode -engine postRoute -effortLevel $eff -coupled true; extractRC} err]} { set ext $eff; break }
  puts "EXTRACT_FAILED_$eff: $err"
}
puts "EXTRACT_MODE $ext"
catch {rcOut -spef pnr/$TOP.spef -rc_corner rc_typ}
# --- post-route timing/power with extracted RC
catch {timeDesign -postRoute -outDir pnr/timing_setup}
catch {timeDesign -postRoute -hold -outDir pnr/timing_hold}
catch {report_timing -max_paths 5 > pnr/setup.rpt}
catch {report_timing -early -max_paths 5 > pnr/hold.rpt}
catch {report_area > pnr/area.rpt}
catch {set_default_switching_activity -input_activity 0.2 -seq_activity 0.1}
catch {report_power -view view_setup -outfile pnr/power.rpt}
catch {checkPlace > pnr/checkplace.rpt}
catch {verify_drc -report pnr/drc.rpt -limit 10000}
catch {verify_connectivity -type all -report pnr/conn.rpt}
catch {verify_process_antenna -report pnr/antenna.rpt}
catch {write_sdf -view view_setup -min_view view_hold -max_view view_setup -typ_view view_setup pnr/$TOP.sdf}
catch {saveNetlist pnr/${TOP}_pnr.v}
catch {saveNetlist -includePowerGround pnr/${TOP}_pnr_pg.v}
catch {defOut -floorplan -netlist -routing pnr/$TOP.def}
set gdsmerge [list $G/gds/gsclib045.gds]
if {[info exists ::env(EXTRA_GDS)] && $::env(EXTRA_GDS) ne ""} { foreach g $::env(EXTRA_GDS) { lappend gdsmerge $g } }
catch {streamOut pnr/$TOP.gds -mapFile /tools/config/GPDK/gpdk045_v_6_0/soce/streamOut.map -merge $gdsmerge -units 2000 -mode ALL}
catch {summaryReport -noHtml -outfile pnr/summary.rpt}
catch {saveDesign pnr/final.enc}
puts "INNOVUS_DONE $TOP"
exit
