#!/bin/bash
# usage: ./sim.sh <name> [wave]
#   compiles rtl/*.v + tb/tb_<name>.v, runs it, dumps sim/<name>.vcd
#   pass "wave" as 2nd arg to open gtkwave after running
set -e
NAME="$1"
cd "$(dirname "$0")"
iverilog -Itb -o "sim/$NAME.vvp" rtl/*.v "tb/tb_$NAME.v"
(cd sim && vvp "$NAME.vvp")
if [ "$2" = "wave" ]; then
  gtkwave "sim/$NAME.vcd" &
fi
