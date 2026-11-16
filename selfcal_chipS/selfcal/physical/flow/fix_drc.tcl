# job25 DRC fix: delete PG special vias flagged MaxViaStack / MinCut, nudge M7 spacing, re-verify, re-time, re-output. env TOP FROM
set TOP $::env(TOP)
set FROM [expr {[info exists ::env(FROM)] ? $::env(FROM) : "final"}]
set G /home/aiasic26911/gsclib045_all_v4.7/gsclib045
restoreDesign pnr/$FROM.enc.dat $TOP
setMultiCpuUsage -localCpu 8
setAnalysisMode -analysisType onChipVariation -cppr both
catch {deleteFiller -prefix FILLER}
clearDrc
verify_drc -report pnr/d2_pass0.rpt -limit 10000
puts "DRC_PASS0 [llength [get_db markers]]"
# Remove one mid-stack special via (M5_M4) at every MaxViaStack marker to split the over-tall PG via stack (M1..M9 corewire stacks)
set todel {}
foreach net {VDD VSS} {
  set cand {}
  foreach v [get_db net:$net .special_vias] { if {[string match M5_M4_* [get_db $v .via_def.name]]} { lappend cand $v; set px($v) [lindex [get_db $v .point] 0] } }
  foreach m [get_db markers -if {.subtype == MaxViaStack}] {
    if {![regexp "Net $net" [get_db $m .message]]} continue
    set b [lindex [get_db $m .bbox] 0]
    set cx [expr {([lindex $b 0]+[lindex $b 2])/2}]; set cy [expr {([lindex $b 1]+[lindex $b 3])/2}]
    foreach v $cand { set p $px($v); if {abs([lindex $p 0]-$cx) < 0.5 && abs([lindex $p 1]-$cy) < 0.5} { lappend todel $v; set info($v) [list $net $p [get_db $v .via_def.name]] } }
  }
}
set todel [lsort -unique $todel]
puts "FIX_todel [llength $todel]"
# Splitting rule: MAXVIASTACK 4 (Metal1..Metal9). The sroute corewire stacks M1..M9 sit on one XY. For every flagged stack move the
# M5_M4 cut sideways by an offset that has no foreign M4/M5 wire/via in the way (checked with get_obj_in_area); stacks that have no
# free offset are left untouched (stay as MaxViaStack items, PG connectivity preserved).
set HW 0.07; set SP 0.15
set offs {}
foreach d {0.3 0.45 0.6 0.9 1.2 1.8 2.4 3.6} { lappend offs [list $d 0] [list -$d 0] [list 0 $d] [list 0 -$d] }
set acc {}; set nacc 0; set nrej 0; set todel2 {}; set plan {}
foreach v $todel {
  lassign $info($v) net p vd
  set x [lindex $p 0]; set y [lindex $p 1]; set ok 0
  foreach off $offs {
    lassign $off ox oy
    set r [list [expr {min($x,$x+$ox)-$HW-$SP}] [expr {min($y,$y+$oy)-$HW-$SP}] [expr {max($x,$x+$ox)+$HW+$SP}] [expr {max($y,$y+$oy)+$HW+$SP}]]
    set foreign 0
    foreach o [dbQuery -area $r -objType wire] { if {[lsearch {Metal4 Metal5} [dbGet $o.layer.name]] >= 0} { incr foreign } }
    foreach o [dbQuery -area $r -objType sWire] { if {[lsearch {Metal4 Metal5} [dbGet $o.layer.name]] >= 0 && [dbGet $o.net.name] ne $net} { incr foreign } }
    if {$foreign} continue
    foreach q $acc { if {[lindex $r 0] < [lindex $q 2] && [lindex $r 2] > [lindex $q 0] && [lindex $r 1] < [lindex $q 3] && [lindex $r 3] > [lindex $q 1]} { set foreign 1; break } }
    if {$foreign} continue
    lappend acc $r; lappend plan [list $net $p $vd $ox $oy]; lappend todel2 $v; set ok 1; break
  }
  if {$ok} { incr nacc } else { incr nrej }
}
puts "FIX_plan accepted $nacc rejected $nrej"
deselectAll
select_obj $todel2
deleteSelectedFromFPlan
foreach e $plan {
  lassign $e net p vd ox oy
  set x [lindex $p 0]; set y [lindex $p 1]
  foreach L {Metal4 Metal5} { add_shape -layer $L -net $net -rect [list [expr {min($x,$x+$ox)-$HW}] [expr {min($y,$y+$oy)-$HW}] [expr {max($x,$x+$ox)+$HW}] [expr {max($y,$y+$oy)+$HW}]] -shape corewire -status routed }
  add_via -net $net -pt [list [expr {$x+$ox}] [expr {$y+$oy}]] -via $vd -shape corewire
}
# remaining M7 stub wires (MinCut / spacing): delete the stub wire + its single via
set sel {}
foreach {net rx0 ry0 vx vy vdef} {
  VDD 1624.785 1064.89 1624.785 1064.95 M7_M6_26
  VDD 1624.785 1786.51 1624.785 1786.57 M7_M6_26
  VSS 658.7 1784.515 658.7 1784.575 M7_M6_39 } {
  foreach w [get_db net:$net .special_wires] {
    if {[get_db $w .layer.name] ne "Metal7"} continue
    set r [lindex [get_db $w .rect] 0]
    if {abs([lindex $r 0]-$rx0) < 0.01 && abs([lindex $r 1]-$ry0) < 0.01} { lappend sel $w }
  }
  foreach v [get_db net:$net .special_vias] {
    set p [lindex [get_db $v .point] 0]
    if {abs([lindex $p 0]-$vx) < 0.01 && abs([lindex $p 1]-$vy) < 0.01 && [get_db $v .via_def.name] eq $vdef} { lappend sel $v }
  }
}
puts "FIX_stub [llength $sel]"
deselectAll
select_obj $sel
deleteSelectedFromFPlan
clearDrc
verify_drc -report pnr/d2_pass1.rpt -limit 10000
puts "DRC_PRE_FILLER [llength [get_db markers]]"
setFillerMode -core {FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1} -corePrefix FILLER
addFiller
clearDrc
verify_drc -report pnr/drc_final2.rpt -limit 10000
puts "DRC_FINAL2 [llength [get_db markers]]"
verify_connectivity -type all -report pnr/conn_final2.rpt
verify_process_antenna -report pnr/antenna_final2.rpt
setExtractRCMode -engine postRoute -effortLevel high -coupled true
extractRC
catch {timeDesign -postRoute -outDir pnr/timing_setup3}
catch {timeDesign -postRoute -hold -outDir pnr/timing_hold3}
catch {report_area > pnr/area_final2.rpt}
catch {checkPlace > pnr/checkplace2.rpt}
catch {set_default_switching_activity -input_activity 0.2 -seq_activity 0.1}
catch {report_power -view view_setup -outfile pnr/power_final2.rpt}
saveNetlist pnr/${TOP}_pnr2.v
defOut -floorplan -netlist -routing pnr/${TOP}2.def
write_sdf -view view_setup -min_view view_hold -max_view view_setup -typ_view view_setup pnr/${TOP}2.sdf
saveDesign pnr/final2.enc
streamOut pnr/${TOP}2.gds -mapFile /tools/config/GPDK/gpdk045_v_6_0/soce/streamOut.map -merge [list $G/gds/gsclib045.gds $::env(MACRO_GDS)] -units 2000 -mode ALL
puts "FIX2_DONE"
exit
