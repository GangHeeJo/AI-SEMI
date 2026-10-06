# env: EXTRA_LIB (slow corner lib for macros, optional)
set LIBDIR /home/aiasic26911/gsclib045_all_v4.7/gsclib045/timing
set X {}
if {[info exists ::env(EXTRA_LIB)]} { set X $::env(EXTRA_LIB) }
create_library_set -name lib_slow -timing [concat $LIBDIR/slow_vdd1v0_basicCells.lib $X]
create_library_set -name lib_fast -timing [concat $LIBDIR/fast_vdd1v0_basicCells.lib $X]
create_rc_corner -name rc_typ -qx_tech_file /tools/config/GPDK/gpdk045_v_6_0/qrc/typical/qrcTechFile -T 25
create_delay_corner -name dc_slow -library_set lib_slow -rc_corner rc_typ
create_delay_corner -name dc_fast -library_set lib_fast -rc_corner rc_typ
create_constraint_mode -name cm -sdc_files [list syn/$::env(TOP).sdc]
create_analysis_view -name view_setup -constraint_mode cm -delay_corner dc_slow
create_analysis_view -name view_hold  -constraint_mode cm -delay_corner dc_fast
set_analysis_view -setup {view_setup} -hold {view_hold}
