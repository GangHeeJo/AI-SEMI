#!/bin/bash
# 클럭 주기 여러 개를 돌려서 각 지점의 WNS(slack)를 표로 뽑는다.
# 사용법: bash syn/sweep_fmax.sh <DESIGN> "<RTL 파일들(공백구분)>" <period1> <period2> ...
# 예:     bash syn/sweep_fmax.sh aer_tx16 "rtl/arbiter4.v rtl/aer_tx16.v" 5.0 2.0 1.0 0.7 0.5 0.4
set -e
DESIGN="$1"
RTL_LIST="$2"
shift 2

OUT=syn/sweep
mkdir -p "$OUT"

echo "period_ns | Path1_line"
echo "----------+----------------------------------------------------------"
for P in "$@"; do
  AER_DESIGN="$DESIGN" AER_RTL_LIST="$RTL_LIST" AER_CLK_PERIOD="$P" \
    genus -files syn/run_genus_sweep.tcl > "$OUT/${DESIGN}_${P}.log" 2>&1
  LINE=$(grep -m1 "^Path 1:" "$OUT/${DESIGN}_${P}.log")
  printf "%-9s | %s\n" "$P" "$LINE"
done
