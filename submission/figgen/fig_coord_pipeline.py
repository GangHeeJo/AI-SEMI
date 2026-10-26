"""wave_coord_pipeline.png from coord.vcd (tb_aer_tx16_coord_transform_v1_uzh_trace, real UZH trace). usage: fig_coord_pipeline.py coord.vcd out.png"""
import sys
from wavelib import *
import matplotlib.gridspec as gs

V = read_vcd(sys.argv[1]); P = "tb_aer_tx16_coord_transform_v1_uzh_trace."
g = lambda n: V[P + n]
PER, OFF = 10000, 6000          # ps: clk period, first-cycle drive time (rst released at 6 ns, arrival driven at 6 ns + 10 ns*cyc)
cyc = lambda t: (t - OFF) / PER
arr_nz = [t for t, v in g("arrival")[1] if to_int(v)]
first = min(arr_nz); assert abs(cyc(first) - round(cyc(first))) < 0.05
c_first = round(cyc(first)); print("first arrival in window at trace cycle", c_first)
T_END = 43000000
ZW = 16                          # zoom width in cycles
z0, z1 = OFF + (c_first - 1) * PER, OFF + (c_first - 1 + ZW) * PER

fig = plt.figure(figsize=(12, 7.2), dpi=140)
G = gs.GridSpec(2, 1, height_ratios=[1, 4.2], hspace=0.28)
# --- overview
ax = fig.add_subplot(G[0]); t0 = 41300000
ax.set_xlim(cyc(t0), cyc(T_END)); ax.set_ylim(-0.1, 2.3)
ax.set_yticks([0.5, 1.5]); ax.set_yticklabels(["world_we\n(메모리 쓰기)", "arrival≠0\n(이벤트 도착)"], fontsize=12)
draw_digital(ax, g("world_we"), t0, T_END, 0, 0.9, "#0E7C7B", PER)
ax.lines[-1].set_xdata((ax.lines[-1].get_xdata() * PER - OFF) / PER)
nz = [(t, to_int(v)) for t, v in g("arrival")[1] if t >= t0]
for t, v in nz:
    if v: ax.plot([cyc(t), cyc(t) + 1], [1.5, 1.5], color="#E09F3E", lw=6, solid_capstyle="butt")
ax.axvspan(cyc(z0), cyc(z1), color="#E09F3E", alpha=0.18)
ax.set_title("전체 구간 150사이클 (주황 영역을 아래에서 확대)", fontsize=14, loc="left")
ax.tick_params(labelsize=12)
# --- zoom
ax = fig.add_subplot(G[1]); ax.set_xlim(cyc(z0), cyc(z1)); ax.set_ylim(0, 8 * 1.0)
rows = ["clk", "arrival[15:0]", "theta_idx", "world_we", "world_addr {y,x}", "world_pol", "overrun"]
H, GAP = 0.62, 1.0
ys = {r: (len(rows) - 1 - i) * GAP + 0.25 for i, r in enumerate(rows)}
ax.set_ylim(0, len(rows) * GAP + 0.1)
ax.set_yticks([ys[r] + H / 2 for r in rows]); ax.set_yticklabels(["clk", "arrival\n(소스 16개 비트맵)", "theta_idx\n(회전각 번호)", "world_we", "world_addr\n{y,x}", "world_pol\n(극성)", "overrun"], fontsize=12)
# clk
ck = g("clk"); edges = [t for t, v in ck[1] if z0 <= t <= z1]
xs, yy = [], []
tt = z0; cur = value_at(ck, z0)
pts = [(z0, cur)] + [(t, v) for t, v in ck[1] if z0 < t <= z1]
for i, (t, v) in enumerate(pts):
    if i: xs.append(cyc(t)); yy.append(ys["clk"] + (H if pts[i - 1][1] == "1" else 0))
    xs.append(cyc(t)); yy.append(ys["clk"] + (H if v == "1" else 0))
xs.append(cyc(z1)); yy.append(yy[-1])
ax.plot(xs, yy, color="#1B2630", lw=1.6)
draw_bus(ax, g("arrival"), z0, z1, ys["arrival[15:0]"], H, "#F6D9A8", PER, lambda v: f"{v:04X}", 0.9)
draw_bus(ax, g("theta_idx"), z0, z1, ys["theta_idx"], H, "#DCEBEA", PER, lambda v: f"{v}", 0.5, zero_dim=False)
draw_digital(ax, g("world_we"), z0, z1, ys["world_we"], H, "#0E7C7B", PER)
draw_bus(ax, g("world_addr"), z0, z1, ys["world_addr {y,x}"], H, "#DCEBEA", PER, lambda v: f"{v >> 6},{v & 63}", 0.7, zero_dim=False)
draw_digital(ax, g("world_pol"), z0, z1, ys["world_pol"], H, "#B5483C", PER)
draw_bus(ax, g("overrun"), z0, z1, ys["overrun"], H, "#F2C4BE", PER, lambda v: f"{v:X}", 99)
# x axis in cycles (fix: digital/ bus use PER scale; convert to cycles)
for ln in ax.lines[1:]:
    ln.set_xdata((ln.get_xdata() * PER - OFF) / PER)
for p in ax.patches: p.set_x((p.get_x() * PER - OFF) / PER); p.set_width(p.get_width())
for tx in ax.texts: x, y = tx.get_position(); tx.set_position(((x * PER - OFF) / PER, y))
ax.set_xlabel("실제 UZH 이벤트 트레이스의 사이클 번호 (1 칸 = 1 clock)", fontsize=13); ax.tick_params(labelsize=12)
ax.xaxis.set_major_locator(matplotlib.ticker.MultipleLocator(2))
ax.grid(axis="x", color="#D5DCDF", lw=0.6); ax.set_axisbelow(True)
fig.suptitle("좌표 변환 파이프라인 시뮬레이션 파형 (iverilog, tb_aer_tx16_coord_transform_v1_uzh_trace)", fontsize=15, x=0.01, ha="left", y=0.985)
fig.subplots_adjust(left=0.14, right=0.985, top=0.9, bottom=0.08)
fig.savefig(sys.argv[2]); print("saved", sys.argv[2])
