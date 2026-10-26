"""wave_row_gating.png, wave_blink.png, worldmem_rtl.png  (real iverilog runs).
usage: fig_more.py <rg.vcd> <blink.vcd> <rtl_mem.txt> <outdir>"""
import sys
import numpy as np
from wavelib import *

rg_vcd, bl_vcd, mem_txt, out = sys.argv[1:5]
INK, TEAL, AMBER, MID, RED = "#1B2630", "#0E7C7B", "#E09F3E", "#5B6B76", "#B5483C"


def steps(ch, t0, t1):
    """-> xs, ys of a 1-bit signal over [t0,t1] (ps)"""
    pts = [(t0, value_at(ch, t0))] + [(t, v) for t, v in ch[1] if t0 < t <= t1]
    xs, ys = [], []
    for i, (t, v) in enumerate(pts):
        y = 1 if v == "1" else 0
        if i:
            xs.append(t); ys.append(ys[-1])
        xs.append(t); ys.append(y)
    xs.append(t1); ys.append(ys[-1])
    return np.array(xs), np.array(ys)


# ---------------- 1) row clock gating ----------------
V = read_vcd(rg_vcd); P = "tb_world_mem_ff_rg."
ck = V[P + "clk"]; we = V[P + "we"]; ad = V[P + "addr"]
t0, t1 = 300000, 420000          # ps (dump window), clock period 5 ns
cyc = lambda t: (t - t0) / 5000.0
rows = []
for r in range(64):
    ch = V[P + f"dut.ROW[{r}].gclk"]
    n = sum(1 for t, v in ch[1] if t0 <= t <= t1 and v == "1")
    rows.append((r, n))
active = [r for r, n in rows if n > 0]
idle = [r for r, n in rows if n == 0][:2]
show = active[:2] + idle[:1]
print("rows toggled in window:", active, "shown", show)
fig, axs = plt.subplots(3 + len(show), 1, figsize=(7.6, 3.9), sharex=True, dpi=140)
def dig(ax, ch, color, label):
    x, y = steps(ch, t0, t1); ax.plot((x - t0) / 5000.0, y, color=color, lw=2); ax.set_ylim(-0.3, 1.4)
    ax.set_yticks([]); ax.set_ylabel(label, rotation=0, ha="right", va="center", fontsize=11)
    for s in ("top", "right"): ax.spines[s].set_visible(False)
dig(axs[0], ck, INK, "clk")
dig(axs[1], we, TEAL, "we\n(쓰기)")
# addr row (bus)
ax = axs[2]; ax.set_ylim(0, 1); ax.set_yticks([]); ax.set_ylabel("쓰는 행\naddr[11:6]", rotation=0, ha="right", va="center", fontsize=11)
ev = [(t0, value_at(ad, t0))] + [(t, v) for t, v in ad[1] if t0 < t <= t1]
for i, (t, v) in enumerate(ev):
    te = ev[i + 1][0] if i + 1 < len(ev) else t1; iv = to_int(v)
    if iv is None: continue
    ax.add_patch(plt.Rectangle((cyc(t), 0.1), (te - t) / 5000.0, 0.8, fc="#DCEBEA", ec=MID, lw=0.8))
    if (te - t) / 5000.0 > 0.8: ax.text(cyc(t) + (te - t) / 10000.0, 0.5, str(iv >> 6), ha="center", va="center", fontsize=11)
for s in ("top", "right"): ax.spines[s].set_visible(False)
for k, r in enumerate(show):
    a = axs[3 + k]; ch = V[P + f"dut.ROW[{r}].gclk"]
    dig(a, ch, AMBER if r in active else MID, f"ROW[{r}].gclk")
    if r not in active: a.text(cyc(t0) + 0.3, 0.5, "클록 꺼짐 (쓰기 없음)", fontsize=10, color=MID, va="center")
axs[-1].set_xlim(0, cyc(t1)); axs[-1].set_xlabel("사이클 (tb_world_mem_ff_rg, 랜덤 쓰기)", fontsize=11); axs[-1].tick_params(labelsize=10)
fig.suptitle("행 단위 클록 게이팅: 쓰는 행의 게이트 클록만 토글", fontsize=12, x=0.01, ha="left")
fig.subplots_adjust(left=0.16, right=0.985, top=0.9, bottom=0.12, hspace=0.35)
fig.savefig(out + "/wave_row_gating.png"); plt.close(fig)

# ---------------- 2) blink ----------------
V = read_vcd(bl_vcd); P = "tb_blink."
arr = V[P + "arrival"]; on = V[P + "on_b"]
PER = 5000; T0 = 0; T1 = 3001 * PER + 1
fig, axs = plt.subplots(2, 1, figsize=(8, 2.8), sharex=True, dpi=140)
ax = axs[0]; ax.set_ylim(0, 1); ax.set_yticks([]); ax.set_ylabel("arrival ≠ 0\n(입력 도착)", rotation=0, ha="right", va="center", fontsize=11)
nz = [t for t, v in arr[1] if to_int(v)]
ax.vlines([t / PER for t in nz], 0.1, 0.9, color=AMBER, lw=0.9)
for s in ("top", "right"): ax.spines[s].set_visible(False)
ax = axs[1]
x, y = steps(on, T0, T1); ax.fill_between(x / PER, 0, y, step=None, color=TEAL, alpha=0.25); ax.plot(x / PER, y, color=TEAL, lw=2.2)
ax.set_ylim(-0.3, 1.5); ax.set_yticks([]); ax.set_ylabel("core_clk_on\n(코어 클록)", rotation=0, ha="right", va="center", fontsize=11)
for s in ("top", "right"): ax.spines[s].set_visible(False)
ax.set_xlim(0, 3000); ax.set_xlabel("사이클 (tb_blink: 프레임 = 입력 300사이클 + 유휴 1200사이클)", fontsize=11); ax.tick_params(labelsize=10)
offs = [t / PER for t, v in on[1] if v == "0" and t > 0]; ons = [t / PER for t, v in on[1] if v == "1" and t > 0]
print("on_b falls at", offs, "rises at", ons)
for xo in offs[:2]: ax.annotate("입력 없음 511사이클 → 클록 차단", (xo, 0.0), (xo + 60, 0.62), fontsize=10, color=INK, arrowprops=dict(arrowstyle="->", color=INK))
fig.suptitle("Blink: 입력이 끊기면 코어 클록을 끄고, 새 입력에 다시 켠다", fontsize=12, x=0.01, ha="left")
fig.subplots_adjust(left=0.16, right=0.985, top=0.86, bottom=0.2, hspace=0.25)
fig.savefig(out + "/wave_blink.png"); plt.close(fig)

# ---------------- 3) RTL world memory image ----------------
w = np.zeros(4096, int); p = np.zeros(4096, int)
for line in open(mem_txt):
    i, a, b = map(int, line.split()); w[i] = a; p[i] = b
img = np.zeros((64, 64, 3)) + 0.93
for i in range(4096):
    if w[i]:
        img[i // 64, i % 64] = (0.055, 0.486, 0.482) if p[i] else (0.878, 0.624, 0.243)
print("filled", int(w.sum()))
fig, ax = plt.subplots(1, 1, figsize=(5.2, 5.2), dpi=140)
ax.imshow(img, interpolation="nearest"); ax.set_xticks([0, 16, 32, 48, 63]); ax.set_yticks([0, 16, 32, 48, 63]); ax.tick_params(labelsize=12)
ax.set_xlabel("X", fontsize=13); ax.set_ylabel("Y", fontsize=13)
ax.set_title(f"RTL이 쓴 월드 메모리 (64×64, 채워진 칸 {int(w.sum())}/4096)", fontsize=13)
from matplotlib.patches import Patch
ax.legend(handles=[Patch(fc=(0.055, 0.486, 0.482), label="극성 1"), Patch(fc=(0.878, 0.624, 0.243), label="극성 0"), Patch(fc=(0.93, 0.93, 0.93), label="비어 있음")], loc="lower left", fontsize=11)
fig.tight_layout(); fig.savefig(out + "/worldmem_rtl.png"); plt.close(fig)
print("done")
