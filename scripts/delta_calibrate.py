#!/usr/bin/env python3
# §155: 영상에 맞춰 손으로 넣었던 값(오프셋 방향 103도, 오프셋 범위/층 간격, 회전 중심)을 영상에서 자동 추정하는
# 보정(calibration) 알고리즘. 영상이 바뀌면 같은 코드가 값을 새로 구하고, 모델(깊이별 회전중심 오프셋이 한 직선
# 위)이 안 맞으면 그렇다고 보고한다. 특정 영상의 값은 코드에 없다.
#
# 모델: 깊이 Z의 영상 움직임 = 회전중심이 c0 + s(Z)*e (e 고정 방향)인 회전. 지역(tile)별 최적 회전중심들은 한 직선
# 위에 놓인다. 알고리즘:
#   1) 회전이 빠르고 이벤트가 많은 구간을 자동 선택(점수 = 평균|omega| * sqrt(이벤트 수))
#   2) 구간을 TX x TY 지역으로 나누고, 지역 이벤트를 무작위 반반으로 나눠 각각 회전중심을 coarse-to-fine 탐색
#      (경계에 걸리면 범위 확장). 두 반쪽의 결과가 일치하는 지역만 신뢰.
#   3) 신뢰된 중심들에 PCA 직선 피팅: 방향 e, 영상 중심에서 가장 가까운 직선 위의 점 c0, 오프셋 s = (t-c0).e
#   4) 직선 위에서 선명도-대-s 곡선의 봉우리 반치폭(FWHM)의 중앙값으로 층 간격 = FWHM/2, 범위 = s 분포 상위 분위
#   5) 진단: 직선 적합도(PCA 분산비), 신뢰 지역 비율 -> 모델 부적합 판정
import json
import sys

import h5py
import numpy as np

W_PX, H_PX = 960, 720
SEG_MS = 32          # 보정에 쓰는 구간 길이(밴드 8개 x 4ms)
N_SEG = 6            # 선택 구간 수
TX, TY = 6, 4
N_EV = 12000         # 지역당 사용 이벤트 수(반반 분할 전)
AGREE_PX = 20.0      # 두 반쪽 일치 허용(층 간격 규모의 해상도 단위)
COARSE_STEP = 20
FINE_STEP, FINE_HALF = 5, 20
R0, R_MAX = 300, 900


def coll(x, y, a, cx, cy):
    c, sn = np.cos(-a), np.sin(-a)
    xr = cx + c * (x - cx) - sn * (y - cy)
    yr = cy + sn * (x - cx) + c * (y - cy)
    key = np.rint(yr).astype(np.int64) * 4096 + np.rint(xr).astype(np.int64)
    _, cnt = np.unique(key, return_counts=True)
    cnt = cnt.astype(np.float64)
    n = cnt.sum()
    return float((cnt * (cnt - 1)).sum() / max(n * (n - 1), 1))


def best_center(x, y, a, c_nom):
    """coarse-to-fine로 공칭중심 기준 오프셋 (dx,dy) 탐색. 경계에 걸리면 범위를 1.5배씩 확장."""
    R = R0
    while True:
        cand = np.arange(-R, R + 1, COARSE_STEP)
        best, bd = -1.0, (0, 0)
        for dy in cand:
            for dx in cand:
                v = coll(x, y, a, c_nom[0] + dx, c_nom[1] + dy)
                if v > best:
                    best, bd = v, (dx, dy)
        if max(abs(bd[0]), abs(bd[1])) < R or R >= R_MAX:
            break
        R = int(R * 1.5)
    fine = np.arange(-FINE_HALF, FINE_HALF + 1, FINE_STEP)
    center, best_f = bd, best
    for dy in fine:
        for dx in fine:
            v = coll(x, y, a, c_nom[0] + bd[0] + dx, c_nom[1] + bd[1] + dy)
            if v > best_f:
                best_f, center = v, (bd[0] + dx, bd[1] + dy)
    return center, best_f


def select_segments(res, n_seg=N_SEG, seg_ms=SEG_MS):
    base = int(res[1, 0] - res[0, 0])
    k = seg_ms // base
    scores = []
    for i in range(0, len(res) - k + 1):
        om = np.abs(res[i:i + k, 1]).mean()
        n = res[i:i + k, 4].sum()
        scores.append((om * np.sqrt(n), int(res[i, 0])))
    scores.sort(reverse=True)
    chosen = []
    for sc, t0 in scores:
        if all(abs(t0 - c) >= 3 * seg_ms for c in chosen):
            chosen.append(t0)
        if len(chosen) == n_seg:
            break
    return sorted(chosen)


def run(h5_path, omega_npy, out_json, c_nom=(W_PX / 2, H_PX / 2), seed=0):
    rng = np.random.default_rng(seed)
    res = np.load(omega_npy)
    base = int(res[1, 0] - res[0, 0])
    bounds_ms = np.concatenate([res[:, 0], [res[-1, 0] + base]])
    cum = np.concatenate([[0.0], np.cumsum(res[:, 1] * base * 1e-3)])
    f = h5py.File(h5_path, "r")
    m = f["ms_to_idx"][:].astype(np.int64)
    segs = select_segments(res)
    print("selected segments (ms):", segs, flush=True)
    tw, th_ = W_PX // TX, H_PX // TY
    pts = []   # (seg, tx, ty, cx, cy, agree_dist, reliable)
    for t0 in segs:
        s, e = m[t0], m[t0 + SEG_MS]
        X = f["events/x"][s:e].astype(np.float64); Y = f["events/y"][s:e].astype(np.float64)
        T = f["events/t"][s:e].astype(np.float64)
        ang = np.interp(T * 1e-3, bounds_ms, cum) - np.interp(t0 + SEG_MS / 2, bounds_ms, cum)
        for ty in range(TY):
            for tx in range(TX):
                k = np.flatnonzero((X >= tx * tw) & (X < (tx + 1) * tw) & (Y >= ty * th_) & (Y < (ty + 1) * th_))
                if len(k) < 2 * 3000:
                    continue
                k = rng.permutation(k)[:N_EV]
                half = len(k) // 2
                (da, _), (db, _) = (best_center(X[k[:half]], Y[k[:half]], ang[k[:half]], c_nom),
                                    best_center(X[k[half:]], Y[k[half:]], ang[k[half:]], c_nom))
                d = float(np.hypot(da[0] - db[0], da[1] - db[1]))
                pts.append((t0, tx, ty, (da[0] + db[0]) / 2, (da[1] + db[1]) / 2, d, d <= AGREE_PX))
        print(f"  seg {t0}: tiles so far {len(pts)}, reliable {sum(p[6] for p in pts)}", flush=True)
    good = np.array([[p[3], p[4]] for p in pts if p[6]])
    diag = {"tiles_total": len(pts), "tiles_reliable": int(len(good))}
    if len(good) < 6:
        diag["valid"] = False
        json.dump({"valid": False, "diag": diag}, open(out_json, "w"), indent=1)
        print("calibration INVALID: too few reliable tiles", diag)
        return
    mu = good.mean(0)
    u, sv, vt = np.linalg.svd(good - mu, full_matrices=False)
    e = vt[0]
    var_ratio = float((sv[1] ** 2) / (sv[0] ** 2 + 1e-12))
    # 영상 중심(공칭 중심)에서 직선까지 가장 가까운 점 c0
    c0 = mu + e * float(((np.zeros(2) - mu) @ e))     # 오프셋 좌표계에서 공칭중심 = (0,0)
    s_all = (good - c0) @ e
    if np.median(s_all) < 0:
        e, s_all = -e, -s_all
    # 선 위 s에 대한 선명도 곡선의 FWHM
    fw = []
    for t0 in segs:
        s_, e_ = m[t0], m[t0 + SEG_MS]
        X = f["events/x"][s_:e_].astype(np.float64); Y = f["events/y"][s_:e_].astype(np.float64)
        T = f["events/t"][s_:e_].astype(np.float64)
        ang = np.interp(T * 1e-3, bounds_ms, cum) - np.interp(t0 + SEG_MS / 2, bounds_ms, cum)
        for (st, tx, ty, cx, cy, d, ok) in pts:
            if st != t0 or not ok:
                continue
            k = np.flatnonzero((X >= tx * tw) & (X < (tx + 1) * tw) & (Y >= ty * th_) & (Y < (ty + 1) * th_))
            k = rng.permutation(k)[:N_EV]
            grid = np.arange(-60, max(s_all.max() * 1.5, 120) + 1, 5.0)
            cn = np.asarray(c_nom, float) + c0
            v = np.array([coll(X[k], Y[k], ang[k], cn[0] + g * e[0], cn[1] + g * e[1]) for g in grid])
            base_v, pk = np.median(v), int(v.argmax())
            if v[pk] < 1.2 * base_v:
                continue
            half = base_v + 0.5 * (v[pk] - base_v)
            lo = pk
            while lo > 0 and v[lo - 1] >= half:
                lo -= 1
            hi = pk
            while hi < len(v) - 1 and v[hi + 1] >= half:
                hi += 1
            fw.append((hi - lo + 1) * 5.0)
    step = float(np.median(fw) / 2) if fw else float("nan")
    smax = float(np.percentile(s_all, 98))
    out = {"valid": bool(var_ratio < 0.25), "direction_deg": float(np.degrees(np.arctan2(e[1], e[0])) % 360),
           "unit_vector": [float(e[0]), float(e[1])],
           "center_px": [float(c_nom[0] + c0[0]), float(c_nom[1] + c0[1])],
           "center_shift_from_nominal_px": [float(c0[0]), float(c0[1])],
           "s_max_px": smax, "s_median_px": float(np.median(s_all)), "s_min_px": float(s_all.min()),
           "layer_step_px": step, "fwhm_median_px": float(np.median(fw)) if fw else None,
           "line_variance_ratio": var_ratio, "diag": diag,
           "tiles": [[int(p[0]), int(p[1]), int(p[2]), float(p[3]), float(p[4]), float(p[5]), bool(p[6])] for p in pts]}
    json.dump(out, open(out_json, "w"), indent=1)
    print(json.dumps(out, indent=1))


if __name__ == "__main__":
    # usage: delta_calibrate.py <events.h5> <omega.npy> <out.json>
    run(sys.argv[1], sys.argv[2], sys.argv[3], seed=int(sys.argv[4]) if len(sys.argv) > 4 else 0)
