#!/usr/bin/env python3
# delta_depthsnap4를 이벤트 STRIDE(환경변수 SNAP_STRIDE, 기본 8)로 빠르게 돌려 일치율만 비교하는 진단용. 사용: snap4_fast.py <h5> <theta.npy> <calib.json> <out_prefix>
import os
import sys

import delta_depthwarp2 as dw2

dw2.STRIDE = int(os.environ.get("SNAP_STRIDE", "8"))
import delta_depthsnap4 as s4  # noqa: E402

s4.run(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])
