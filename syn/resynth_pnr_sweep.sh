#!/bin/bash
# per_target_resynthesis 공식 방법론(준영 문서 4-D) — 주기(period)마다 Genus 재합성부터
# 새로 하고, 그 넷리스트로 floorplan->place->CTS->route->extractRC까지 완주. 기존
# sweep_pnr_fmax.sh(fixed-netlist, 진단용)와 달리 매 지점마다 합성을 다시 함.
# setup/hold timing, DRC, antenna, unconstrained path까지 확인(준영 문서 요구사항).
# 사용법: bash syn/resynth_pnr_sweep.sh <period1> <period2> ...
set -e
DESIGN=${DESIGN:-aer_tx16_trad_rowcol_fovea}
RTL_LIST=${RTL_LIST:-"rtl/arbiter2.v rtl/arbiter4_tree.v rtl/aer_tx16_trad_rowcol_fovea.v"}
LIB_DIR=/home/aiasic26911/gsclib045_all_v4.7/gsclib045
LIB_FILE=$LIB_DIR/timing/slow_vdd1v0_basicCells.lib
OUT=${OUT:-syn/pnr/resynth}
mkdir -p $OUT

for P in "$@"; do
  echo "=== period=$P: Genus resynthesis ==="
  SDC=$OUT/${DESIGN}_${P}.sdc
  sed "s/-period 5.000/-period $P/" syn/constraints_5ns.sdc > $SDC

  GENUS_TCL=$OUT/genus_${P}.tcl
  cat > $GENUS_TCL <<EOF
set DESIGN   $DESIGN
set RTL_LIST {$RTL_LIST}
set SDC_FILE $SDC
set LIB_FILE $LIB_FILE
set OUT_DIR  $OUT

set_db library \$LIB_FILE
set_db lp_insert_clock_gating true

read_hdl \$RTL_LIST
elaborate \$DESIGN
read_sdc \$SDC_FILE

syn_generic
syn_map
syn_opt

report_area   > \$OUT_DIR/${DESIGN}_${P}_area.rpt
report_timing > \$OUT_DIR/${DESIGN}_${P}_gtiming.rpt
report_power  > \$OUT_DIR/${DESIGN}_${P}_gpower.rpt

write_hdl > \$OUT_DIR/${DESIGN}_${P}_netlist.v
write_sdc > \$OUT_DIR/${DESIGN}_${P}_out.sdc
exit
EOF

  genus -batch -files $GENUS_TCL -log $OUT/genus_${P}.log

  if [[ ! -s $OUT/${DESIGN}_${P}_netlist.v ]]; then
    echo "period=$P: GENUS FAILED (check $OUT/genus_${P}.log)"
    continue
  fi

  echo "=== period=$P: Innovus P&R ==="
  MMMC=$OUT/mmmc_${P}.tcl
  cat > $MMMC <<EOF
create_library_set -name libset_slow -timing "$LIB_FILE"
create_rc_corner -name rc_typical -qrc_tech $LIB_DIR/qrc/qx/gpdk045.tch
create_delay_corner -name delay_slow -library_set libset_slow -rc_corner rc_typical
create_constraint_mode -name constraints_default -sdc_files {$OUT/${DESIGN}_${P}_out.sdc}
create_analysis_view -name view_slow -constraint_mode constraints_default -delay_corner delay_slow
set_analysis_view -setup {view_slow} -hold {view_slow}
EOF

  RUNTCL=$OUT/run_${P}.tcl
  cat > $RUNTCL <<EOF
set DESIGN $DESIGN
set OUT_DIR $OUT
set init_lef_file "$LIB_DIR/lef/gsclib045_tech.lef $LIB_DIR/lef/gsclib045_macro.lef"
set init_verilog $OUT/${DESIGN}_${P}_netlist.v
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

report_area  > \$OUT_DIR/${DESIGN}_${P}_pnr_area.rpt
report_power > \$OUT_DIR/${DESIGN}_${P}_pnr_power.rpt
report_timing -late  > \$OUT_DIR/${DESIGN}_${P}_setup_timing.rpt
report_timing -early > \$OUT_DIR/${DESIGN}_${P}_hold_timing.rpt
catch {check_timing -verbose > \$OUT_DIR/${DESIGN}_${P}_check_timing.rpt}
catch {verify_drc -report \$OUT_DIR/${DESIGN}_${P}_drc.rpt}
catch {verify_process_antenna -report \$OUT_DIR/${DESIGN}_${P}_antenna.rpt}
catch {write_db \$OUT_DIR/${DESIGN}_${P}_db}
exit
EOF

  innovus -files $RUNTCL -log $OUT/innovus_${P}.log
  echo "period=$P done:"
  grep -m1 "^Path 1:" $OUT/${DESIGN}_${P}_setup_timing.rpt || echo "NO SETUP TIMING RESULT (check $OUT/innovus_${P}.log)"
done

echo "ALL PERIODS DONE"
