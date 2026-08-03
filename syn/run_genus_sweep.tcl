# 클럭 주기를 바꿔가며 진짜 Fmax(타이밍이 깨지기 직전 지점)를 찾기 위한 범용 스크립트.
# DESIGN/RTL_LIST/CLK_PERIOD를 환경변수로 받는다(sweep_fmax.sh가 채워줌).
#   AER_DESIGN=aer_tx16 AER_RTL_LIST="rtl/arbiter4.v rtl/aer_tx16.v" AER_CLK_PERIOD=1.5 \
#     genus -files syn/run_genus_sweep.tcl

set DESIGN     $::env(AER_DESIGN)
set RTL_LIST   $::env(AER_RTL_LIST)
set CLK_PERIOD $::env(AER_CLK_PERIOD)
set LIB_FILE   /home/aiasic26911/gsclib045_all_v4.7/gsclib045/timing/slow_vdd1v0_basicCells.lib
set OUT_DIR    syn/sweep

file mkdir $OUT_DIR

set_db library $LIB_FILE

read_hdl $RTL_LIST
elaborate $DESIGN

# I/O 지연·불확실성은 5ns 기준 SDC와 동일하게 고정 — 클럭 주기만 바꿔서 진짜 한계를 찾는다.
create_clock -name clk -period $CLK_PERIOD [get_ports clk]
set_clock_uncertainty 0.100 [get_clocks clk]
set_input_delay  -clock clk 0.250 [remove_from_collection [all_inputs] [get_ports clk]]
set_output_delay -clock clk 0.250 [all_outputs]
set_load 0.010 [all_outputs]

syn_generic
syn_map
syn_opt

report_area   > $OUT_DIR/${DESIGN}_${CLK_PERIOD}_area.rpt
report_timing > $OUT_DIR/${DESIGN}_${CLK_PERIOD}_timing.rpt

exit
