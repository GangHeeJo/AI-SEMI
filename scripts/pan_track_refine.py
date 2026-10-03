#!/usr/bin/env python3
# §176: pan 궤적 정밀화. track(t) = ECC 궤적(t) + 매듭 보정(모자 함수 보간). 매듭(NK개, 양 끝 고정)마다 (dx,dy)를 좌표 하강으로 조절해
# 장면 좌표 2px 격자에서 이벤트 겹침 점수 sum c^2를 최대화(증분 계산). 보정량 상한 CAP px(지도 축소 편향 방지).
# 사용: pan_track_refine.py <events.h5> <ecc_track.npy> <out_track.npy>   (출력 열: ts, px, py, 1 -- pan_blur_table.py 입력 형식)
import sys

import h5py
import numpy as np

NK, BIN, STRIDE, CAP = 66, 2.0, 4, 30.0


def run(h5p, trk, out):
    f = h5py.File(h5p, "r"); t = f["events/t"][::STRIDE].astype(np.float64); x = f["events/x"][::STRIDE].astype(np.float64); y = f["events/y"][::STRIDE].astype(np.float64)
    tr = np.load(trk); ts = tr[:, 0]; base = np.c_[np.interp(t, ts, tr[:, 1]), np.interp(t, ts, tr[:, 2])]
    tk = np.linspace(t[0], t[-1], NK); h = tk[1] - tk[0]; off = np.zeros((NK, 2))
    Xc = x + base[:, 0]; Yc = y + base[:, 1]; x0 = Xc.min() - CAP - 20; y0 = Yc.min() - CAP - 20
    nxg = int((Xc.max() + CAP + 20 - x0) / BIN) + 2; nyg = int((Yc.max() + CAP + 20 - y0) / BIN) + 2; G = nxg * nyg
    cell = lambda X, Y: np.clip(((Y - y0) / BIN).astype(np.int64), 0, nyg - 1) * nxg + np.clip(((X - x0) / BIN).astype(np.int64), 0, nxg - 1)
    C = np.bincount(cell(Xc, Yc), minlength=G).astype(np.float64); score = lambda: float((C ** 2).sum() / len(t) ** 2)
    sl = [slice(np.searchsorted(t, tk[k] - h), np.searchsorted(t, tk[k] + h)) for k in range(NK)]
    wk = [1 - np.abs(t[s] - tk[k]) / h for k, s in enumerate(sl)]
    print(f"events {len(t)}, grid {nyg}x{nxg}, score start {score()*1e6:.3f}e-6", flush=True)
    for sweep, steps in enumerate(((6, 3), (3, 1.5), (1.5, 0.75), (0.75, 0.4))):
        moved = 0
        for k in range(1, NK - 1):
            for axis in (0, 1):
                for st in steps:
                    for sgn in (1, -1):
                        d = np.zeros(2); d[axis] = sgn * st
                        if abs(off[k, axis] + d[axis]) > CAP: continue
                        s = sl[k]; Xn = Xc[s] + wk[k] * d[0]; Yn = Yc[s] + wk[k] * d[1]
                        co = np.bincount(cell(Xc[s], Yc[s]), minlength=G); cn = np.bincount(cell(Xn, Yn), minlength=G); dd = cn - co
                        gain = (2 * C * dd + dd.astype(np.float64) ** 2).sum()
                        if gain > 0:
                            C += dd; Xc[s] = Xn; Yc[s] = Yn; off[k] += d; moved += 1
        print(f"sweep {sweep}: moves {moved}, score {score()*1e6:.3f}e-6, max|offset| {np.abs(off).max():.1f}px", flush=True)
    new = np.c_[np.interp(ts, tk, off[:, 0]), np.interp(ts, tk, off[:, 1])]
    np.save(out, np.c_[ts, tr[:, 1] + new[:, 0], tr[:, 2] + new[:, 1], np.ones(len(ts))])
    print("offset at knots (px, x): " + " ".join(f"{v:+.1f}" for v in off[::6, 0]))
    print(f"total shift now ({tr[-1,1]+new[-1,0]:.1f}, {tr[-1,2]+new[-1,1]:.1f}) vs ECC ({tr[-1,1]:.1f}, {tr[-1,2]:.1f})")


if __name__ == "__main__":
    run(*sys.argv[1:4])
