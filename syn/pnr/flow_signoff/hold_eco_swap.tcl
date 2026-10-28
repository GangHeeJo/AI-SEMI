# hold ECO (셀 교체 방식): 버퍼를 새로 넣는 방식(hold_eco.tcl)은 메모리 배열 영역에 빈자리가 없어 합법화가 버퍼를 100~180 um 밖으로 밀어내
# Q 선이 길어지고 clk->Q가 2 ns가 되어 setup이 -0.18 ns로 깨졌다(progress.md §228). 새 자리가 필요 없게, 자기 루프의 hold mux를
# 같은 기능의 더 느린 셀로 바꾼다. 처음 시도한 MX2XL(면적 2.394)은 오히려 12 ps 빨라 hold가 -19 ps로 악화됐고,
# 후보 비교(progress.md §228)로 CLKMX2X4(면적 4.104 vs CLKMX2X2 3.078, hold +4 ps)를 선택했다.
# env: TOP, SWAP_CELL(기본 CLKMX2X4; MX2XL은 더 빨라 hold가 악화됨), HOLD_MARGIN(기본 0.005), ECO_ITER(기본 2)
set TOP $::env(TOP)
set NEWC [expr {[info exists ::env(SWAP_CELL)] ? $::env(SWAP_CELL) : "CLKMX2X4"}]
set MARGIN [expr {[info exists ::env(HOLD_MARGIN)] ? $::env(HOLD_MARGIN) : 0.005}]
set NIT [expr {[info exists ::env(ECO_ITER)] ? $::env(ECO_ITER) : 2}]
restoreDesign pnr/final.enc.dat $TOP
setAnalysisMode -analysisType onChipVariation -cppr both
spefIn -rc_corner rc_typ pnr/${TOP}_quantus.spef
catch {deleteFiller -prefix FILLER}
set done {}
for {set it 0} {$it < $NIT} {incr it} {
  set rpt pnr/eco_hold_pre$it.rpt
  report_timing -early -max_paths 20000 -nworst 1 -max_slack $MARGIN > $rpt
  set fh [open $rpt r]; set txt [read $fh]; close $fh
  set targets {}; set first 0
  foreach line [split $txt "\n"] {
    if {[regexp {^Path [0-9]+:} $line]} { set first 1; continue }
    if {$first && [regexp {^\s*\|\s+(\S+)\s+\|\s+(\S+)\s+[v^]\s+->\s+(\S+)\s+[v^]\s+\|\s+(\S+)\s+\|} $line -> inst pin outp cell]} {
      if {$pin ne "CK"} {
        if {($cell eq "CLKMX2X2" || $cell eq "MX2X1") && [lsearch -exact $done $inst] < 0 && [lsearch -exact $targets $inst] < 0} { lappend targets $inst } elseif {$cell ne "CLKMX2X2" && $cell ne "MX2X1"} { puts "ECO_SKIP $inst $cell" }
        set first 0
      }
    }
  }
  puts "ECO_ITER $it muxes_to_swap [llength $targets]"
  if {[llength $targets] == 0} break
  foreach inst $targets { if {[catch {ecoChangeCell -inst $inst -cell $NEWC} err]} { puts "ECO_SWAP_FAIL $inst $err" } else { lappend done $inst } }
  catch {ecoPlace}
  catch {ecoRoute}
  setAnalysisMode -analysisType onChipVariation -cppr both
  catch {extractRC}
}
puts "ECO_DONE_SWAPS [llength $done]"
catch {setFillerMode -core {FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1} -corePrefix FILLER}
catch {addFiller}
catch {ecoRoute}
catch {verify_drc -report pnr/eco_drc.rpt -limit 10000}
catch {verify_connectivity -type all -report pnr/eco_conn.rpt}
catch {verify_process_antenna -report pnr/eco_antenna.rpt}
catch {report_timing -early -max_paths 3 > pnr/eco_hold_internal.rpt}
catch {report_timing -max_paths 3 > pnr/eco_setup_internal.rpt}
catch {saveNetlist pnr/${TOP}_pnr.v}
catch {saveNetlist -includePowerGround pnr/${TOP}_pnr_pg.v}
catch {defOut -floorplan -netlist -routing pnr/$TOP.def}
catch {saveDesign pnr/final.enc}
puts "HOLD_ECO_DONE $TOP"
exit
