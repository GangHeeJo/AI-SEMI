# job25 task 2: clear the 26 remaining PG MaxViaStack markers of final2 by splitting the M1..M9 corewire stack at a different cut.
# Stack = Via1..Via8 on one XY (max 4 allowed). Candidates to remove+relocate (a<=4 and b<=4 cuts remain on both sides):
#   level A: M6_M5 cut (wires Metal5/Metal6), level B: M4_M3 cut (wires Metal3/Metal4), level C: M5_M4 (Metal4/Metal5, already tried in final2)
# Relocation offsets are validated first (dbQuery: no foreign regular wire / other-net special wire on the two layers near the new stub),
# nothing is deleted unless a free offset exists, so the PG net stays connected.
set TOP chip_s_full
set FROM [expr {[info exists ::env(FROM)] ? $::env(FROM) : "final2"}]
restoreDesign pnr/$FROM.enc.dat $TOP
setMultiCpuUsage -localCpu 8
setAnalysisMode -analysisType onChipVariation -cppr both
catch {deleteFiller -prefix FILLER}
clearDrc
verify_drc -report pnr/d3_pass0.rpt -limit 10000
puts "DRC_PASS0 [llength [get_db markers]]"
set marks {}
foreach m [get_db markers -if {.subtype == MaxViaStack}] {
  set b [lindex [get_db $m .bbox] 0]
  regexp {Net (VDD|VSS)} [get_db $m .message] -> net
  lappend marks [list $net [expr {([lindex $b 0]+[lindex $b 2])/2}] [expr {([lindex $b 1]+[lindex $b 3])/2}]]
}
puts "FIX3_marks [llength $marks]"
set levels {{M6_M5_ Metal5 Metal6} {M4_M3_ Metal3 Metal4} {M5_M4_ Metal4 Metal5}}
set HW 0.07; set SP [expr {[info exists ::env(SP)] ? $::env(SP) : 0.15}]
set offs {}
foreach d {0.3 0.45 0.6 0.9 1.2 1.8 2.4 3.6 5.0 7.0 10.0} { lappend offs [list $d 0] [list -$d 0] [list 0 $d] [list 0 -$d] }
# index special vias by net for the needed cut prefixes
foreach net {VDD VSS} { foreach v [get_db net:$net .special_vias] {
  set dn [get_db $v .via_def.name]
  foreach lv $levels { if {[string match "[lindex $lv 0]*" $dn]} { set p [lindex [get_db $v .point] 0]; lappend cutlist($net,[lindex $lv 0]) [list $v $p $dn] } }
} }
set remaining $marks; set acc {}; set plan {}; set todel {}
foreach lv $levels {
  lassign $lv pre L1 L2
  set next {}
  foreach mk $remaining {
    lassign $mk net cx cy
    set found ""
    foreach e $cutlist($net,$pre) { lassign $e v p dn; if {abs([lindex $p 0]-$cx) < 0.5 && abs([lindex $p 1]-$cy) < 0.5} { set found $e; break } }
    if {$found eq ""} { lappend next $mk; continue }
    lassign $found v p dn
    set x [lindex $p 0]; set y [lindex $p 1]; set ok 0
    foreach off $offs {
      lassign $off ox oy
      set r [list [expr {min($x,$x+$ox)-$HW-$SP}] [expr {min($y,$y+$oy)-$HW-$SP}] [expr {max($x,$x+$ox)+$HW+$SP}] [expr {max($y,$y+$oy)+$HW+$SP}]]
      set foreign 0
      foreach o [dbQuery -area $r -objType wire] { if {[lsearch [list $L1 $L2] [dbGet $o.layer.name]] >= 0} { incr foreign } }
      foreach o [dbQuery -area $r -objType sWire] { if {[lsearch [list $L1 $L2] [dbGet $o.layer.name]] >= 0 && [dbGet $o.net.name] ne $net} { incr foreign } }
      if {$foreign} continue
      foreach q $acc { if {[lindex $r 0] < [lindex $q 2] && [lindex $r 2] > [lindex $q 0] && [lindex $r 1] < [lindex $q 3] && [lindex $r 3] > [lindex $q 1]} { set foreign 1; break } }
      if {$foreign} continue
      lappend acc $r; lappend plan [list $net $p $dn $ox $oy $L1 $L2]; lappend todel $v; set ok 1; break
    }
    if {!$ok} { lappend next $mk }
  }
  puts "FIX3_level $pre remaining_before [llength $remaining] after [llength $next]"
  set remaining $next
}
puts "FIX3_plan [llength $plan] unresolved [llength $remaining]"
foreach mk $remaining { puts "FIX3_unres $mk" }
deselectAll
select_obj $todel
deleteSelectedFromFPlan
foreach e $plan {
  lassign $e net p vd ox oy L1 L2
  set x [lindex $p 0]; set y [lindex $p 1]
  foreach L [list $L1 $L2] { add_shape -layer $L -net $net -rect [list [expr {min($x,$x+$ox)-$HW}] [expr {min($y,$y+$oy)-$HW}] [expr {max($x,$x+$ox)+$HW}] [expr {max($y,$y+$oy)+$HW}]] -shape corewire -status routed }
  add_via -net $net -pt [list [expr {$x+$ox}] [expr {$y+$oy}]] -via $vd -shape corewire
}
clearDrc
verify_drc -report pnr/d3_pass1.rpt -limit 10000
puts "DRC_PRE_FILLER [llength [get_db markers]]"
setFillerMode -core {FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1} -corePrefix FILLER
addFiller
clearDrc
verify_drc -report pnr/drc_final3.rpt -limit 10000
puts "DRC_FINAL3 [llength [get_db markers]]"
verify_connectivity -type all -report pnr/conn_final3.rpt
verify_process_antenna -report pnr/antenna_final3.rpt
setExtractRCMode -engine postRoute -effortLevel high -coupled true
extractRC
catch {timeDesign -postRoute -outDir pnr/timing_setup4}
catch {timeDesign -postRoute -hold -outDir pnr/timing_hold4}
catch {report_area > pnr/area_final3.rpt}
catch {checkPlace > pnr/checkplace3.rpt}
catch {set_default_switching_activity -input_activity 0.2 -seq_activity 0.1}
catch {report_power -view view_setup -outfile pnr/power_final3.rpt}
saveNetlist pnr/${TOP}_pnr3.v
defOut -floorplan -netlist -routing pnr/${TOP}3.def
write_sdf -view view_setup -min_view view_hold -max_view view_setup -typ_view view_setup pnr/${TOP}3.sdf
saveDesign pnr/final3.enc
streamOut pnr/${TOP}3.gds -mapFile /tools/config/GPDK/gpdk045_v_6_0/soce/streamOut.map -merge [list /home/aiasic26911/gsclib045_all_v4.7/gsclib045/gds/gsclib045.gds $::env(MACRO_GDS)] -units 2000 -mode ALL
puts "FIX3_DONE"
exit
