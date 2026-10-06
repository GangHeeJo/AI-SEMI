#!/bin/bash
# usage: run_flow.sh <workdir> <TOP> <PER_ns> <UTIL> <rtl files...>
# optional env: EXTRA_LIB EXTRA_LEF EXTRA_GDS MACRO_PLACE
set -u
W=$1; export TOP=$2 PER=$3 UTIL=$4; shift 4; RTL=""; for f in "$@"; do RTL="$RTL $(readlink -f $f)"; done; export RTL
FLOW=$(cd $(dirname $0) && pwd)
mkdir -p $W && cd $W
cp $FLOW/mmmc.tcl .
t0=$(date +%s)
if [ -z "${RESUME:-}" ]; then genus -no_gui -files $FLOW/genus.tcl -log genus < /dev/null > genus.out 2>&1; fi
t1=$(date +%s); echo "genus $((t1-t0))s rc=$?" > times.txt
grep -q GENUS_DONE genus.out || { echo GENUS_FAIL >> times.txt; exit 1; }
innovus -no_gui -files $FLOW/innovus.tcl -log innovus < /dev/null > innovus.out 2>&1
t2=$(date +%s); echo "innovus $((t2-t1))s" >> times.txt
grep -q INNOVUS_DONE innovus.out || { echo INNOVUS_FAIL >> times.txt; exit 1; }
echo FLOW_DONE >> times.txt
