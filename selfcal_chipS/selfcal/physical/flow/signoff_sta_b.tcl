# New selfcal candidate, 8ns SDC from fresh synthesis; never restore old final3.
set TOP $::env(TOP)
restoreDesign pnr/final.enc.dat $TOP
setMultiCpuUsage -localCpu 4
update_constraint_mode -name cm -sdc_files syn/chip_s_full.sdc
set_interactive_constraint_modes [all_constraint_modes -active]
set_propagated_clock [all_clocks]
report_clocks > pnr/signoff_clocks.rpt
setAnalysisMode -analysisType onChipVariation -cppr both
spefIn -rc_corner rc_typ pnr/chip_s_full_quantus.spef
timeDesign -signoff -outDir pnr/signoff_setup
timeDesign -signoff -hold -outDir pnr/signoff_hold
report_timing -max_paths 20 > pnr/signoff_setup.rpt
report_timing -early -max_paths 20 > pnr/signoff_hold.rpt
set_default_switching_activity -input_activity 0.2 -seq_activity 0.1
report_power -view view_setup -outfile pnr/signoff_power.rpt
write_sdf -view view_setup -min_view view_hold -max_view view_setup -typ_view view_setup pnr/chip_s_full_signoff.sdf
# Export pin-placement evidence, including the new selfcal ports.
set fp [open pnr/pin_placement.txt w]
foreach pin [get_db ports] {
 puts $fp "[get_db $pin .name] [get_db $pin .location]"
}
close $fp
puts SELF_CAL_SIGNOFF_DONE
exit
