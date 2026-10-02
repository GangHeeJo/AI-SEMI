#!/usr/bin/env python3
# §159: 합성 정답과 파이프라인 결과 비교. 정답 월드맵 = 장면 Q (공통 좌표계 u = Q, 캔버스 좌표 u + C/2).
#  1) 보정 복원: 방향/중심/범위 vs 정답
#  2) theta 추정 오차(정답 theta와 시작점 정렬 후)
#  3) 맵 vs 정답 장면: 밴드패스 NCC(작은 이동 탐색 +-20px), 변형별(단일 층/자기선택/교차검증)
#  4) 막대 연속성: 정답 막대 길이(320px) 대비 맵 세로선 길이
#  5) 복사본: 맵 자기상관의 고립 봉우리(축 방향 제외) vs 정답 장면 자체의 자기상관
import json
import sys

import numpy as np
from scipy import ndimage as ndi


def render_truth(truth, C, sigma=1.3):
    """공통 좌표계 캔버스(원점 C/2)에 정답 장면을 가우시안 선/점으로 렌더링."""
    img = np.zeros((C, C), np.float32); OFF = C / 2
    for x1, y1, x2, y2, s in truth["segs"]:
        n = int(max(abs(x2 - x1), abs(y2 - y1)) * 2) + 2
        xs = np.linspace(x1, x2, n); ys = np.linspace(y1, y2, n)
        xi = np.rint(xs + OFF).astype(int); yi = np.rint(ys + OFF).astype(int)
        ok = (xi >= 0) & (xi < C) & (yi >= 0) & (yi < C); img[yi[ok], xi[ok]] += 1
    for x, y, s in truth["dots"]:
        xi, yi = int(round(x + OFF)), int(round(y + OFF))
        if 0 <= xi < C and 0 <= yi < C: img[yi, xi] += 12
    return ndi.gaussian_filter(img, sigma)


def prep(m, C, radius=420):
    m = np.log1p(m.astype(np.float32)); g = ndi.gaussian_filter(m, 1.5) - ndi.gaussian_filter(m, 12)
    yy, xx = np.mgrid[:C, :C]; g[(xx - C / 2) ** 2 + (yy - C / 2) ** 2 > radius ** 2] = 0
    return g


def ncc_shift(a, b, R=20):
    best = (-1, 0, 0)
    a0 = a - a.mean()
    for dy in range(-R, R + 1, 2):
        for dx in range(-R, R + 1, 2):
            bs = np.roll(np.roll(b, dy, 0), dx, 1); bs = bs - bs.mean()
            v = float((a0 * bs).sum() / np.sqrt((a0 * a0).sum() * (bs * bs).sum()))
            if v > best[0]: best = (v, dx, dy)
    return best


def rods_len(img, ncols=6):
    z = ndi.gaussian_filter(np.abs(ndi.sobel(ndi.gaussian_filter(img.astype(np.float32), 1.2), axis=1)), 1.0)
    col = z.sum(0); picks = []
    for c in np.argsort(col)[::-1]:
        if all(abs(c - p) > 25 for p in picks): picks.append(int(c))
        if len(picks) == ncols: break
    out = []
    for c in picks:
        prof = z[:, max(c - 3, 0):c + 4].mean(1); ok = ndi.binary_closing(prof > 0.25 * prof.max(), np.ones(15)); lab, n = ndi.label(ok)
        if n: out.append(int(ndi.sum(ok, lab, range(1, n + 1)).max()))
    return out


def replica_peaks(z, R=90):
    z = ndi.gaussian_filter(np.log1p(z.astype(np.float32)), 1.2) - ndi.gaussian_filter(np.log1p(z.astype(np.float32)), 12); z = z - z.mean()
    z = z * np.outer(np.hanning(z.shape[0]), np.hanning(z.shape[1]))
    F = np.fft.fft2(z, s=(2 * z.shape[0], 2 * z.shape[1])); a = np.fft.fftshift(np.fft.ifft2(np.abs(F) ** 2).real); a /= a.max()
    cy, cx = np.array(a.shape) // 2; w = a[cy - R:cy + R + 1, cx - R:cx + R + 1]; yy, xx = np.mgrid[-R:R + 1, -R:R + 1]; rr = np.hypot(yy, xx)
    mx = (w == ndi.maximum_filter(w, size=9)) & (rr >= 8) & (w > 0.05)
    pk = sorted([(round(float(w[y, x]), 2), int(xx[y, x]), int(yy[y, x])) for y, x in zip(*np.nonzero(mx))], reverse=True)
    return [(h, dx, dy) for h, dx, dy in pk if not (dx < 0 or (dx == 0 and dy < 0)) and not (abs(dx) <= 3 or abs(dy) <= 3)][:4]


def main(sp, tag=""):
    truth = dict(np.load(sp + "/syn_truth.npz"))
    cal = json.load(open(sp + f"/calib_syn{tag}.json"))
    e_est = np.array(cal["unit_vector"]); c_est = np.array(cal["center_px"])
    print("== 1) calibration recovery ==")
    print(f"  direction  est {cal['direction_deg']:.1f} deg  truth {float(truth['e_deg']):.1f} deg   error {((cal['direction_deg'] - float(truth['e_deg']) + 180) % 360 - 180):+.1f} deg")
    print(f"  center     est {np.round(c_est, 1).tolist()}  truth {truth['c0'].tolist()}   error {np.round(c_est - truth['c0'], 1).tolist()} px")
    print(f"  s range    est s_min {cal['s_min_px']:.0f} .. s_max {cal['s_max_px']:.0f}  (truth depth offsets 10..228)   valid={cal['valid']}  var_ratio {cal['line_variance_ratio']:.3f}  reliable {cal['diag']['tiles_reliable']}/{cal['diag']['tiles_total']}  layer_step {cal['layer_step_px']}")
    th_t = truth["theta"]; th_e = np.load(sp + f"/trk_syn{tag}_theta.npy"); n = min(len(th_t), len(th_e))
    d = np.degrees(th_e[:n] - th_t[:n]); d -= d[0]
    print("== 2) theta estimate vs truth ==")
    print(f"  final truth {np.degrees(th_t[n - 1]):.1f} deg  est {np.degrees(th_e[n - 1]):.1f} deg  | error (aligned at start): rms {np.sqrt((d ** 2).mean()):.2f} deg, max {np.abs(d).max():.2f} deg")
    S = np.load(sp + f"/snap_syn{tag}_self.npy"); X = np.load(sp + f"/snap_syn{tag}_cross.npy"); C = S.shape[0]
    T = render_truth(truth, C); PT = prep(T, C)
    print("== 3) map vs truth scene (band-pass NCC, shift search +-20px) ==")
    for nm, M in (("self-selected", S), ("cross-validated", X)):
        v, dx, dy = ncc_shift(PT, prep(M, C)); print(f"  {nm:16s} NCC {v:.3f} at shift ({dx:+d},{dy:+d}) px")
    print("== 4) rod continuity (truth rod length = 320 px) ==")
    cy = cx = C // 2
    sl = (slice(cy - 330, cy + 330), slice(cx - 330, cx + 330))
    for nm, M in (("truth scene", T), ("self-selected", S), ("cross-validated", X)):
        L = rods_len(np.minimum(M[sl], np.percentile(M[sl][M[sl] > 0], 99.5))); print(f"  {nm:16s} {L} median {np.median(L):.0f} px")
    print("== 5) replica peaks in autocorrelation (height, dx, dy), axis-aligned peaks excluded ==")
    for nm, M in (("truth scene", T), ("self-selected", S), ("cross-validated", X)):
        print(f"  {nm:16s}", replica_peaks(M[cy - 300:cy + 300, cx - 300:cx + 300]))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "")
