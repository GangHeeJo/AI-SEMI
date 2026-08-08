# MMMC(Multi-Mode Multi-Corner) 뷰 정의 — Innovus 타이밍 분석에 필요.
# Genus와 동일한 slow_vdd1v0 코너 하나만 씀(단일 코너, 단일 모드).
set LIB_DIR /home/aiasic26911/gsclib045_all_v4.7/gsclib045

create_library_set -name libset_slow \
  -timing "$LIB_DIR/timing/slow_vdd1v0_basicCells.lib"

create_rc_corner -name rc_typical -qrc_tech $LIB_DIR/qrc/qx/gpdk045.tch

create_delay_corner -name delay_slow -library_set libset_slow -rc_corner rc_typical

create_constraint_mode -name constraints_default -sdc_files {syn/reports/aer_tx16_trad_rowcol_fovea_out.sdc}

create_analysis_view -name view_slow -constraint_mode constraints_default -delay_corner delay_slow

set_analysis_view -setup {view_slow} -hold {view_slow}
