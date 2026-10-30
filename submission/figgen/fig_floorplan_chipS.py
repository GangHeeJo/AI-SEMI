import re, sys
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle
plt.rcParams["font.family"] = "Malgun Gothic"
DIE = (5846000, 3883600); U = 2000.0; MW, MH = 604000, 603800
rows = [l.split() for l in open(sys.argv[1], encoding="utf-8")]
fig, ax = plt.subplots(figsize=(8.6, 5.7), dpi=200)
ax.add_patch(Rectangle((0, 0), DIE[0] / U, DIE[1] / U, fill=False, ec="#1D1D1F", lw=1.2))
cnt = {"est": 0, "world": 0}
for name, x, y, o in rows:
    est = "u_est_u_core/g_pl" in name
    cnt["est" if est else "world"] += 1
    ax.add_patch(Rectangle((int(x) / U, int(y) / U), MW / U, MH / U, fc="#CFE3F7" if est else "#0066CC", ec="#1D1D1F", lw=0.5, alpha=0.95))
ax.set_xlim(-40, DIE[0] / U + 40); ax.set_ylim(-40, DIE[1] / U + 40); ax.set_aspect("equal")
ax.set_xlabel("µm"); ax.set_ylabel("µm"); ax.tick_params(labelsize=8)
ax.legend(handles=[Rectangle((0, 0), 1, 1, fc="#CFE3F7", ec="#1D1D1F"), Rectangle((0, 0), 1, 1, fc="#0066CC", ec="#1D1D1F")],
          labels=[f"자세 추정기 평면 뱅크 {cnt['est']}개", f"월드 메모리 뱅크 {cnt['world']}개"], loc="upper right", fontsize=9, frameon=True)
ax.set_title("풀칩 배치 (2923×1942 µm, 8 kbit 하드매크로 46개)", fontsize=11)
plt.tight_layout(); plt.savefig(sys.argv[2]); print(cnt)
