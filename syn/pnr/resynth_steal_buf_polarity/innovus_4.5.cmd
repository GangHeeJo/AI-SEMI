#######################################################
#                                                     
#  Innovus Command Logging File                     
#  Created on Mon Aug 24 09:15:19 2026                
#                                                     
#######################################################

#@(#)CDS: Innovus v23.14-s088_1 (64bit) 02/28/2025 12:25 (Linux 3.10.0-693.el7.x86_64)
#@(#)CDS: NanoRoute 23.14-s088_1 NR250219-0822/23_14-UB (database version 18.20.661) {superthreading v2.20}
#@(#)CDS: AAE 23.14-s018 (64bit) 02/28/2025 (Linux 3.10.0-693.el7.x86_64)
#@(#)CDS: CTE 23.14-s036_1 () Feb 22 2025 01:17:26 ( )
#@(#)CDS: SYNTECH 23.14-s010_1 () Feb 19 2025 23:56:49 ( )
#@(#)CDS: CPE v23.14-s082
#@(#)CDS: IQuantus/TQuantus 23.1.1-s336 (64bit) Mon Jan 20 22:11:00 PST 2025 (Linux 3.10.0-693.el7.x86_64)

set_global _enable_mmmc_by_default_flow      $CTE::mmmc_default
suppressMessage ENCEXT-2799
set init_lef_file {/home/aiasic26911/gsclib045_all_v4.7/gsclib045/lef/gsclib045_tech.lef /home/aiasic26911/gsclib045_all_v4.7/gsclib045/lef/gsclib045_macro.lef}
set init_verilog syn/pnr/resynth_steal_buf_polarity/aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_4.5_netlist.v
set init_top_cell aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity
set init_gnd_net VSS
set init_pwr_net VDD
set init_mmmc_file syn/pnr/resynth_steal_buf_polarity/mmmc_4.5.tcl
init_design
setDesignMode -process 45
set_dont_use [get_lib_cells */BUFX2] true
floorPlan -r 1.0 0.5 10 10 10 10
assignIoPins -pin {clk rst {arrival[15]} {arrival[14]} {arrival[13]} {arrival[12]} {arrival[11]} {arrival[10]} {arrival[9]} {arrival[8]} {arrival[7]} {arrival[6]} {arrival[5]} {arrival[4]} {arrival[3]} {arrival[2]} {arrival[1]} {arrival[0]} {polarity_in[15]} {polarity_in[14]} {polarity_in[13]} {polarity_in[12]} {polarity_in[11]} {polarity_in[10]} {polarity_in[9]} {polarity_in[8]} {polarity_in[7]} {polarity_in[6]} {polarity_in[5]} {polarity_in[4]} {polarity_in[3]} {polarity_in[2]} {polarity_in[1]} {polarity_in[0]} {overrun[15]} {overrun[14]} {overrun[13]} {overrun[12]} {overrun[11]} {overrun[10]} {overrun[9]} {overrun[8]} {overrun[7]} {overrun[6]} {overrun[5]} {overrun[4]} {overrun[3]} {overrun[2]} {overrun[1]} {overrun[0]} valid0 {row0[1]} {row0[0]} {col_mask0[3]} {col_mask0[2]} {col_mask0[1]} {col_mask0[0]} {pol_mask0[3]} {pol_mask0[2]} {pol_mask0[1]} {pol_mask0[0]} valid1 {row1[1]} {row1[0]} {col_mask1[3]} {col_mask1[2]} {col_mask1[1]} {col_mask1[0]} {pol_mask1[3]} {pol_mask1[2]} {pol_mask1[1]} {pol_mask1[0]}}
globalNetConnect VDD -type pgpin -pin VDD -inst * -verbose
globalNetConnect VSS -type pgpin -pin VSS -inst * -verbose
addRing -nets {VDD VSS} -type core_rings -layer {top Metal6 bottom Metal6 left Metal7 right Metal7} -width 2 -spacing 2 -offset 2
sroute -nets {VDD VSS} -connect {blockPin padPin corePin}
place_opt_design
clock_opt_design
routeDesign
extractRC
report_area > syn/pnr/resynth_steal_buf_polarity/aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_4.5_pnr_area.rpt
report_power > syn/pnr/resynth_steal_buf_polarity/aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_4.5_pnr_power.rpt
report_timing -late  > $OUT_DIR/aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_4.5_setup_timing.rpt
report_timing -early > $OUT_DIR/aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_4.5_hold_timing.rpt
check_timing -verbose > $OUT_DIR/aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_4.5_check_timing.rpt
verify_drc -report syn/pnr/resynth_steal_buf_polarity/aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_4.5_drc.rpt
write_db syn/pnr/resynth_steal_buf_polarity/aer_tx16_trad_rowcol_fovea_cluster2_steal_buf_polarity_4.5_db
