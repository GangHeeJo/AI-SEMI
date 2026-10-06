#!/bin/bash
# usage: run_signoff.sh <workdir> <TOP>  : Quantus SPEF -> Innovus re-time -> signoff SDF
W=$1; export TOP=$2; FLOW=$(cd $(dirname $0) && pwd)
bash $FLOW/run_quantus.sh $W $TOP
cd $W && innovus -no_gui -files $FLOW/signoff_sta.tcl -log signoff < /dev/null > signoff.out 2>&1
grep -q SIGNOFF_STA_DONE signoff.out && echo SIGNOFF_DONE || echo SIGNOFF_FAIL
