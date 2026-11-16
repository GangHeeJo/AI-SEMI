# job23b MMMC: setup = slow (0.9 V / 125 C lib slow_vdd1v0), hold = fast (fast_vdd1v0), typical RC.
# env: MACRO_SLOW, MACRO_FAST (extracted macro .lib per corner, optional)
set LIBDIR /home/aiasic26911/gsclib045_all_v4.7/gsclib045/timing
set XS {}; set XF {}
if {[info exists ::env(MACRO_SLOW)]} { set XS $::env(MACRO_SLOW) }
if {[info exists ::env(MACRO_FAST)]} { set XF $::env(MACRO_FAST) }
create_library_set -name lib_slow -timing [concat $LIBDIR/slow_vdd1v0_basicCells.lib $XS]
create_library_set -name lib_fast -timing [concat $LIBDIR/fast_vdd1v0_basicCells.lib $XF]
create_rc_corner -name rc_typ -qx_tech_file /tools/config/GPDK/gpdk045_v_6_0/qrc/typical/qrcTechFile -T 25
create_delay_corner -name dc_slow -library_set lib_slow -rc_corner rc_typ
create_delay_corner -name dc_fast -library_set lib_fast -rc_corner rc_typ
create_constraint_mode -name cm -sdc_files [list [expr {[info exists ::env(SDCFILE)] ? $::env(SDCFILE) : "syn/$::env(TOP).sdc"}]]
create_analysis_view -name view_setup -constraint_mode cm -delay_corner dc_slow
create_analysis_view -name view_hold  -constraint_mode cm -delay_corner dc_fast
set_analysis_view -setup {view_setup} -hold {view_hold}
