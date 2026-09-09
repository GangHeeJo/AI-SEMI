# Digital 2차 통합판(steal_buf_polarity + coord_transform_rmcm x8 + world_mem_writer) Genus 합성.
# coord_transform_rmcm 8레인 병렬 복제 비용이 실제로 얼마나 드는지 실측하기 위함
# (단독 RMCM 1개 PPA: area 1199.052/795 cells, power 0.041372mW, §110).
#   genus -batch -files syn/run_genus_aer_tx16_coord_transform_v1.tcl

set DESIGN   aer_tx16_coord_transform_v1
set RTL_LIST {
  rtl/arbiter4_tree.v
  rtl/aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity.v
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
