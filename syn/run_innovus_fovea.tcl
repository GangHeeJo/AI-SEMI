# P&R(place&route)까지 확장 — 클록트리 실제 합성으로 멀티비트 DFF 등 물리 단계
# 최적화 이득이 실제로 잡히는지 확인. Genus 합성 넷리스트(aer_tx16_trad_rowcol_fovea,
# 클록게이팅 포함 최종본)를 입력으로 씀.
#   innovus -files syn/run_innovus_fovea.tcl

set DESIGN aer_tx16_trad_rowcol_fovea
set LIB_DIR /home/aiasic26911/gsclib045_all_v4.7/gsclib045
set OUT_DIR syn/pnr
file mkdir $OUT_DIR

set init_lef_file "$LIB_DIR/lef/gsclib045_tech.lef $LIB_DIR/lef/gsclib045_macro.lef"
set init_verilog syn/reports/aer_tx16_trad_rowcol_fovea_netlist.v
set init_top_cell $DESIGN
set init_gnd_net VSS
set init_pwr_net VDD
set init_mmmc_file syn/mmmc_fovea.tcl

init_design

setDesignMode -process 45

floorPlan -r 1.0 0.5 10 10 10 10

# 전력배선(power planning) — 처음엔 생략했다가(빠른 검증용) "할 수 있는 건 다 하자"는
# 방침으로 추가. globalNetConnect로 논리적 PG 연결 → addRing으로 코어 둘레 링 →
# sroute로 스탠다드셀 레일을 링에 실제 연결.
globalNetConnect VDD -type pgpin -pin VDD -inst * -verbose
globalNetConnect VSS -type pgpin -pin VSS -inst * -verbose

addRing -nets {VDD VSS} -type core_rings -layer {top Metal6 bottom Metal6 left Metal7 right Metal7} \
  -width 2 -spacing 2 -offset 2

sroute -nets {VDD VSS} -connect {blockPin padPin corePin}

place_opt_design

clock_opt_design

routeDesign

# 배선 후 진짜 기생커패시턴스로 재추출(qrc tech 기반, PreRoute 추정보다 정확) —
# 정확도를 최대한 끌어올림.
extractRC

report_area > $OUT_DIR/${DESIGN}_pnr_area.rpt
report_power > $OUT_DIR/${DESIGN}_pnr_power.rpt
report_timing > $OUT_DIR/${DESIGN}_pnr_timing.rpt

exit
