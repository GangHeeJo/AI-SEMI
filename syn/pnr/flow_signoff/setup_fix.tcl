# hold ECO(hold_eco_swap.tcl) 뒤에 남은 setup 위반 1경로(-5 ps)만 setup 전용 후처리 최적화로 고친다.
# 입력: hold ECO를 끝낸 final.enc.dat + 그 Quantus SPEF. 출력: pnr/final.enc 등 갱신(이후 run_signoff.sh)
set TOP $::env(TOP)
restoreDesign pnr/final.enc.dat $TOP
setAnalysisMode -analysisType onChipVariation -cppr both
spefIn -rc_corner rc_typ pnr/${TOP}_quantus.spef
catch {deleteFiller -prefix FILLER}
setOptMode -setupTargetSlack 0.020
catch {optDesign -postRoute -setup}
catch {ecoRoute}
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
puts "SETUP_FIX_DONE $TOP"
exit
