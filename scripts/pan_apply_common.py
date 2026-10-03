#!/usr/bin/env python3
# §178: 공통 궤적 오차 e(t)를 타일 절반(훈련)으로 추정 -> 궤적에서 빼 보정 -> 나머지 절반(시험) 타일의 번짐 변화로 검증.
# 사용: pan_apply_common.py <events.h5> <track.npy> <out_track_train.npy> <test_tiles.npy>
import sys

import numpy as np

from pan_common_mode import collect, design

h5p, trk, out, out_tiles = sys.argv[1:5]
R, t0, t1 = collect(h5p, trk); R = R[R[:, 5] > 0.3]; A, tk = design(R, t0, t1)
tiles = np.unique(R[:, 0]); rng = np.random.default_rng(0); te = set(rng.choice(tiles, len(tiles) // 2, replace=False)); is_te = np.array([v in te for v in R[:, 0]])
e = np.zeros(len(tk)); e[1:] = np.linalg.lstsq(A[~is_te], R[~is_te, 3], rcond=None)[0]              # 훈련 타일만 사용
tr = np.load(trk); tr[:, 1] -= np.interp(tr[:, 0], tk, e); np.save(out, tr)
tt = np.unique(R[is_te][:, [6, 7]], axis=0); np.save(out_tiles, tt)
print(f"train tiles {len(tiles)-len(te)}, test tiles {len(te)}; e(t) range {e.min():+.1f}..{e.max():+.1f} px; corrected total x shift {tr[-1,1]:.1f}")
