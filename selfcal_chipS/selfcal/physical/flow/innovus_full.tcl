# job25: chip_s_full P&R, 46 mem_bank_8k hard macros (16 world + 30 estimator planes), logic strip in the middle.
# env: TOP, UTIL (logic-region utilisation), MACRO_LEF, CH (channel um, default 20)
set TOP $::env(TOP)
set UTIL $::env(UTIL)
set G /home/aiasic26911/gsclib045_all_v4.7/gsclib045
set CH [expr {[info exists ::env(CH)] ? $::env(CH) : 20}]
file mkdir pnr
set init_lef_file [list $G/lef/gsclib045_tech.lef $G/lef/gsclib045_macro.lef $::env(MACRO_LEF)]
set init_verilog syn/$TOP.v
set init_top_cell $TOP
set init_pwr_net VDD
set init_gnd_net VSS
set init_mmmc_file mmmc.tcl
init_design
setDesignMode -process 45
foreach p {BUFX2 FSWNX1 FSWX1 HSWDNX1 HSWDX1 HSWNX1 HSWX1 PINVX1} { catch {setDontUse $p true} }
setMultiCpuUsage -localCpu 4

# ---- floorplan: 4 x 4 macro array on the left, standard-cell region on the right
set macros [lsort -dictionary [get_db [get_db insts -if {.base_cell.name == mem_bank_8k}] .name]]
puts "MACROS [llength $macros]"
set bb [get_db [get_db base_cells mem_bank_8k] .bbox]
set mw [expr {[lindex [lindex $bb 0] 2] - [lindex [lindex $bb 0] 0]}]
set mh [expr {[lindex [lindex $bb 0] 3] - [lindex [lindex $bb 0] 1]}]
set std_area 0.0
foreach a [get_db [get_db insts -if {.base_cell.class == core}] .area] { set std_area [expr {$std_area + $a}] }
# macro grid NC x NR with a square hole in the middle for the standard-cell logic, plus 2 extra slots on the right
set NC 8; set NR 6
set nm [llength $macros]
set slots {}
for {set c 0} {$c < $NC} {incr c} { for {set r 0} {$r < $NR} {incr r} {
  if {($c == 3 || $c == 4) && ($r == 2 || $r == 3)} { continue }
  lappend slots [list $c $r] } }
lappend slots [list $NC 0] [list $NC 1]
set coreW [expr {ceil((15 + ($NC + 1) * $mw + $NC * $CH) / 0.2) * 0.2}]
set coreH [expr {ceil(($NR * $mh + ($NR - 1) * $CH) / 1.71) * 1.71}]
puts "FLOORPLAN macro ${mw}x${mh} n $nm std_area $std_area core ${coreW}x${coreH} slots [llength $slots]"
floorPlan -site CoreSite -s $coreW $coreH 15 15 15 15
set i 0
foreach m $macros {
  set sl [lindex $slots $i]; set c [lindex $sl 0]; set r [lindex $sl 1]
  placeInstance $m [expr {15 + $c * ($mw + $CH)}] [expr {15 + $r * ($mh + $CH)}] R0
  setInstancePlacementStatus -name $m -status fixed
  addHaloToBlock 3 3 3 3 $m
  incr i
}
cutRow
globalNetConnect VDD -type pgpin -pin VDD -inst *
globalNetConnect VSS -type pgpin -pin VSS -inst *
globalNetConnect VDD -type tiehi
globalNetConnect VSS -type tielo
addRing -nets {VDD VSS} -type core_rings -layer {top Metal9 bottom Metal9 left Metal8 right Metal8} -width 3 -spacing 1.5 -offset 1.5
addStripe -nets {VDD VSS} -layer Metal8 -direction vertical -width 1.5 -spacing 1.5 -set_to_set_distance 40 -start_from left -start_offset 10
addStripe -nets {VDD VSS} -layer Metal7 -direction horizontal -width 1.5 -spacing 1.5 -set_to_set_distance 40 -start_from bottom -start_offset 10
sroute -nets {VDD VSS} -connect {corePin blockPin} -blockPin useLef -allowJogging 1 -allowLayerChange 1 -blockPinTarget nearestTarget
setPlaceMode -place_global_place_io_pins true
place_opt_design
saveDesign pnr/place.enc
clock_opt_design
catch {setOptMode -opt_hold_target_slack 0.05 -opt_hold_allow_setup_tns_degradation false}
optDesign -postCTS -hold
routeDesign
setAnalysisMode -analysisType onChipVariation -cppr both
optDesign -postRoute -setup -hold
saveDesign pnr/route.enc
catch {timeDesign -postRoute -hold -outDir pnr/timing_hold_a}
catch {timeDesign -postRoute -outDir pnr/timing_setup_a}
set dbb [get_db current_design .bbox]
puts "DIE_BBOX $dbb"
puts "INNOVUS_DONE $TOP"
exit
