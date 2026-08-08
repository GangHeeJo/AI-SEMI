#!/bin/bash
# P&R(place+CTS+route) 레벨에서 진짜 Fmax를 재스윕 — 지금까지는 Genus 사전배치
# 추정(wireload model)으로만 스윕했음(1.2ns MET/1.15ns VIOLATED). 실제 배선
# 지연까지 반영된 post-route 타이밍으로 그 경계가 맞는지 재확인.
# 사용법: bash syn/sweep_pnr_fmax.sh <period1> <period2> ...
set -e
DESIGN=${DESIGN:-aer_tx16_trad_rowcol_fovea}
LIB_DIR=/home/aiasic26911/gsclib045_all_v4.7/gsclib045
OUT=syn/pnr/sweep
mkdir -p $OUT

for P in "$@"; do
  WAVE=$(echo "$P/2" | bc -l)
  SDC=$OUT/${DESIGN}_${P}.sdc
  sed "s/-period 5.0 -waveform {0.0 2.5}/-period $P -waveform {0.0 $WAVE}/" syn/reports/${DESIGN}_out.sdc > $SDC

  MMMC=$OUT/mmmc_${P}.tcl
  cat > $MMMC <<EOF
create_library_set -name libset_slow -timing "$LIB_DIR/timing/slow_vdd1v0_basicCells.lib"
create_rc_corner -name rc_typical -qrc_tech $LIB_DIR/qrc/qx/gpdk045.tch
create_delay_corner -name delay_slow -library_set libset_slow -rc_corner rc_typical
create_constraint_mode -name constraints_default -sdc_files {$SDC}
create_analysis_view -name view_slow -constraint_mode constraints_default -delay_corner delay_slow
set_analysis_view -setup {view_slow} -hold {view_slow}
EOF

  RUNTCL=$OUT/run_${P}.tcl
  cat > $RUNTCL <<EOF
set DESIGN $DESIGN
set OUT_DIR $OUT
set init_lef_file "$LIB_DIR/lef/gsclib045_tech.lef $LIB_DIR/lef/gsclib045_macro.lef"
set init_verilog syn/reports/${DESIGN}_netlist.v
set init_top_cell \$DESIGN
set init_gnd_net VSS
set init_pwr_net VDD
set init_mmmc_file $MMMC
init_design
setDesignMode -process 45
floorPlan -r 1.0 0.5 10 10 10 10
globalNetConnect VDD -type pgpin -pin VDD -inst * -verbose
globalNetConnect VSS -type pgpin -pin VSS -inst * -verbose
addRing -nets {VDD VSS} -type core_rings -layer {top Metal6 bottom Metal6 left Metal7 right Metal7} -width 2 -spacing 2 -offset 2
sroute -nets {VDD VSS} -connect {blockPin padPin corePin}
place_opt_design
clock_opt_design
routeDesign
extractRC
report_timing > \$OUT_DIR/${DESIGN}_${P}_timing.rpt
exit
EOF

  innovus -files $RUNTCL -log $OUT/innovus_${P}.log
  echo "period=$P:"
  grep -m1 "^Path 1:" $OUT/${DESIGN}_${P}_timing.rpt || echo "NO TIMING RESULT (check $OUT/innovus_${P}.log)"
done
