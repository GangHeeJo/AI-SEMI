# 1차 흐름(syn/pnr/resynth_steal_buf_polarity/run_*.tcl)과 같은 순서 + 배선 후 setup/hold 최적화. 실행: cd ~/redred-faer && innovus -no_gui -batch -files syn/pnr/coord_v1_mem/run.tcl < /dev/null
set DESIGN aer_tx16_coord_transform_v1_mem
set OUT_DIR syn/pnr/coord_v1_mem
set init_lef_file "/home/aiasic26911/gsclib045_all_v4.7/gsclib045/lef/gsclib045_tech.lef /home/aiasic26911/gsclib045_all_v4.7/gsclib045/lef/gsclib045_macro.lef"
set init_verilog $OUT_DIR/${DESIGN}_netlist.v
set init_top_cell $DESIGN
set init_gnd_net VSS
set init_pwr_net VDD
set init_mmmc_file $OUT_DIR/mmmc.tcl
init_design
setDesignMode -process 45
set_dont_use [get_lib_cells */BUFX2] true
floorPlan -r 1.0 0.5 10 10 10 10
assignIoPins -pin [dbGet top.terms.name]
globalNetConnect VDD -type pgpin -pin VDD -inst * -verbose
globalNetConnect VSS -type pgpin -pin VSS -inst * -verbose
addRing -nets {VDD VSS} -type core_rings -layer {top Metal6 bottom Metal6 left Metal7 right Metal7} -width 2 -spacing 2 -offset 2
sroute -nets {VDD VSS} -connect {blockPin padPin corePin}
place_opt_design
clock_opt_design
routeDesign
setExtractRCMode -engine postRoute
extractRC
setAnalysisMode -analysisType onChipVariation -cppr both
setOptMode -holdTargetSlack 0.020 -setupTargetSlack 0.030
optDesign -postRoute -setup -hold
catch {ecoRoute -fix_drc}
extractRC
optDesign -postRoute -hold
extractRC
report_area  > $OUT_DIR/${DESIGN}_pnr_area.rpt
report_power > $OUT_DIR/${DESIGN}_pnr_power.rpt
report_timing -late  > $OUT_DIR/${DESIGN}_setup_timing.rpt
report_timing -early > $OUT_DIR/${DESIGN}_hold_timing.rpt
catch {report_timing -late  -max_paths 1 -view view_slow > $OUT_DIR/${DESIGN}_wns_setup.rpt}
catch {check_timing -verbose > $OUT_DIR/${DESIGN}_check_timing.rpt}
catch {verify_drc -report $OUT_DIR/${DESIGN}_drc.rpt}
catch {verify_connectivity -report $OUT_DIR/${DESIGN}_conn.rpt}
catch {verify_process_antenna -report $OUT_DIR/${DESIGN}_antenna.rpt}
catch {saveDesign $OUT_DIR/${DESIGN}.enc -mmmc2}
catch {streamOut $OUT_DIR/${DESIGN}.gds -mapFile /tools/config/GPDK/gpdk045_v_6_0/soce/streamOut.map -libName DesignLib -merge {/home/aiasic26911/gsclib045_all_v4.7/gsclib045/gds/gsclib045.gds}}
catch {write_sdf $OUT_DIR/${DESIGN}.sdf}
exit
