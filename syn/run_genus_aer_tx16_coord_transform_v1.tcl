# Digital 2차 통합판 v3(pose_fifo 추가 TX + FIFO/arbiter8 직렬화 + SRAM 스타일 단일 포트,
# progress.md §113/§114) Genus 합성. 저장소(world memory 4096칸)는 이제 이 RTL 밖에 있어서
# (world_we/world_addr/world_pol 인터페이스만 노출) 합성 PPA에 안 잡힘 -- v1(레지스터 배열
# 직접 합성)이 면적 98%를 먹었던 문제(§112)의 근본 해결.
#   genus -batch -files syn/run_genus_aer_tx16_coord_transform_v1.tcl

set DESIGN   aer_tx16_coord_transform_v1
set RTL_LIST {
  rtl/arbiter4_tree.v
  rtl/arbiter8.v
  rtl/small_fifo.v
  rtl/aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_pose.v
  rtl/coord_transform_rmcm.v
  rtl/world_mem_writer.v
  rtl/aer_tx16_coord_transform_v1.v
}
set SDC_FILE syn/constraints_5ns.sdc
set LIB_FILE /home/aiasic26911/gsclib045_all_v4.7/gsclib045/timing/slow_vdd1v0_basicCells.lib
set OUT_DIR  syn/reports

file mkdir $OUT_DIR

set_db library $LIB_FILE
set_db lp_insert_clock_gating true
set_db hdl_search_path rtl
set_db init_hdl_search_path .

read_hdl $RTL_LIST
elaborate $DESIGN
read_sdc $SDC_FILE

syn_generic
syn_map
syn_opt

report_area   > $OUT_DIR/${DESIGN}_area.rpt
report_timing > $OUT_DIR/${DESIGN}_timing.rpt
report_power  > $OUT_DIR/${DESIGN}_power.rpt
report_gates  > $OUT_DIR/${DESIGN}_gates.rpt

write_hdl > $OUT_DIR/${DESIGN}_netlist.v
write_sdc > $OUT_DIR/${DESIGN}_out.sdc

exit
