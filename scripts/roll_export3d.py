#!/usr/bin/env python3
# §189: 상대 3D 점(u,v,s)을 마우스로 돌려 볼 수 있는 HTML 뷰어(three.js, 자체 궤도 조작)와 두 각도 정지 이미지로 내보낸다.
# 점 = 2px 격자 칸마다 (u,v) 중심 + 평균 s, 색 = 상대 깊이(turbo), 밝기 = log 이벤트 수. 깊이 축 눈금은 교정값이 없어 슬라이더로 조절.
# 사용: roll_export3d.py <events.h5> <theta.npy> <calib.json> <diag_prefix> <out_prefix> [max_points]   (DELTA_RHO 환경변수는 해당 실행과 동일하게)
import sys

import numpy as np

from roll_relative3d import load, uv
from viewer3d import write_viewer

h5p, th, cal, diag, out = sys.argv[1:6]; MAXP = int(sys.argv[6]) if len(sys.argv) > 6 else 350000
x, y, a, s, fl, e, c0, tol, C = load(h5p, th, cal, diag); ag = (fl == 1) & np.isfinite(s); x, y, a, s = x[ag], y[ag], a[ag], s[ag]; u, v = uv(x, y, a, s, e, c0)
write_viewer(u, v, s, out, "Relative 3D world map (roll)", "depth s is relative", MAXP)
