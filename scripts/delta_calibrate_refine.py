#!/usr/bin/env python3
# §165: 보정(오프셋 직선의 방향 phi, 공칭 중심에서의 수직 거리 d)을 맵 일관성으로 정밀화. 직선 위 s=0 기준점은 데이터로 정해지지
# 않는 모호성이라 건드리지 않는다(공칭 중심에 가장 가까운 점 고정).
# 목적함수: 층별 월드맵을 타일(48px)로 나누어 타일마다 가장 응집된(충돌 sum c^2) 층을 고르고 합한다. 기하가 맞으면 각 깊이의
# 구조가 한 점으로 모여 값이 커진다. 모든 층이 같은 이벤트 N개를 쓰고 평행이동은 면적을 안 바꾸므로 비교가 공정하다.
# 좌표 하강: phi(+-3도) -> d(+-16px) -> phi(+-1도), 각 5점 포물선 보간.
import json
import sys

import h5py
import numpy as np

W_PX, H_PX = 960, 720
TILE = 48
C = 1680                                  # 타일(48)의 배수
OFF = C / 2


def make_events(h5_path, theta_npy, t_range, stride, rho=0.0):
    th = np.load(theta_npy); mids = np.arange(len(th)) * 4 + 2.0
    f = h5py.File(h5_path, "r"); m = f["ms_to_idx"][:].astype(np.int64)
    s, e = m[t_range[0]], m[t_range[1]]
    x = f["events/x"][s:e:stride].astype(np.float64); y = f["events/y"][s:e:stride].astype(np.float64)
    t = f["events/t"][s:e:stride].astype(np.float64) / 1e3
    t = t + (x / 960.0 - 0.5) * rho * 0.773
    return x, y, -np.interp(t, mids, th)


def score(ev, phi_deg, d, ss, c_nom=(480.0, 360.0)):
    x, y, a = ev
    e = np.array([np.cos(np.radians(phi_deg)), np.sin(np.radians(phi_deg))]); nrm = np.array([-e[1], e[0]])
    c0 = np.array(c_nom) + d * nrm
    cs, sn = np.cos(a), np.sin(a)
    nt = C // TILE
    best = np.full((nt, nt), -1.0)
    for s_ in ss:
        px = x - c0[0] - s_ * e[0]; py = y - c0[1] - s_ * e[1]
        xi = np.rint(cs * px - sn * py + OFF).astype(np.int64); yi = np.rint(sn * px + cs * py + OFF).astype(np.int64)
        ok = (xi >= 0) & (xi < C) & (yi >= 0) & (yi < C)
        cnt = np.bincount(yi[ok] * C + xi[ok], minlength=C * C).reshape(C, C).astype(np.float64)
        col = (cnt * cnt).reshape(nt, TILE, nt, TILE).sum((1, 3))              # 타일별 sum c^2
        best = np.maximum(best, col)
    return float(best.sum() / (len(x) ** 2) * 1e6)


def parabola_peak(xs, ys):
    c = np.polyfit(xs, ys, 2)
    return float(-c[1] / (2 * c[0])) if c[0] < 0 else float(xs[int(np.argmax(ys))])


def refine(h5_path, theta_npy, cal_json, out_json, t_range=(300, 1500), stride=8, rho=0.0):
    cal = json.load(open(cal_json)); ev = make_events(h5_path, theta_npy, t_range, stride, rho)
    step = float(cal["layer_step_px"]) / 3.0                                   # 정밀화는 층을 조금 더 촘촘히(FWHM/9)
    ss = np.arange(cal["s_min_px"] - 20, cal["s_max_px"] + 60, max(step, 12.0))
    phi, d = float(cal["direction_deg"]), 0.0
    print(f"start: phi {phi:.2f} deg, d {d:.1f} px, layers {len(ss)} (s {ss[0]:.0f}..{ss[-1]:.0f}), events {len(ev[0])}", flush=True)
    hist = []
    for name, steps in (("phi", np.array([-3, -1.5, 0, 1.5, 3.0])), ("d", np.array([-16, -8, 0, 8, 16.0])), ("phi", np.array([-1, -0.5, 0, 0.5, 1.0]))):
        for rep in range(6):                                                    # 최적점이 탐색 구간 끝에 걸리면 구간을 옮겨 다시 (최대 6회)
            vals = []
            for st in steps:
                v = score(ev, phi + st, d, ss) if name == "phi" else score(ev, phi, d + st, ss)
                vals.append(v)
            vals = np.array(vals); ib = int(np.argmax(vals))
            at_edge = ib in (0, len(steps) - 1)
            pk = float(np.clip(parabola_peak(steps, vals), steps[0], steps[-1]))
            if name == "phi": phi += pk
            else: d += pk
            hist.append((name, steps.tolist(), [round(float(x), 3) for x in vals], round(pk, 2)))
            print(f"  {name}: scores {[round(float(x), 3) for x in vals]} -> shift {pk:+.2f} -> phi {phi:.2f}, d {d:.1f}{'  (edge: re-centering)' if at_edge else ''}", flush=True)
            if not at_edge:
                break
    e = np.array([np.cos(np.radians(phi)), np.sin(np.radians(phi))]); nrm = np.array([-e[1], e[0]])
    out = dict(cal); c0 = np.array([480.0, 360.0]) + d * nrm
    out.update(direction_deg=float(phi % 360), unit_vector=[float(e[0]), float(e[1])], center_px=[float(c0[0]), float(c0[1])],
               refined=True, refine_history=hist)
    json.dump(out, open(out_json, "w"), indent=1)
    return out


if __name__ == "__main__":
    # usage: delta_calibrate_refine.py <events.h5> <theta.npy> <calibration.json> <out.json>
    refine(*sys.argv[1:5])
