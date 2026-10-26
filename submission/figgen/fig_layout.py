"""P&R 레이아웃(셀 배치도): GDS의 최상위 셀 인스턴스 경계상자를 종류별로 색칠. usage: fig_layout.py <in.gds> <out.png>"""
import sys
import gdstk
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import PatchCollection
from matplotlib.patches import Rectangle, Patch
from matplotlib import font_manager

for f in ("Malgun Gothic",):
    if any(f == x.name for x in font_manager.fontManager.ttflist):
        plt.rcParams["font.family"] = f

lib = gdstk.read_gds(sys.argv[1])
top = lib.top_level()[0]
print("top", top.name, "refs", len(top.references))
bbox_cache = {}
groups = {"ff": [], "icg": [], "logic": [], "fill": []}
for r in top.references:
    n = r.cell.name if hasattr(r.cell, "name") else str(r.cell)
    if n not in bbox_cache:
        c = r.cell if not isinstance(r.cell, str) else None
        bbox_cache[n] = c.bounding_box() if c is not None else None
    bb = bbox_cache[n]
    if bb is None:
        continue
    (x0, y0), (x1, y1) = bb
    ox, oy = r.origin
    rect = Rectangle((ox + x0, oy + y0), x1 - x0, y1 - y0)
    u = n.upper()
    if u.startswith("FILL") or u.startswith("TAP") or "ANTENNA" in u:
        groups["fill"].append(rect)
    elif u.startswith("TLATNCA") or u.startswith("TLATNTSCA"):
        groups["icg"].append(rect)
    elif u.startswith("DFF") or u.startswith("SDFF") or u.startswith("TLAT"):
        groups["ff"].append(rect)
    else:
        groups["logic"].append(rect)
print({k: len(v) for k, v in groups.items()})
fig, ax = plt.subplots(figsize=(7, 6.3), dpi=140)
ax.set_facecolor("#10181E")
for k, col, a in (("fill", "#2A3A44", 1.0), ("logic", "#7FA8B5", 0.9), ("ff", "#E09F3E", 0.95), ("icg", "#E0443A", 1.0)):
    if groups[k]:
        ax.add_collection(PatchCollection(groups[k], facecolor=col, edgecolor="none", alpha=a))
allr = [r for g in groups.values() for r in g]
xs = [r.get_x() for r in allr] + [r.get_x() + r.get_width() for r in allr]
ys = [r.get_y() for r in allr] + [r.get_y() + r.get_height() for r in allr]
ax.set_xlim(min(xs), max(xs)); ax.set_ylim(min(ys), max(ys)); ax.set_aspect("equal")
ax.tick_params(labelsize=12)
ax.set_xlabel("µm"); ax.set_ylabel("µm")
ax.legend(handles=[Patch(fc="#E09F3E", label='플립플롭·래치'), Patch(fc="#E0443A", label=f"클록 게이트 ICG ({len(groups['icg'])})"), Patch(fc="#7FA8B5", label='조합 논리·기타'), Patch(fc="#2A3A44", label="필러·탭")], loc="upper right", fontsize=13, facecolor="#FFFFFF")
fig.tight_layout(); fig.savefig(sys.argv[2]); print("saved")
