#!/usr/bin/env python3
# worldmap_current_best.png(§154 시점 "현재 최선")의 렌더링 코드. 원래는 인라인으로만 실행되어 커밋되지 않았던 것을 재현 가능하게 스크립트로 보존.
# 입력 depth_comp.npy = scripts/delta_depth_layers.py의 focus stack 합성(층마다 국소 선명도(sigma=8)가 최대인 층의 픽셀을 골라 합성; 손으로 넣은 상수 103도/s 0~280 step 20/중심(480,360), 구 trk_theta 사용).
# 사용: render_depth_comp.py <depth_comp.npy> <out.png>
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

comp = np.load(sys.argv[1]); crop = comp[200:1200, 200:1200]; hi = np.percentile(crop[crop > 0], 99.7)
plt.figure(figsize=(10, 10)); plt.imshow(np.clip(crop, 0, hi) ** 0.6, cmap="gray"); plt.axis("off"); plt.tight_layout(pad=0); plt.savefig(sys.argv[2], dpi=100)
