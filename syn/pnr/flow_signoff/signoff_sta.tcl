# Re-time the routed db with standalone-Quantus SPEF and write the signoff SDF. env: TOP
set TOP $::env(TOP)
restoreDesign pnr/final.enc.dat $TOP
setAnalysisMode -analysisType onChipVariation -cppr both
spefIn -rc_corner rc_typ pnr/${TOP}_quantus.spef
catch {timeDesign -signoff -outDir pnr/signoff_setup}
catch {timeDesign -signoff -hold -outDir pnr/signoff_hold}
catch {report_timing -max_paths 3 > pnr/signoff_setup.rpt}
catch {report_timing -early -max_paths 3 > pnr/signoff_hold.rpt}
catch {set_default_switching_activity -input_activity 0.2 -seq_activity 0.1}
catch {report_power -view view_setup -outfile pnr/signoff_power.rpt}
catch {write_sdf -view view_setup -min_view view_hold -max_view view_setup -typ_view view_setup pnr/${TOP}_signoff.sdf}
puts "SIGNOFF_STA_DONE"
exit
