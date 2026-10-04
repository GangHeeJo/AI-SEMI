#!/usr/bin/env python3
# §185: 정답을 아는 pan 합성 데이터 (궤도 운동의 시차 모델). 깊이별 평면 j는 기준 이동 p(t)의 lam_j 배로 움직인다:
#   x = Qx - lam_j * px(t),  y = Qy - lam_j * py(t)     (Q = 평면 좌표; 파이프라인이 올바른 lam으로 되돌리면 X = x + lam*p = Q)
# 평면 5개(lam = 1-w ~ 1+w 균등) + 연속 깊이 바닥(점 격자, lam이 y에 선형). w(시차 폭)는 매개변수 -- 실제 영상의 lam 분포에 맞추지 않음.
# 실제 영상에서 가져오는 것: 이동 궤적 p(t)와 프레임별 이벤트 수 프로파일(roll 합성이 실제 theta 프로파일을 쓴 것과 같음).
# 이벤트: 요소(선분/점) 위의 점, 에지 법선 방향 속도에 비례해 채택(가로 에지는 이벤트 없음), 위치 잡음 0.6px, 배경 잡음 3%.
# 한계: 원근 왜곡(실제 궤도 운동은 평면 병진이 아님) 없음 -> 파이프라인 가정과 같은 모델 안에서의 시험.
# 사용: synth_pan.py <real_events.h5> <track.npy> <w> <total_events> <out.h5> <truth.npz> [seed]
import sys

import h5py
import numpy as np

W_PX, H_PX, NOISE_PX, BG_FRAC = 960, 720, 0.6, 0.03


def build(w, p_max, rng):
    lam_planes = np.linspace(1 - w, 1 + w, 5); segs, dots = [], []
    for lam in lam_planes:
        qw = W_PX + lam * p_max
        for _ in range(250):
            ang = np.radians(rng.normal(90, 12)) if rng.random() < 0.6 else np.radians(rng.uniform(0, 180))     # 60%는 세로 근처(이벤트 풍부), 나머지는 임의 방향
            L = rng.uniform(40, 220); cx = rng.uniform(0, qw); cy = rng.uniform(40, H_PX - 40)
            segs.append((cx - L / 2 * np.cos(ang), cy - L / 2 * np.sin(ang), cx + L / 2 * np.cos(ang), cy + L / 2 * np.sin(ang), lam))
    for y in range(430, 700, 30):                                                                     # 연속 깊이 바닥: lam이 y에 선형
        for x in range(0, int(W_PX + (1 + w) * p_max), 40):
            dots.append((x, y, 1 - w + 2 * w * (y - 430) / 270))
    return np.array(segs), np.array(dots), lam_planes


def generate(real_h5, track_npy, w, total, out_h5, truth_npz, seed=0):
    rng = np.random.default_rng(seed); tr = np.load(track_npy)
    f = h5py.File(real_h5, "r"); t_real = f["events/t"][:]
    first = np.concatenate([[0], np.flatnonzero(np.diff(t_real)) + 1, [len(t_real)]]); cnt = np.diff(first); tf = t_real[first[:-1]].astype(np.float64)
    n_f = np.maximum((cnt * (total / cnt.sum())).astype(int), 0)
    S, D, lam_planes = build(w, tr[:, 1].max(), rng)
    sl = np.hypot(S[:, 2] - S[:, 0], S[:, 3] - S[:, 1]); w_el = np.concatenate([sl, np.full(len(D), 12.0)]); w_el /= w_el.sum(); nseg = len(S)
    X, Y, T, L = [], [], [], []
    for fi in range(len(tf)):
        target = int(n_f[fi])
        if target < 20: continue
        got = 0; xs, ys, ls = [], [], []
        pxf = np.interp(tf[fi], tr[:, 0], tr[:, 1]); pyf = np.interp(tf[fi], tr[:, 0], tr[:, 2])
        vx = np.gradient(tr[:, 1], tr[:, 0]); v = np.interp(tf[fi], tr[:, 0], vx) * 773.0            # px / 프레임
        while got < target:
            m = max(3 * (target - got), 2000); el = rng.choice(len(w_el), size=m, p=w_el); is_seg = el < nseg
            sg = S[np.minimum(el, nseg - 1)]; dd = D[np.maximum(el - nseg, 0)]; u = rng.random(m)
            qx = np.where(is_seg, sg[:, 0] + u * (sg[:, 2] - sg[:, 0]), dd[:, 0]); qy = np.where(is_seg, sg[:, 1] + u * (sg[:, 3] - sg[:, 1]), dd[:, 1]); lam = np.where(is_seg, sg[:, 4], dd[:, 2])
            dx = sg[:, 2] - sg[:, 0]; dy = sg[:, 3] - sg[:, 1]; Ln = np.maximum(np.hypot(dx, dy), 1e-9); nx = -dy / Ln                 # 에지 법선의 x성분
            acc = np.where(is_seg, np.minimum(np.abs(nx) * lam * abs(v) / 1.2, 1.0), 0.5)             # 법선 방향 이동량에 비례(1.2px/프레임 이상이면 포화)
            x = qx - lam * pxf + rng.normal(0, NOISE_PX, m); y = qy - lam * pyf + rng.normal(0, NOISE_PX, m)
            ok = (rng.random(m) < acc) & (x >= 0) & (x < W_PX) & (y >= 0) & (y < H_PX)
            xs.append(x[ok]); ys.append(y[ok]); ls.append(lam[ok]); got += int(ok.sum())
        x = np.concatenate(xs)[:target]; y = np.concatenate(ys)[:target]; lam = np.concatenate(ls)[:target]
        nb = int(BG_FRAC * target); x[:nb] = rng.random(nb) * W_PX; y[:nb] = rng.random(nb) * H_PX; lam[:nb] = np.nan             # 배경 잡음: 깊이 없음
        X.append(np.floor(x).astype(np.uint16)); Y.append(np.floor(y).astype(np.uint16)); T.append(np.full(target, tf[fi], np.uint32)); L.append(lam.astype(np.float32))
    X = np.concatenate(X); Y = np.concatenate(Y); T = np.concatenate(T); L = np.concatenate(L)
    nms = int(T[-1] // 1000) + 2
    with h5py.File(out_h5, "w") as g:
        e = g.create_group("events"); e.attrs["height"] = H_PX; e.attrs["width"] = W_PX; e.attrs["source"] = b"SYNTH_PAN"
        e.create_dataset("x", data=X); e.create_dataset("y", data=Y); e.create_dataset("t", data=T); e.create_dataset("lam_true", data=L)
        g.create_dataset("ms_to_idx", data=np.searchsorted(T, np.arange(nms) * 1000).astype(np.uint64))
    np.savez(truth_npz, w=w, segs=S, dots=D, lam_planes=lam_planes)
    print("events", len(X), "w", w, "->", out_h5)


if __name__ == "__main__":
    a = sys.argv; generate(a[1], a[2], float(a[3]), int(a[4]), a[5], a[6], int(a[7]) if len(a) > 7 else 0)
