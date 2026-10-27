#!/usr/bin/env python3
# 실제 DELTA 영상에서 키프레임(SLAM) 방식 시험 -- 기준은 syn/reports/keyframe_slam/criteria_delta.md (K 실행 전에 커밋: 0ac8fed, 128f1b0).
# B1 = scripts/delta_map_track.py track() 그대로, K = 키프레임 3도 + 이벤트별 작은 각도 보정 + 후보 각도차 10도 이내 루프 클로저 + 자세 그래프,
# K-global = K와 같되 루프 클로저 후보를 전 범위(+-180도) 회전 탐색으로 바꾼 변형. 평가 = 앞/뒤 절반 월드맵 정합(delta_eval_halves.py 전처리).
# 구현 세부(기준 문서에 없던 것): 루프 클로저 NCC는 센서 직사각형 틀 영향을 피하려고 반지름 340 원형 마스크 안에서 계산.
# 사용: python keyframe_slam_delta.py <omega.npy> <K|global> <out.txt>
import sys
import time

sys.path.insert(0, "scripts")
import h5py
import numpy as np
from scipy import ndimage as ndi
from scipy.ndimage import map_coordinates

import delta_map_track as bt
import keyframe_slam_test as ks
from delta_rotation_cmax import CX, CY, H5, WIN_MS

CANVAS, OFF, SIGMA, SUB = 1200, 600, 2.0, 20000
CANDS = np.radians(np.arange(-1.5, 1.5 + 1e-9, 0.25))
KF_DEG, NLOC = 3.0, 2
HALF_WIN = 199                                        # 0.795 s / 4 ms
YY, XX = np.mgrid[0:CANVAS, 0:CANVAS]
MASK = np.hypot(XX - OFF, YY - OFF) <= 340


def blur_log(a): return ndi.gaussian_filter(np.log1p(np.asarray(a, np.float32)), SIGMA)


def warp(img, ang):
    sx, sy = ks.rot((XX - OFF).astype(np.float32), (YY - OFF).astype(np.float32), -ang)
    return map_coordinates(np.asarray(img, np.float32), [sy + OFF, sx + OFF], order=1, mode="constant", cval=0.0)


def look(bl, x, y):
    ix, iy = np.rint(x + OFF).astype(int), np.rint(y + OFF).astype(int)
    ok = (ix >= 0) & (ix < CANVAS) & (iy >= 0) & (iy < CANVAS); v = np.zeros(len(x), np.float32); v[ok] = bl[iy[ok], ix[ok]]
    return v


class KF:
    def __init__(self, theta, win0): self.theta, self.win0, self.img, self.bl, self.pts = theta, win0, np.zeros((CANVAS, CANVAS), np.float32), None, None


def prepare(kf, rng, npts):
    kf.bl = blur_log(kf.img); flat = kf.img.ravel(); top = np.argpartition(flat, -SUB)[-SUB:]; top = top[flat[top] > 0]
    top = rng.choice(top, min(npts, len(top)), replace=False) if len(top) > npts else top
    kf.pts = ((top % CANVAS) - OFF).astype(np.float32), ((top // CANVAS) - OFF).astype(np.float32), np.log1p(flat[top])


def curve(bl, pts, rs):
    x, y, w = pts; sw = w.sum()
    return np.array([(w * look(bl, *ks.rot(x, y, r))).sum() / sw for r in rs])


def closures(kfs, j, mode, rng, diag):
    kj = kfs[j]; out = []
    if kj.pts is None or len(kj.pts[0]) < 100: return out
    for i in range(0, j - ks.LC_GAP):
        r0 = kfs[i].theta - kj.theta
        if mode == "K":
            if abs(r0) > ks.LC_SPAN: continue
            ds = np.arange(-ks.LC_RANGE, ks.LC_RANGE + 1e-9, ks.STEP); sc = curve(kfs[i].bl, kj.pts, r0 + ds); k = int(sc.argmax())
            far = np.abs(ds - ds[k]) > np.radians(1.5); rstar = r0 + ds[k]
        else:
            if i % 3: continue
            rs = np.radians(np.arange(-180, 180, 1.0)); sc = curve(kfs[i].bl, kj.pts, rs); k = int(sc.argmax())
            far = np.abs(np.angle(np.exp(1j * (rs - rs[k])))) > np.radians(3.0)
            fine = rs[k] + np.radians(np.arange(-1, 1.0001, 0.25)); rstar = fine[int(curve(kfs[i].bl, kj.pts, fine).argmax())]
            rstar += 2 * np.pi * np.round((r0 - rstar) / (2 * np.pi))
        ok_ratio = sc[k] > 0 and not (far.any() and sc[k] < ks.LC_RATIO * sc[far].max())
        if not ok_ratio: diag.append((i, j, None)); continue
        B = blur_log(warp(kj.img, rstar)); ncc = float(np.corrcoef(kfs[i].bl[MASK], B[MASK])[0, 1]); diag.append((i, j, ncc))
        if ncc >= ks.LC_COS: out.append((i, j, -rstar))
    return out


def run_K(res, mode):
    rng = np.random.default_rng(0); f = h5py.File(H5, "r"); m = f["ms_to_idx"][:].astype(np.int64)
    kfs = [KF(0.0, 0)]; odo, loops, diag = [], [], []; prev = np.zeros((CANVAS, CANVAS), np.float32); theta_prev = 0.0; ths, wk = [], []
    for w, row in enumerate(res):
        s, e = m[w * WIN_MS], m[(w + 1) * WIN_MS]; om = row[1]; n = e - s; cur = kfs[-1]; base = cur.theta
        theta_mid_pred = theta_prev + om * WIN_MS * 1e-3 / 2; best_d = 0.0
        if n >= 5000:
            pool = np.arange(n); idx = np.sort(rng.choice(pool, min(SUB, n), replace=False))
            x = f["events/x"][s:e][idx].astype(np.float64) - CX; y = f["events/y"][s:e][idx].astype(np.float64) - CY
            t = f["events/t"][s:e][idx].astype(np.float64) * 1e-6; dt = t - (w * WIN_MS + WIN_MS / 2) * 1e-3
            M = prev + cur.img
            if M.max() > 0:
                bl = blur_log(M); best = -1.0
                for d in sorted(CANDS, key=abs):
                    xi, yi, ok = bt.project(x, y, -(theta_mid_pred + d + om * dt - base), OFF)
                    sc = float(bl[yi[ok], xi[ok]].sum()) / len(x)
                    if sc > best + 1e-9: best, best_d = sc, d
        theta_mid = theta_mid_pred + best_d; theta_prev = theta_mid + om * WIN_MS * 1e-3 / 2; ths.append(theta_mid); wk.append(len(kfs) - 1)
        if n >= 5000:
            xa = f["events/x"][s:e].astype(np.float64) - CX; ya = f["events/y"][s:e].astype(np.float64) - CY
            dta = f["events/t"][s:e].astype(np.float64) * 1e-6 - (w * WIN_MS + WIN_MS / 2) * 1e-3
            xi, yi, ok = bt.project(xa, ya, -(theta_mid + om * dta - base), OFF)
            cur.img += np.bincount(yi[ok] * CANVAS + xi[ok], minlength=CANVAS * CANVAS).reshape(CANVAS, CANVAS).astype(np.float32)
            if abs(theta_mid - base) >= np.radians(KF_DEG):
                prepare(cur, rng, 20000 if mode == "K" else 3000); loops += closures(kfs, len(kfs) - 1, mode, rng, diag)
                odo.append((len(kfs) - 1, len(kfs), theta_mid - base)); kfs.append(KF(theta_mid, w + 1))
                prev = np.zeros((CANVAS, CANVAS), np.float32)
                for j in range(max(0, len(kfs) - 1 - NLOC), len(kfs) - 1): prev += warp(kfs[j].img, theta_mid - kfs[j].theta)
        if w % 50 == 0: print(f"window {w}/{len(res)} kfs {len(kfs)} loops {len(loops)}", flush=True)
    th_opt = ks.solve_graph(len(kfs), odo, loops); ths = np.array(ths); wk = np.array(wk); on = np.array([k.theta for k in kfs])
    resid = [np.degrees((th_opt[j] - th_opt[i]) - mm) for i, j, mm in loops]
    return dict(online=ths, corr=th_opt[wk] + (ths - on[wk]), kfs=kfs, th_opt=th_opt, loops=loops, diag=diag, resid=resid)


def prep(mm):
    mm = np.minimum(mm, np.percentile(mm[mm > 0], 99)); g = ndi.gaussian_filter(mm, 2) - ndi.gaussian_filter(mm, 12)
    g[(XX - 600) ** 2 + (YY - 600) ** 2 > 450 ** 2] = 0; return g


def ncc(a, b): a = a - a.mean(); b = b - b.mean(); return float((a * b).sum() / np.sqrt((a * a).sum() * (b * b).sum()))


def half_score(A, B):
    a, b = prep(A), prep(B); ps = np.arange(-4, 4.01, 0.5); sc = [ncc(a, ndi.rotate(b, p, reshape=False, order=1)) for p in ps]
    k = int(np.argmax(sc)); return float(ps[k]), sc[k], sc[int(np.flatnonzero(ps == 0)[0])]


def halves_from_theta(th):
    f = h5py.File(H5, "r"); n = f["events/t"].shape[0]; mids = (np.arange(len(th)) * WIN_MS + WIN_MS / 2) * 1e3
    maps = [np.zeros(CANVAS * CANVAS, np.float64) for _ in range(2)]
    for s in range(0, n, 4_000_000):
        x = f["events/x"][s:s + 4_000_000].astype(float) - CX; y = f["events/y"][s:s + 4_000_000].astype(float) - CY; t = f["events/t"][s:s + 4_000_000].astype(float)
        a = -np.interp(t, mids, th); c, sn = np.cos(a), np.sin(a)
        xi = np.rint(c * x - sn * y + OFF).astype(np.int64); yi = np.rint(sn * x + c * y + OFF).astype(np.int64)
        ok = (xi >= 0) & (xi < CANVAS) & (yi >= 0) & (yi < CANVAS); h = (t >= 0.5e6 * 1.59).astype(int)
        for k in (0, 1): q = ok & (h == k); maps[k] += np.bincount(yi[q] * CANVAS + xi[q], minlength=CANVAS * CANVAS)
    return [mm.reshape(CANVAS, CANVAS).astype(np.float32) for mm in maps]


def main():
    res = np.load(sys.argv[1]); mode = sys.argv[2]; out = sys.argv[3]; lines = []
    def log(s): print(s, flush=True); lines.append(s)
    t0 = time.time(); th_b1, _ = bt.track(res); log(f"B1 track {time.time() - t0:.0f}s, final theta {np.degrees(th_b1[-1]):.1f} deg")
    A, B = halves_from_theta(th_b1); r, c, c0 = half_score(A, B); log(f"B1 halves: best rotation {r:+.1f} deg, ncc max {c:.3f}, ncc@0 {c0:.3f}")
    t0 = time.time(); r_k = run_K(res, mode); log(f"{mode} run {time.time() - t0:.0f}s, KFs {len(r_k['kfs'])}, accepted loops {len(r_k['loops'])}")
    th_opt = r_k["th_opt"]; a = np.zeros((CANVAS, CANVAS), np.float32); b = np.zeros((CANVAS, CANVAS), np.float32)
    for k, kf in enumerate(r_k["kfs"]): (a if kf.win0 < HALF_WIN else b).__iadd__(warp(kf.img, 0.0 - th_opt[k]))
    rk, ck, c0k = half_score(a, b); log(f"{mode} halves (keyframe maps): best rotation {rk:+.1f} deg, ncc max {ck:.3f}, ncc@0 {c0k:.3f}")
    A2, B2 = halves_from_theta(r_k["corr"]); re_, ce, c0e = half_score(A2, B2); log(f"{mode} halves (event maps, corrected theta, diagnostic): best rotation {re_:+.1f} deg, ncc max {ce:.3f}, ncc@0 {c0e:.3f}")
    dd = np.degrees(np.abs(r_k["corr"] - th_b1)); log(f"D2 max |theta_K,corr - theta_B1| = {dd.max():.2f} deg (mean {dd.mean():.2f}); online-vs-B1 max {np.degrees(np.abs(r_k['online'] - th_b1)).max():.2f}")
    rs = r_k["resid"]; log(f"D3 loops accepted {len(r_k['loops'])}, residual RMS {np.sqrt(np.mean(np.square(rs))) if rs else float('nan'):.3f} deg")
    nccs = [d[2] for d in r_k["diag"] if d[2] is not None]
    log(f"diag: candidates {len(r_k['diag'])}, passed ratio test {len(nccs)}, NCC of those: " + (f"min {min(nccs):.2f} median {np.median(nccs):.2f} max {max(nccs):.2f}" if nccs else "none"))
    d0 = abs(c0 - 0.239) <= 0.02 and abs(r) <= 0.5; d1 = abs(rk) <= 2 and c0k >= 1.10 * c0; d3 = len(r_k["loops"]) >= 3 and rs and np.sqrt(np.mean(np.square(rs))) <= 1.0
    log(f"== D0 {'PASS' if d0 else 'FAIL'} | D1 {'GAIN' if d1 else ('WORSE' if c0k < 0.9 * c0 else 'NO GAIN')} (ncc@0 ratio {c0k / c0:.2f}) | D2 {'PASS' if dd.max() <= 3 else 'FAIL'} | D3 {'PASS' if d3 else 'FAIL'}")
    np.save(out.replace(".txt", "_theta_corr.npy"), r_k["corr"]); np.save(out.replace(".txt", "_theta_b1.npy"), th_b1)
    open(out, "w", encoding="utf-8").write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
