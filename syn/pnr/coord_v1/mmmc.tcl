# setup = slow 0.9V/125C 라이브러리, hold = fast 라이브러리(팀원 P&R과 같은 두 코너), RC는 typical 하나.
set L /home/aiasic26911/gsclib045_all_v4.7/gsclib045
create_library_set -name libset_slow -timing "$L/timing/slow_vdd1v0_basicCells.lib"
create_library_set -name libset_fast -timing "$L/timing/fast_vdd1v0_basicCells.lib"
create_rc_corner -name rc_typical -qrc_tech $L/qrc/qx/gpdk045.tch
create_delay_corner -name delay_slow -library_set libset_slow -rc_corner rc_typical
create_delay_corner -name delay_fast -library_set libset_fast -rc_corner rc_typical
create_constraint_mode -name constraints_default -sdc_files {syn/pnr/coord_v1/aer_tx16_coord_transform_v1_out.sdc}
create_analysis_view -name view_slow -constraint_mode constraints_default -delay_corner delay_slow
create_analysis_view -name view_fast -constraint_mode constraints_default -delay_corner delay_fast
set_analysis_view -setup {view_slow} -hold {view_fast}
