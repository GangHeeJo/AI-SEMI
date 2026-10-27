#!/usr/bin/env python3
# 키프레임(SLAM) 방식 소프트웨어 프로토타입 -- 평가 기준은 syn/reports/keyframe_slam/criteria.md (코드 작성 전에 커밋, 41a405a).
# 합성 데이터(정답 각도 있음): 원판 장면(시차 없음) + 패치 256x256 + 회전중심=패치 중심.
# 방법: B0 창 대 창 적분 / B1 누적 월드맵 정합(현재 설계 해당) / K-fine(간격 0.45도) / K-coarse(간격 3도 + 이벤트별 작은 각도 보정)
#   K = 로컬 키프레임 맵으로 추적 + 키프레임 쌍 정합 루프 클로저 + 1차원 자세 그래프(가중 최소제곱).
# 사용: python keyframe_slam_test.py [--selftest] [--rate 400] [--out result.txt]
import sys
import time

import numpy as np
from scipy.ndimage import binary_dilation, gaussian_filter, map_coordinates

N, C = 256, 128
SIG, DT = 1.5, 2e-3
SEARCH, STEP = np.radians(2.5), np.radians(0.25)
GRID = np.arange(-SEARCH, SEARCH + 1e-9, STEP)
CLIP = 3                                              # 2비트 셀(현재 월드 메모리와 동일)
LC_COS, LC_RATIO, LC_SPAN, LC_GAP, LC_RANGE = 0.5, 1.5, np.radians(10), 5, np.radians(6)
YY, XX = np.mgrid[0:N, 0:N]
DISK = np.hypot(XX + 0.5 - C, YY + 0.5 - C) <= 125
PROFILES = {"P1": [(0, 0), (0.6, 170)], "P2": [(0, 0), (0.5, 120), (1.0, 0), (1.5, 120)], "P3": [(0, 0), (0.6, 170), (1.1, 40), (1.6, 170)]}


def rot(x, y, a):
    c, s = np.cos(a), np.sin(a)
    return c * x - s * y, s * x + c * y


def make_theta(knots):
    kt = np.array([k[0] for k in knots], float); ka = np.radians([k[1] for k in knots])

    def f(t):
        t = np.clip(np.asarray(t, float), kt[0], kt[-1] - 1e-12)
        i = np.clip(np.searchsorted(kt, t, side="right") - 1, 0, len(kt) - 2)
        u = (t - kt[i]) / (kt[i + 1] - kt[i])
        return ka[i] + (ka[i + 1] - ka[i]) * 0.5 * (1 - np.cos(np.pi * u))
    return f, kt[-1]


def make_scene(seed):
    r = np.random.default_rng(1000 + seed)
    segs = []
    while len(segs) < 40:
        a, b = r.uniform(-128, 128, (2, 2))
        if np.hypot(*a) < 125 and np.hypot(*b) < 125 and 20 < np.hypot(*(a - b)) < 120:
            segs.append((*a, *b))
    dots = []
    while len(dots) < 60:
        p = r.uniform(-125, 125, 2)
        if np.hypot(*p) < 125: dots.append(tuple(p))
    return np.array(segs), np.array(dots)


def gen_windows(scene, theta_fn, T, rate_per_ms, seed):
    rng = np.random.default_rng(seed)
    S, D = scene; nseg = len(S)
    L = np.hypot(S[:, 2] - S[:, 0], S[:, 3] - S[:, 1]); w_el = np.concatenate([L, np.full(len(D), 12.0)]); w_el /= w_el.sum()
    n = int(rate_per_ms * DT * 1e3); wins = []
    for w in range(int(round(T / DT))):
        xs, ys, got = [], [], 0
        while got < n:
            m = max(4 * (n - got), 2000)
            el = rng.choice(len(w_el), m, p=w_el); seg = el < nseg
            sg = S[np.minimum(el, nseg - 1)]; u = rng.random(m)
            qx = np.where(seg, sg[:, 0] + u * (sg[:, 2] - sg[:, 0]), D[np.maximum(el - nseg, 0), 0])
            qy = np.where(seg, sg[:, 1] + u * (sg[:, 3] - sg[:, 1]), D[np.maximum(el - nseg, 0), 1])
            dx, dy = sg[:, 2] - sg[:, 0], sg[:, 3] - sg[:, 1]; Ln = np.maximum(np.hypot(dx, dy), 1e-9)
            t = w * DT + rng.random(m) * DT; th = theta_fn(t)
            px, py = rot(qx, qy, th); nx, ny = rot(-dy / Ln, dx / Ln, th)
            om = (theta_fn(t + 1e-4) - theta_fn(t - 1e-4)) / 2e-4
            vn = np.abs(-om * py * nx + om * px * ny)
            acc = np.where(seg, np.minimum(vn / 400.0, 1.0), 0.5)
            px = px + rng.normal(0, 0.6, m); py = py + rng.normal(0, 0.6, m)
            ok = (rng.random(m) < acc) & (np.abs(px) < C) & (np.abs(py) < C)
            xs.append(px[ok]); ys.append(py[ok]); got += int(ok.sum())
        px = np.concatenate(xs)[:n]; py = np.concatenate(ys)[:n]
        nb = int(0.03 * n); px[:nb] = rng.uniform(-C, C, nb); py[:nb] = rng.uniform(-C, C, nb)
        wins.append((np.floor(px) + 0.5, np.floor(py) + 0.5))              # 정수 픽셀로 양자화한 중심좌표
    return wins


def lookup(M, x, y):
    ix, iy = np.floor(x + C).astype(int), np.floor(y + C).astype(int)
    ok = (ix >= 0) & (ix < N) & (iy >= 0) & (iy < N); v = np.zeros(len(x), np.float32); v[ok] = M[iy[ok], ix[ok]]
    return v


def blur(img): return gaussian_filter(img.astype(np.float32), SIG)


def add_events(img, x, y):
    ix, iy = np.floor(x + C).astype(int), np.floor(y + C).astype(int)
    ok = (ix >= 0) & (ix < N) & (iy >= 0) & (iy < N); np.add.at(img, (iy[ok], ix[ok]), 1); np.minimum(img, CLIP, out=img)


def warp(img, ang):
    """frame_j 영상을 ang만큼 회전한 영상 (p' = R(ang) p). out(p') = img(R(-ang) p')."""
    x, y = XX + 0.5 - C, YY + 0.5 - C; sx, sy = rot(x, y, -ang)
    return map_coordinates(img.astype(np.float32), [sy + C - 0.5, sx + C - 0.5], order=1, mode="constant", cval=0.0)


def best_shift(scores):
    """점수 최대 후보, 동점이면 |d| 작은 쪽."""
    s = np.asarray(scores); mx = s.max(); idx = np.flatnonzero(s >= mx - 1e-9)
    return idx[np.argmin(np.abs(GRID[idx]))]


def build_map(wins, ths):
    W = np.zeros((N, N), np.float32)
    for (px, py), th in zip(wins, ths):
        x, y = rot(px, py, -th); add_events(W, x, y)
    return W


def run_B0(wins):
    ths, th, om = [0.0], 0.0, 0.0
    for w in range(1, len(wins)):
        prev = np.zeros((N, N), np.float32); add_events(prev, *wins[w - 1]); Mb = blur(prev); px, py = wins[w]
        pred = om * DT
        if len(wins[w - 1][0]) and w >= 3:
            d = GRID[best_shift([lookup(Mb, *rot(px, py, -(pred + d_))).sum() for d_ in GRID])]
        else: d = 0.0
        step = pred + d; th += step; om = 0.5 * om + 0.5 * step / DT; ths.append(th)
    return np.array(ths)


def run_B1(wins):
    W = np.zeros((N, N), np.float32); ths, th, om = [], 0.0, 0.0
    for w, (px, py) in enumerate(wins):
        pred = th + om * DT if w else 0.0
        if w >= 3:
            Mb = blur(W); d = GRID[best_shift([lookup(Mb, *rot(px, py, -(pred + d_))).sum() for d_ in GRID])]
        else: d = 0.0
        new = pred + d; om = 0.5 * om + 0.5 * (new - th) / DT if w else 0.0; th = new
        add_events(W, *rot(px, py, -th)); ths.append(th)
    return np.array(ths), W


class KF:
    def __init__(self, theta, ttrue=0.0): self.theta, self.ttrue, self.img, self.bl = theta, ttrue, np.zeros((N, N), np.float32), None


def local_map(kfs, upto, phi, nloc):
    M = np.zeros((N, N), np.float32)
    for j in range(max(0, upto - nloc + 1), upto + 1): M += warp(kfs[j].img, phi - kfs[j].theta)
    return np.minimum(M, CLIP)


def try_closures(kfs, j, truth_th):
    """완성된 키프레임 j를 이전 키프레임들과 정합. 반환: [(i, j, 측정 theta_j-theta_i)]"""
    kj = kfs[j]; iy, ix = np.nonzero(kj.img); wgt = kj.img[iy, ix]; cx, cy = ix + 0.5 - C, iy + 0.5 - C
    if len(wgt) < 30: return []
    out = []
    for i in range(0, j - LC_GAP):
        if abs(kfs[i].theta - kj.theta) > LC_SPAN: continue
        r0 = kfs[i].theta - kj.theta
        ds = np.arange(-LC_RANGE, LC_RANGE + 1e-9, STEP)
        sc = np.array([(wgt * lookup(kfs[i].bl, *rot(cx, cy, r0 + d))).sum() / wgt.sum() for d in ds])
        k = int(sc.argmax()); far = np.abs(ds - ds[k]) > np.radians(1.5)
        if sc[k] <= 0 or (far.any() and sc[k] < LC_RATIO * sc[far].max()): continue
        r = r0 + ds[k]; B = blur(warp(kj.img, r)); A = kfs[i].bl
        ncc = np.corrcoef(A[DISK], B[DISK])[0, 1]
        if ncc >= LC_COS: out.append((i, j, -r))
    return out


def solve_graph(n, odo, loops):
    rows, rhs, wts = [], [], []
    for k, _, rel in odo:
        r = np.zeros(n); r[k], r[k + 1] = -1, 1; rows.append(r); rhs.append(rel); wts.append(1 / (0.05 * abs(np.degrees(rel)) + 0.1))
    for i, j, m in loops:
        r = np.zeros(n); r[i], r[j] = -1, 1; rows.append(r); rhs.append(m); wts.append(1 / 0.3)
    r = np.zeros(n); r[0] = 1; rows.append(r); rhs.append(0.0); wts.append(1e3)
    A = np.array(rows) * np.array(wts)[:, None]; b = np.array(rhs) * np.array(wts)
    # 각도는 도 단위 가중이므로 rad 로 풀되 가중 상수는 곱해진 상태
    return np.linalg.lstsq(A, b, rcond=None)[0]


def run_K(wins, delta_deg, per_event, truth_th):
    D = np.radians(delta_deg); nloc = max(2, int(round(5.0 / delta_deg)))
    kfs = [KF(0.0)]; odo, loops = [], []; cur = 0; th, om = 0.0, 0.0
    prev_map = np.zeros((N, N), np.float32); ths, win_kf = [], []
    for w, (px, py) in enumerate(wins):
        pred = th + om * DT if w else 0.0
        M = prev_map + kfs[cur].img
        if w >= 3 and M.sum() > 0:
            Mb = blur(M); base = kfs[cur].theta
            d = GRID[best_shift([lookup(Mb, *rot(px, py, -(pred + d_ - base))).sum() for d_ in GRID])]
        else: d = 0.0
        new = pred + d; om = 0.5 * om + 0.5 * (new - th) / DT if w else 0.0; th = new
        x, y = rot(px, py, -(th - kfs[cur].theta)) if per_event else (px, py)
        add_events(kfs[cur].img, x, y); ths.append(th); win_kf.append(cur)
        if abs(th - kfs[cur].theta) >= D:
            kfs[cur].bl = blur(kfs[cur].img)
            loops += try_closures(kfs, cur, truth_th)
            odo.append((cur, cur + 1, th - kfs[cur].theta)); kfs.append(KF(th, float(truth_th((w + 0.5) * DT)))); cur += 1
            prev_map = local_map(kfs, cur - 1, th, nloc)
    kfs[cur].bl = blur(kfs[cur].img)
    th_opt = solve_graph(len(kfs), odo, loops)
    ths = np.array(ths); wk = np.array(win_kf); on = np.array([k.theta for k in kfs])
    corr = th_opt[wk] + (ths - on[wk])
    Wm = np.zeros((N, N), np.float32)
    for k, kf in enumerate(kfs): Wm += warp(kf.img, 0.0 - th_opt[k])
    return dict(online=ths, corr=corr, map=Wm, kfs=kfs, loops=loops, th_opt=th_opt)


def render_truth(scene):
    S, D = scene; T = np.zeros((N, N), bool)
    for x1, y1, x2, y2 in S:
        t = np.linspace(0, 1, int(np.hypot(x2 - x1, y2 - y1) * 2) + 2); x, y = x1 + t * (x2 - x1), y1 + t * (y2 - y1)
        T[np.floor(y + C).astype(int), np.floor(x + C).astype(int)] = True
    for x, y in D: T[int(np.floor(y + C)), int(np.floor(x + C))] = True
    return T


def map_metrics(M, T):
    near3 = binary_dilation(T, iterations=3); mass = M[DISK].sum()
    prec = M[DISK & near3].sum() / max(mass, 1e-9); sup = binary_dilation(M >= 0.25, iterations=2)
    return 1 - prec, float(sup[T & DISK].mean())


def err_stats(est, truth_fn):
    tm = truth_fn((np.arange(len(est)) + 0.5) * DT); e = np.degrees(est - tm); return float(np.abs(e).max()), float(np.sqrt((e ** 2).mean()))


def run_case(profile, seed, rate):
    f, T = make_theta(PROFILES[profile]); scene = make_scene(seed); wins = gen_windows(scene, f, T, rate, seed)
    Tm = render_truth(scene); res = {}
    t = time.time()
    th0 = run_B0(wins); res["B0"] = dict(err=err_stats(th0, f), map=map_metrics(build_map(wins, th0), Tm))
    th1, W1 = run_B1(wins); res["B1"] = dict(err=err_stats(th1, f), map=map_metrics(W1, Tm))
    for name, dd, pe in (("K-fine", 0.45, False), ("K-coarse", 3.0, True)):
        r = run_K(wins, dd, pe, f); kfs = r["kfs"]
        lerr = [abs(np.degrees(m - (kfs[j].ttrue - kfs[i].ttrue))) for i, j, m in r["loops"]]
        res[name] = dict(err_corr=err_stats(r["corr"], f), err_on=err_stats(r["online"], f), map=map_metrics(r["map"], Tm),
                         nkf=len(kfs), nloop=len(lerr), nfalse=int(sum(e > 1.0 for e in lerr)), ntrue=int(sum(e <= 1.0 for e in lerr)))
    res["time"] = time.time() - t; res["truth_fn"] = f
    return res


def selftest():
    """부호 확인: 같은 장면을 참 각도 0 / 10도로 쌓은 두 키프레임을 정합하면 theta_j-theta_i = +10도(= 참)가 나와야 함."""
    scene = make_scene(0); f, _ = make_theta([(0, 0), (1.0, 10), (2.0, 10)])
    wins = gen_windows(scene, f, 2.0, 400, 0)
    kfs = [KF(0.0, 0.0), KF(np.radians(10.0), np.radians(10.0))]
    for w in range(0, 5): add_events(kfs[0].img, *wins[w])
    for w in range(len(wins) - 5, len(wins)): add_events(kfs[1].img, *wins[w])
    for k in kfs: k.bl = blur(k.img)
    kfs = [kfs[0]] + [KF(0.0)] * 6 + [kfs[1]]; kfs[7].theta = np.radians(7.0)    # 추정이 3도 틀린 것으로 가정(LC_GAP 때문에 중간에 더미)
    for k in kfs[1:7]: k.img = np.zeros((N, N), np.float32); k.bl = blur(k.img); k.theta = np.radians(40.0)
    out = try_closures(kfs, 7, f)
    print("selftest closures:", [(i, j, round(float(np.degrees(m)), 2)) for i, j, m in out])
    assert out and abs(np.degrees(out[0][2]) - 10.0) < 0.6, "루프 클로저 부호/크기 오류"
    print("selftest OK")


def main():
    rate = 400; out = None; a = sys.argv[1:]
    if "--selftest" in a: return selftest()
    if "--rate" in a: rate = float(a[a.index("--rate") + 1])
    if "--out" in a: out = a[a.index("--out") + 1]
    lines = [f"rate={rate}/ms  windows=2ms  seeds=0,1,2"]
    hdr = f"{'case':8s}{'method':10s}{'maxerr deg':>11s}{'rms deg':>9s}{'ghost%':>8s}{'cover%':>8s}{'#KF':>6s}{'loops(true/false)':>20s}"
    lines.append(hdr); print(hdr)
    allr = {}
    for prof in ("P1", "P2", "P3"):
        for seed in (0, 1, 2):
            r = run_case(prof, seed, rate); allr[(prof, seed)] = r
            def row(name, e, m, nkf="", lp=""):
                return f"{prof}s{seed:<5d}{name:10s}{e[0]:11.2f}{e[1]:9.2f}{m[0] * 100:8.1f}{m[1] * 100:8.1f}{str(nkf):>6s}{lp:>20s}"
            for name in ("B0", "B1"): lines.append(row(name, r[name]["err"], r[name]["map"]))
            for name in ("K-fine", "K-coarse"):
                k = r[name]; lines.append(row(name + "*", k["err_corr"], k["map"], k["nkf"], f"{k['ntrue']}/{k['nfalse']}")); lines.append(row(name + "(on)", k["err_on"], k["map"], k["nkf"]))
            print("\n".join(lines[-7:]), f"   [{r['time']:.0f}s]", flush=True)
    # 판정(criteria.md)
    lines.append(""); lines.append("== 판정 (K* = 자세 그래프 보정 후) ==")
    for name in ("K-fine", "K-coarse"):
        rev = [(p, s) for p in ("P2", "P3") for s in (0, 1, 2)]; ratios = [allr[x][name]["err_corr"][0] / max(allr[x]["B1"]["err"][0], 1e-9) for x in rev]
        c1 = np.median(ratios) <= 0.5 and max(ratios) <= 1.0
        c2r = [allr[("P1", s)][name]["err_corr"][0] / max(allr[("P1", s)]["B1"]["err"][0], 1e-9) for s in (0, 1, 2)]; c2 = max(c2r) <= 1.2
        better = sum(allr[x][name]["map"][0] <= allr[x]["B1"]["map"][0] for x in rev); covd = max(allr[x]["B1"]["map"][1] - allr[x][name]["map"][1] for x in rev)
        c3 = better >= 5 and covd <= 0.02
        bits = int(np.ceil(180.0 / (0.45 if name == "K-fine" else 3.0))) * N * N * 2; c4 = bits <= 4 * 1024 * 1024 * 2
        nf = sum(allr[x][name]["nfalse"] for x in allr); nt = [allr[x][name]["ntrue"] for x in rev]; c5 = nf == 0 and min(nt) >= 1
        lines.append(f"{name}: C1 {'PASS' if c1 else 'FAIL'} (오차비 중앙값 {np.median(ratios):.2f}, 최대 {max(ratios):.2f}) | C2 {'PASS' if c2 else 'FAIL'} (최대비 {max(c2r):.2f}) | "
                     f"C3 {'PASS' if c3 else 'FAIL'} (잔상 개선 {better}/6, 커버리지 최대 하락 {covd * 100:.1f}%p) | C4 {'PASS' if c4 else 'FAIL'} ({bits / 1e6:.2f} Mbit) | "
                     f"C5 {'PASS' if c5 else 'FAIL'} (거짓 {nf}, 회차별 참 루프 {nt})")
    txt = "\n".join(lines); print("\n".join(lines[-3:]))
    if out: open(out, "w", encoding="utf-8").write(txt + "\n")


if __name__ == "__main__":
    main()
