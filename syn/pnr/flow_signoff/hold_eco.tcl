# 목표 지정 hold ECO: 저장된 P&R(final.enc.dat)에서 hold 슬랙이 HOLD_MARGIN 미만인 끝점(D 핀)에만 지연 버퍼를 넣는다.
# (전체 최적화 optDesign -hold 는 이 경로(플립플롭 자기 루프 Q->MX2->D)를 못 고치고 setup만 깼음, progress.md §224)
# env: TOP, ECO_CELL(기본 BUFX3), HOLD_MARGIN(기본 0.030), ECO_ITER(기본 3)
set TOP $::env(TOP)
set CELL [expr {[info exists ::env(ECO_CELL)] ? $::env(ECO_CELL) : "BUFX3"}]
set MARGIN [expr {[info exists ::env(HOLD_MARGIN)] ? $::env(HOLD_MARGIN) : 0.030}]
set NIT [expr {[info exists ::env(ECO_ITER)] ? $::env(ECO_ITER) : 3}]
restoreDesign pnr/final.enc.dat $TOP
setAnalysisMode -analysisType onChipVariation -cppr both
spefIn -rc_corner rc_typ pnr/${TOP}_quantus.spef
# 저장된 DB는 필러가 채워져 있어(밀도 100%) 버퍼를 못 놓으므로 필러를 지우고 ECO 후 다시 채운다
catch {deleteFiller -prefix FILLER}
set done {}
for {set it 0} {$it < $NIT} {incr it} {
  set rpt pnr/eco_hold_pre$it.rpt
  report_timing -early -max_paths 20000 -nworst 1 -max_slack $MARGIN > $rpt
  set fh [open $rpt r]; set txt [read $fh]; close $fh
  # 위반 경로마다 launch 플립플롭 뒤 첫 게이트의 입력 핀(자기 루프의 feedback 입력)에만 버퍼를 넣는다.
  # (끝점 D 핀에 넣으면 같은 D로 들어오는 긴 enable 경로(setup 여유 0.08 ns)까지 느려져 setup이 -0.83 ns로 깨졌음)
  set eps {}; set first 0; array unset bpof; set bp {}
  foreach line [split $txt "
"] {
    if {[regexp {^Path [0-9]+:} $line]} { set first 1; continue }
    regexp {^Beginpoint:\s+(\S+)/Q\s} $line -> bp
    if {$first && [regexp {^\s*\|\s+(\S+)\s+\|\s+(\S+)\s+[v^]\s+->\s+(\S+)\s+[v^]\s+\|\s+(\S+)\s+\|} $line -> inst pin outp cell]} {
      if {$pin ne "CK"} { set tp "$inst/$pin"; if {[lsearch -exact $done $tp] < 0 && [lsearch -exact $eps $tp] < 0} { lappend eps $tp; set bpof($tp) $bp }; set first 0 }
    }
  }
  puts "ECO_ITER $it endpoints_to_fix [llength $eps]"
  if {[llength $eps] == 0} break
  setEcoMode -batchMode true -updateTiming false
  # 버퍼는 launch 플립플롭(Q 선의 드라이버) 바로 옆에 놓는다: Q 선은 짧게, 버퍼 출력에서 mux까지의 긴 선은 버퍼가 구동.
  # (위치 미지정: die 가장자리에 놓여 Q 선이 길어짐 / mux 옆: Q 선이 길어짐 -> 둘 다 clk->Q가 2 ns로 늘어 setup이 깨졌음. 원본 P&R의 FE_PHC 버퍼도 플립플롭 옆에 있음)
  foreach pin $eps {
    set inst $bpof($pin)
    set pt [lindex [dbGet [dbGetInstByName $inst].pt] 0]
    if {[catch {ecoAddRepeater -term $pin -cell $CELL -loc $pt} err]} { puts "ECO_ADD_FAIL $pin $err" } else { lappend done $pin }
  }
  setEcoMode -batchMode false
  catch {ecoPlace}
  catch {ecoRoute}
  setAnalysisMode -analysisType onChipVariation -cppr both
  catch {extractRC}
}
puts "ECO_DONE_ENDPOINTS [llength $done]"
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
