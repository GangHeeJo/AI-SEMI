# base(aer_tx16) 활동도 기반(VCD) 전력 측정 — 첫 시도.
# 먼저 로컬에서 tb/tb_aer16_base_vcd.v를 돌려 sim/vcd/aer_tx16_base.vcd를 만들고,
# 그 파일을 서버의 같은 경로(sim/vcd/)로 옮긴 뒤 이 스크립트를 실행한다.
#   scp sim/vcd/aer_tx16_base.vcd aiasic26911@210.126.11.79:~/redred-faer/sim/vcd/
#   genus -files syn/run_genus_base_power_vcd.tcl
# 처음 시도라 read_stimulus 문법/dut_instance 지정이 안 맞을 수 있음 — 실제 에러 보고 수정할 것.

set DESIGN   aer_tx16
set RTL_LIST {rtl/arbiter4.v rtl/aer_tx16.v}
set SDC_FILE syn/constraints_5ns.sdc
set LIB_FILE /home/aiasic26911/gsclib045_all_v4.7/gsclib045/timing/slow_vdd1v0_basicCells.lib
set VCD_FILE sim/vcd/aer_tx16_base.vcd
set OUT_DIR  syn/reports

file mkdir $OUT_DIR

set_db library $LIB_FILE

read_hdl $RTL_LIST
elaborate $DESIGN
read_sdc $SDC_FILE

syn_generic
syn_map
syn_opt

# VCD 최상위(tb_aer16_base_vcd) 안에서 실제 DUT는 "tx" 인스턴스이므로 그 전체 경로를
# 지정해서 신호를 매칭한다(help read_stimulus로 확인: -dut_instance는 전체 경로 필요,
# 예 "/cpu_10bit_tb/CPU"). vectorless 대신 진짜 스위칭 활동으로 전력을 계산.
read_stimulus -file $VCD_FILE -format vcd -dut_instance /tb_aer16_base_vcd/tx

report_power > $OUT_DIR/${DESIGN}_vcd_power.rpt

exit
