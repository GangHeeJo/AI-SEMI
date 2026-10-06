#!/bin/bash
# usage: run_quantus.sh <workdir> <TOP>   (after run_flow.sh; writes pnr/<TOP>_quantus.spef)
W=$1; TOP=$2; FLOW=$(cd $(dirname $0) && pwd); G=/home/aiasic26911/gsclib045_all_v4.7/gsclib045
cd $W; sed -e "s#@TOP@#$TOP#g" -e "s#@G@#$G#g" -e "s#@FLOW@#$FLOW#g" -e "s#@EXTRA_LEF@#${EXTRA_LEF:-}#g" $FLOW/quantus.ccl.tmpl > quantus.ccl
quantus -cmd quantus.ccl < /dev/null > quantus.out 2>&1; echo "quantus rc=$?"
ls -la pnr/${TOP}_quantus.spef 2>/dev/null
