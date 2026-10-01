#!/usr/bin/env python3
# §156: 정답 없이 월드맵 품질을 재는 시간 일관성 지표. 시간을 4등분해 구간마다 월드맵을 따로 쌓고(같은 theta,
# 같은 깊이지도), 쌍별(6쌍) 밴드패스 NCC의 평균을 낸다. 맞는 월드맵이면 서로 다른 시간대 맵이 같아야 한다.
# 주의: 부드럽게 뭉갠 맵이 유리해지지 않도록 DoG(작은 시그마-큰 시그마) 밴드패스 후 비교. 변형별(깊이 없음/v1/v2)
# 같은 방식으로 비교하는 용도(절대값이 아니라 상대 비교).
import json
import sys

import h5py
import numpy as np
from scipy import ndimage as ndi

W_PX, H_PX = 960, 720
STRIDE, CHUNK = 2, 4_000_000


def maps_quarters(f, th, mids, c0, e, depth, C, nq=4):
    OFF = C / 2
    t_end = float(f["events/t"][-1])
    Q = [np.zeros(C * C, np.float32) for _ in range(nq)]
    n = f["events/t"].shape[0]

    def canvas(x, y, a, s):
        px = x - c0[0] - s * e[0]; py = y - c0[1] - s * e[1]
        c, sn = np.cos(a), np.sin(a)
        xi = np.rint(c * px - sn * py + OFF).astype(np.int64); yi = np.rint(sn * px + c * py + OFF).astype(np.int64)
        ok = (xi >= 0) & (xi < C) & (yi >= 0) & (yi < C)
        return np.where(ok, yi * C + xi, -1)

    for s0 in range(0, n, CHUNK * STRIDE):
        sl = slice(s0, s0 + CHUNK * STRIDE, STRIDE)
        x = f["events/x"][sl].astype(np.float64); y = f["events/y"][sl].astype(np.float64)
        t = f["events/t"][sl].astype(np.float64)
        a = -np.interp(t, mids, th)
        s_ev = np.zeros(len(x))
        if depth is not None:                              # 고정점 반복 2회: 위치 -> 깊이 읽기 -> 재투영
            for _ in range(2):
                p = canvas(x, y, a, s_ev)
                s_ev = np.where(p >= 0, depth.ravel()[np.maximum(p, 0)], 0.0)
        p = canvas(x, y, a, s_ev)
        q = np.minimum((t / (t_end + 1) * nq).astype(np.int64), nq - 1)
        for k in range(nq):
            pk = p[(q == k) & (p >= 0)]
            Q[k] += np.bincount(pk, minlength=C * C).astype(np.float32)
    return [m.reshape(C, C) for m in Q]


def prep(m, C, radius=420):
    m = np.minimum(m, np.percentile(m[m > 0], 99))
    g = ndi.gaussian_filter(m, 2.0) - ndi.gaussian_filter(m, 12.0)
    yy, xx = np.mgrid[:C, :C]
    g[(xx - C / 2) ** 2 + (yy - C / 2) ** 2 > radius ** 2] = 0
    return g


def ncc(a, b):
    a = a - a.mean(); b = b - b.mean()
    return float((a * b).sum() / np.sqrt((a * a).sum() * (b * b).sum()))


def score(h5_path, theta_npy, cal_json, depth_npy, C):
    cal = json.load(open(cal_json))
    e = np.array(cal["unit_vector"], float); c0 = np.array(cal["center_px"], float)
    th = np.load(theta_npy); mids = (np.arange(len(th)) * 4 + 2) * 1e3
    depth = None if depth_npy is None else np.load(depth_npy)
    f = h5py.File(h5_path, "r")
    Q = [prep(m, C) for m in maps_quarters(f, th, mids, c0, e, depth, C)]
    pair = [ncc(Q[i], Q[j]) for i in range(len(Q)) for j in range(i + 1, len(Q))]
    return float(np.mean(pair)), pair


if __name__ == "__main__":
    # usage: delta_consistency.py <events.h5> <theta.npy> <calibration.json> <out.json> <name:depth.npy:C> ...
    h5, th, cal, out = sys.argv[1:5]
    res = {}
    for spec in sys.argv[5:]:
        name, rest = spec.split(":", 1)
        dp, C = rest.rsplit(":", 1)                      # 경로에 ":"(C:/...)가 있어도 안전
        mean, pair = score(h5, th, cal, None if dp == "none" else dp, int(C))
        res[name] = {"mean_pairwise_ncc": mean, "pairs": pair}
        print(f"{name:20s} mean pairwise NCC = {mean:.4f}   pairs {np.round(pair, 3).tolist()}", flush=True)
    json.dump(res, open(out, "w"), indent=1)
