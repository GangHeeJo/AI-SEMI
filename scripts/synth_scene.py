#!/usr/bin/env python3
# §159: 정답을 아는 합성 이벤트 데이터. 파이프라인이 가정하는 모델을 그대로 생성기로 씀:
#   p(t) = c0 + s*e + R(theta(t)) Q          (Q = 장면 좌표, s = 깊이 오프셋; 점은 자기 깊이의 회전중심 c0+s*e 주위를 돎)
# 그러면 공통 좌표계 u = R(-theta)(p - c0 - s*e) = Q 라서, 파이프라인이 만드는 이상적인 월드맵 = 장면 Q 그 자체(정답).
# 센서 오프셋(e, c0)은 실제 영상 값(약 110도, (486,362))과 일부러 다르게(125도, (470,372)) -> 보정이 실제 영상 값을
# 기억하는 게 아니라 데이터에서 구하는지 검증. 시간 프로파일(theta(t), 창별 이벤트 수)은 실제 영상 것을 사용.
# 이벤트 생성: 요소(선분/점) 위의 무작위 점, 에지 법선 방향 속도 |v . n| 에 비례해 채택(에지가 이동 방향과 나란하면
# 이벤트 없음 = 실제 DVS의 aperture 성질), 위치 잡음 0.6px, 배경 잡음 이벤트 3%.
import json
import sys

import h5py
import numpy as np

W_PX, H_PX = 960, 720
E_DEG, C0 = 125.0, (470.0, 372.0)       # 합성 센서 오프셋(실제 영상과 다르게)
NOISE_PX, BG_FRAC, SCALE = 0.6, 0.03, 0.3
SYN_RHO = __import__("os").environ.get("SYN_RHO")      # 설정 시 센서의 프레임 단위 타임스탬프 + 컬럼 순차 읽기 모델 사용(값=읽기 지속 비율 rho)
FRAME_US = 773.0


def build_scene():
    """요소: 선분 (x1,y1,x2,y2,s) / 점 (x,y,s). 좌표는 Q(회전중심 기준 px)."""
    segs, dots = [], []
    def line(x1, y1, x2, y2, s): segs.append((x1, y1, x2, y2, s))
    # 먼 벽: 창틀 격자(s=10)
    for x in (-250, -100, 50, 200): line(x, -300, x, -50, 10)
    for y in (-300, -175, -50): line(-250, y, 200, y, 10)
    # 케이지(s=45): 사각형 + 안쪽 선
    for (a, b, c, d) in ((-200, -20, 100, -20), (-200, 160, 100, 160), (-200, -20, -200, 160), (100, -20, 100, 160), (-50, -20, -50, 160), (-200, 70, 100, 70)):
        line(a, b, c, d, 45)
    # 수직 막대 3개(깊이 70/110/150), 막대마다 에지 2개(폭 14px), 길이 320
    rods = []
    for x, s in ((-120, 70), (40, 110), (170, 150)):
        line(x - 7, -200, x - 7, 120, s); line(x + 7, -200, x + 7, 120, s); rods.append((x, s))
    # 클램프(s=90): 작은 사각형
    for (a, b, c, d) in ((-50, 85, -10, 85), (-50, 110, -10, 110), (-50, 85, -50, 110), (-10, 85, -10, 110)):
        line(a, b, c, d, 90)
    # 바닥 점 격자: 깊이가 연속적으로 변함(120~228)
    for y in range(150, 331, 30):
        for x in range(-300, 301, 40):
            dots.append((x, y, 120 + 0.6 * (y - 150)))
    return segs, dots, rods


def generate(theta_npy, omega_npy, out_h5, truth_npz, seed=0):
    rng = np.random.default_rng(seed)
    th = np.load(theta_npy); res = np.load(omega_npy)
    n_win = np.maximum((res[:len(th), 4] * SCALE).astype(int), 0)
    e = np.array([np.cos(np.radians(E_DEG)), np.sin(np.radians(E_DEG))]); c0 = np.array(C0)
    segs, dots, rods = build_scene()
    S = np.array([[*sg] for sg in segs], float); D = np.array([[*d] for d in dots], float)
    seglen = np.hypot(S[:, 2] - S[:, 0], S[:, 3] - S[:, 1])
    w_el = np.concatenate([seglen, np.full(len(D), 12.0)]); w_el /= w_el.sum()
    nseg = len(S)
    win_s = 4e-3
    tt = (np.arange(len(th)) * 4 + 2) * 1e3                      # 창 중앙 시각(us)
    X, Y, T, P, SZ = [], [], [], [], []
    for w in range(len(th)):
        target = int(n_win[w])
        if target < 50:
            continue
        got = 0; xs, ys, ts, ss_ = [], [], [], []
        while got < target:
            m = max(2 * (target - got), 4000)
            el = rng.choice(len(w_el), size=m, p=w_el)
            is_seg = el < nseg
            s_el = np.where(is_seg, S[np.minimum(el, nseg - 1), 4], D[np.maximum(el - nseg, 0), 2])
            u = rng.random(m)
            sg = S[np.minimum(el, nseg - 1)]
            qx = np.where(is_seg, sg[:, 0] + u * (sg[:, 2] - sg[:, 0]), D[np.maximum(el - nseg, 0), 0])
            qy = np.where(is_seg, sg[:, 1] + u * (sg[:, 3] - sg[:, 1]), D[np.maximum(el - nseg, 0), 1])
            # 선분 법선(Q 좌표)
            dx = sg[:, 2] - sg[:, 0]; dy = sg[:, 3] - sg[:, 1]; L = np.maximum(np.hypot(dx, dy), 1e-9)
            nqx, nqy = -dy / L, dx / L
            t_us = tt[w] + (rng.random(m) - 0.5) * 4000.0
            theta = np.interp(t_us, tt, th)
            c, sn = np.cos(theta), np.sin(theta)
            cpx = c0[0] + s_el * e[0]; cpy = c0[1] + s_el * e[1]               # 깊이별 회전중심 c'
            px = cpx + c * qx - sn * qy; py = cpy + sn * qx + c * qy             # p = c' + R(theta) Q
            # 채택: 에지 법선 방향 속도 |perp(p-c') . n_s| (점은 일정 확률)
            nsx = c * nqx - sn * nqy; nsy = sn * nqx + c * nqy
            speed_n = np.abs((-(py - cpy)) * nsx + (px - cpx) * nsy)
            acc = np.where(is_seg, np.minimum(speed_n / 400.0, 1.0), 0.5)
            px += rng.normal(0, NOISE_PX, m); py += rng.normal(0, NOISE_PX, m)
            ok = (rng.random(m) < acc) & (px >= 0) & (px < W_PX) & (py >= 0) & (py < H_PX)
            if SYN_RHO is not None:                       # 이벤트는 참 시각 t_us에 발생, 열 x가 읽히는 시각의 프레임 스탬프로 기록
                rho = float(SYN_RHO)
                t_us = FRAME_US * np.ceil((t_us - (px / W_PX) * rho * FRAME_US) / FRAME_US)
            xs.append(px[ok]); ys.append(py[ok]); ts.append(t_us[ok]); ss_.append(s_el[ok]); got += int(ok.sum())
        xs = np.concatenate(xs)[:target]; ys = np.concatenate(ys)[:target]; ts = np.concatenate(ts)[:target]; sz = np.concatenate(ss_)[:target].astype(np.float32)
        nbg = int(BG_FRAC * target)                                              # 배경 잡음: 균일
        xs[:nbg] = rng.random(nbg) * W_PX; ys[:nbg] = rng.random(nbg) * H_PX; sz[:nbg] = -1.0   # 잡음 이벤트는 깊이 없음(-1)
        o = np.argsort(ts)
        X.append(np.floor(xs[o]).astype(np.uint16)); Y.append(np.floor(ys[o]).astype(np.uint16)); T.append(ts[o].astype(np.uint32))
        P.append((rng.random(target) < 0.5).astype(np.uint8)); SZ.append(sz[o])
        if w % 50 == 0:
            print(f"window {w}/{len(th)} events so far {sum(len(a) for a in X)}", flush=True)
    X = np.concatenate(X); Y = np.concatenate(Y); T = np.concatenate(T); P = np.concatenate(P); SZ = np.concatenate(SZ)
    order = np.argsort(T, kind="stable"); X, Y, T, P, SZ = X[order], Y[order], T[order], P[order], SZ[order]
    nms = int(T[-1] // 1000) + 2
    ms_to_idx = np.searchsorted(T, np.arange(nms) * 1000).astype(np.uint64)
    with h5py.File(out_h5, "w") as f:
        g = f.create_group("events"); g.attrs["height"] = H_PX; g.attrs["width"] = W_PX
        g.attrs["polarity_encoding"] = b"1=ON, 0=OFF"; g.attrs["source"] = b"SYNTH"
        g.create_dataset("x", data=X); g.create_dataset("y", data=Y); g.create_dataset("t", data=T); g.create_dataset("p", data=P); g.create_dataset("s_true", data=SZ)   # 정답 깊이 오프셋(검증 전용, 파이프라인은 읽지 않음)
        f.create_dataset("ms_to_idx", data=ms_to_idx); f.create_dataset("t_offset", data=0)
    np.savez(truth_npz, e_deg=E_DEG, c0=c0, theta=th, segs=S, dots=D, rods=np.array(rods))
    print("events", len(X), "->", out_h5, flush=True)


if __name__ == "__main__":
    # usage: synth_scene.py <real theta.npy> <real omega.npy(창별 이벤트 수 프로파일)> <out.h5> <truth.npz>
    generate(*sys.argv[1:5])
