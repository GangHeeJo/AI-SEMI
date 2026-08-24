import gdstk
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon
from matplotlib.collections import PatchCollection
import sys

gds_path = sys.argv[1]
out_path = sys.argv[2]

lib = gdstk.read_gds(gds_path)
top = lib.top_level()[0]

fig, ax = plt.subplots(figsize=(14, 14), facecolor="#0d0f14")
ax.set_facecolor("#0d0f14")

cmap = plt.get_cmap("tab20")
layers_seen = {}

polys = top.get_polygons(depth=None)
print(f"total polygons: {len(polys)}")

by_layer = {}
for p in polys:
    key = (p.layer, p.datatype)
    by_layer.setdefault(key, []).append(p.points)

for i, (key, pts_list) in enumerate(sorted(by_layer.items())):
    color = cmap(i % 20)
    patches = [Polygon(pts, closed=True) for pts in pts_list]
    pc = PatchCollection(patches, facecolor=color, edgecolor='none', alpha=0.75, linewidths=0)
    ax.add_collection(pc)
    print(f"layer {key}: {len(pts_list)} polygons, color {color}")

ax.autoscale_view()
ax.set_aspect('equal')
ax.axis('off')
plt.tight_layout()
plt.savefig(out_path, dpi=200, facecolor=fig.get_facecolor())
print(f"saved {out_path}")
