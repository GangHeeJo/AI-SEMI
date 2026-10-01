#!/usr/bin/env python3
# §147: 3차 QnA 실측 DELTA 데이터(960x720, 1000fps, h5로 export한 것)를 기존 addrpol.txt
# 포맷("cycle arrival_hex16 pol_hex16", source=row*4+col)의 4x4 패치 트레이스로 변환.
# 1프레임=1ms=1cycle(센서 native 1000fps라 시간 압축 인공물 없음 -- §116 교훈).
# 패치는 4x4 블록(stride 4) 활동량 순위에서 분위별로 골라 "가장 바쁜 곳 ~ 보통 곳"을 같이 본다.
import sys

import h5py
import numpy as np

H5 = "Q&A/3차/extracted/2026-09-22-16-42-32-DELTA.h5"
OUT_DIR = "common_traces_delta"
W, H = 960, 720
QUANTILES = (1.0, 0.99, 0.9, 0.5)  # 활동량 상위 분위(1.0=최대)
CHUNK = 5_000_000


def main():
    f = h5py.File(H5, "r")
    n = f["events/t"].shape[0]
    blocks = np.zeros((H // 4, W // 4), np.int64)
    for s in range(0, n, CHUNK):
        x = f["events/x"][s:s + CHUNK] // 4
        y = f["events/y"][s:s + CHUNK] // 4
        blocks += np.bincount(y.astype(np.int64) * (W // 4) + x, minlength=blocks.size).reshape(blocks.shape)
    flat = np.sort(blocks.ravel())
    nz = flat[flat > 0]
    picks = {}
    for q in QUANTILES:
        target = nz[min(int(q * (len(nz) - 1)), len(nz) - 1)]
        by, bx = np.argwhere(blocks == target)[0]
        picks[q] = (int(bx) * 4, int(by) * 4, int(target))
    print("patches (x0,y0,total events):", picks)

    import os
    os.makedirs(OUT_DIR, exist_ok=True)
    acc = {q: {} for q in picks}
    coll = {q: 0 for q in picks}
    for s in range(0, n, CHUNK):
        x = f["events/x"][s:s + CHUNK]; y = f["events/y"][s:s + CHUNK]
        t = f["events/t"][s:s + CHUNK]; p = f["events/p"][s:s + CHUNK]
        for q, (x0, y0, _) in picks.items():
            m = (x >= x0) & (x < x0 + 4) & (y >= y0) & (y < y0 + 4)
            for xi, yi, ti, pi in zip(x[m], y[m], t[m], p[m]):
                cyc = int(ti) // 1000
                bit = 1 << ((int(yi) - y0) * 4 + (int(xi) - x0))
                a, pl = acc[q].get(cyc, (0, 0))
                if a & bit:
                    coll[q] += 1
                acc[q][cyc] = (a | bit, pl | (bit if pi else 0))
    for q, (x0, y0, tot) in picks.items():
        path = f"{OUT_DIR}/delta_q{int(q * 100):03d}_x{x0}_y{y0}.addrpol.txt"
        with open(path, "w") as out:
            for cyc in sorted(acc[q]):
                a, pl = acc[q][cyc]
                out.write(f"{cyc} {a:04x} {pl:04x}\n")
        per = [bin(a).count("1") for a, _ in acc[q].values()]
        print(f"q={q}: {path} events={tot} cycles_with_event={len(acc[q])} "
              f"collisions(same pixel same cycle)={coll[q]} max/cycle={max(per)} mean/active_cycle={sum(per)/len(per):.2f}")


if __name__ == "__main__":
    main()
