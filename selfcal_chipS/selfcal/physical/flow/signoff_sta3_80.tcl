# job25 final: final3 DB re-timed at 8.0 ns with the Quantus SPEF of final3 (setup slow lib / hold fast lib), signoff SDF
set TOP chip_s_full
restoreDesign pnr/final3.enc.dat $TOP
setMultiCpuUsage -localCpu 8
update_constraint_mode -name cm -sdc_files syn/chip_s_full_80.sdc
set_interactive_constraint_modes [all_constraint_modes -active]
set_propagated_clock [all_clocks]
report_clocks
setAnalysisMode -analysisType onChipVariation -cppr both
spefIn -rc_corner rc_typ pnr/chip_s_full3_quantus.spef
catch {timeDesign -signoff -outDir pnr/signoff_setup3}
catch {timeDesign -signoff -hold -outDir pnr/signoff_hold3}
catch {report_timing -max_paths 5 > pnr/signoff_setup3.rpt}
catch {report_timing -early -max_paths 5 > pnr/signoff_hold3.rpt}
catch {set_default_switching_activity -input_activity 0.2 -seq_activity 0.1}
catch {report_power -view view_setup -outfile pnr/signoff_power3_80.rpt}
catch {write_sdf -view view_setup -min_view view_hold -max_view view_setup -typ_view view_setup pnr/chip_s_full3_signoff.sdf}
puts "SIGNOFF3_DONE"
exit
