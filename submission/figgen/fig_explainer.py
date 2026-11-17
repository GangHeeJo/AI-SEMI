"""그림 생성: 쉬운 설명 PDF용 다이어그램 (submission/figs_explain/*.png)."""
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch, Circle, Rectangle
from matplotlib import font_manager as fm
from pathlib import Path

fm.fontManager.addfont("C:/Windows/Fonts/malgun.ttf"); fm.fontManager.addfont("C:/Windows/Fonts/malgunbd.ttf")
plt.rcParams["font.family"] = "Malgun Gothic"; plt.rcParams["axes.unicode_minus"] = False
OUT = Path(__file__).resolve().parent.parent / "figs_explain"; OUT.mkdir(exist_ok=True)
BLUE, ORANGE, GREEN, GRAY, DARK = "#1F5FA8", "#B85A1A", "#2E7255", "#6B7280", "#1F2937"
LBLUE, LORANGE, LGREEN = "#EAF1FA", "#FBEFE5", "#E8F3EC"


def canvas(w, h):
    fig = plt.figure(figsize=(w, h), dpi=200); ax = fig.add_axes([0, 0, 1, 1]); ax.set_xlim(0, w); ax.set_ylim(0, h); ax.axis("off")
    return fig, ax


def box(ax, x, y, w, h, title, sub="", color=BLUE, fill=LBLUE, fs=15, sfs=11.5):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.02,rounding_size=0.12", fc=fill, ec=color, lw=2.2))
    ax.text(x + w / 2, y + h * (0.64 if sub else 0.5), title, ha="center", va="center", fontsize=fs, fontweight="bold", color=color)
    if sub: ax.text(x + w / 2, y + h * 0.28, sub, ha="center", va="center", fontsize=sfs, color=DARK, linespacing=1.4)


def arrow(ax, p, q, color=DARK, lw=2.4, rad=0.0):
    ax.add_patch(FancyArrowPatch(p, q, arrowstyle="-|>", mutation_scale=20, color=color, lw=lw, connectionstyle=f"arc3,rad={rad}"))


# 1) 전체 흐름 ------------------------------------------------------------------
fig, ax = canvas(10, 3.0)
xs = [0.2, 2.75, 5.3, 7.85]; w = 1.95
items = [("① 이벤트 입력", "센서가 '바뀐 픽셀'만\n주소로 보낸다", BLUE, LBLUE), ("② 회전각 추정", "지금 카메라가\n얼마나 돌았는지 계산", ORANGE, LORANGE),
         ("③ 좌표 변환", "돌아간 만큼 되돌려\n월드 좌표로 옮김", BLUE, LBLUE), ("④ 월드 맵", "같은 자리 점을\n한 칸에 모아 쌓음", GREEN, LGREEN)]
for x, (t, s, c, f) in zip(xs, items): box(ax, x, 0.55, w, 1.7, t, s, c, f, fs=14, sfs=11)
for a, b in zip(xs[:-1], xs[1:]): arrow(ax, (a + w + 0.04, 1.4), (b - 0.04, 1.4))
ax.text(5, 0.22, "이 네 단계가 칩 한 개 안에서 이벤트마다 연속으로 돈다", ha="center", fontsize=12, color=GRAY)
fig.savefig(OUT / "flow4.png"); plt.close(fig)

# 2) 소용돌이 vs 월드 좌표 개념 -------------------------------------------------------
fig, ax = canvas(10, 3.4)
rng = np.random.default_rng(3)
pts = rng.uniform(-1, 1, (60, 2)) * np.array([1.4, 0.9])
for k, (cx, ttl) in enumerate([(1.8, "센서 좌표에 그냥 쌓으면"), (5.0, "각도만큼 되돌려 쌓으면")]):
    ax.text(cx, 3.05, ttl, ha="center", fontsize=13, fontweight="bold", color=DARK)
    for th in np.linspace(0, 1.4, 8):
        c, s = np.cos(th * (k == 0)), np.sin(th * (k == 0))
        q = pts @ np.array([[c, -s], [s, c]]).T
        ax.scatter(cx + q[:, 0] * 0.85, 1.4 + q[:, 1] * 0.85, s=5, color=(ORANGE if k == 0 else GREEN), alpha=0.35 if k == 0 else 0.5, lw=0)
    ax.add_patch(Rectangle((cx - 1.55, 0.3), 3.1, 2.4, fc="none", ec=GRAY, lw=1.2))
ax.text(1.8, 0.05, "번져서 소용돌이가 된다", ha="center", fontsize=11, color=GRAY); ax.text(5.0, 0.05, "같은 물체가 같은 자리에 모인다", ha="center", fontsize=11, color=GRAY)
box(ax, 6.75, 0.55, 3.0, 2.2, "핵심", "카메라가 도는 각도를\n알면 되돌릴 수 있다.\n그래서 각도 추정이\n가장 중요하다", ORANGE, LORANGE, fs=14, sfs=11.5)
fig.savefig(OUT / "swirl.png"); plt.close(fig)

# 3) 월드 메모리 구조 --------------------------------------------------------------
fig, ax = canvas(10, 3.7)
ax.text(0.15, 3.4, "월드 메모리: 8×8 픽셀 = 한 칸(셀), 칸마다 4비트 카운터", fontsize=13, fontweight="bold", color=DARK)
for i in range(8):
    for j in range(8):
        ax.add_patch(Rectangle((0.3 + i * 0.23, 0.8 + j * 0.23), 0.23, 0.23, fc=("#BFD4EE" if (i + j) % 2 else "#DCE8F6"), ec="white", lw=0.8))
ax.add_patch(Rectangle((0.3, 0.8), 1.84, 1.84, fc="none", ec=BLUE, lw=2.4))
ax.text(1.22, 0.45, "픽셀 64개 = 한 칸", ha="center", fontsize=11, color=DARK)
arrow(ax, (2.3, 1.72), (3.0, 1.72))
box(ax, 3.05, 1.05, 2.1, 1.35, "4비트 카운터", "이벤트가 올 때마다\n(확률적으로) +1", GREEN, LGREEN, fs=13.5, sfs=11)
ax.text(4.1, 0.55, "큰 수까지 4비트로 세기 위해\n로그 방식 사용", ha="center", fontsize=10.5, color=GRAY, linespacing=1.4)
arrow(ax, (5.3, 1.72), (6.0, 1.72))
for r in range(4):
    for c in range(4):
        on = (r == 1)
        ax.add_patch(FancyBboxPatch((6.15 + c * 0.88, 2.35 - r * 0.55), 0.78, 0.45, boxstyle="round,pad=0.01,rounding_size=0.06", fc=("#7FC49B" if on else "#E8F3EC"), ec=GREEN, lw=1.2))
ax.text(7.9, 3.0, "하드 메모리 뱅크 16개", ha="center", fontsize=12.5, fontweight="bold", color=GREEN)
ax.text(7.9, 0.1, "쓰는 행만 클록을 켠다(초록) → 전력 절감", ha="center", fontsize=11, color=DARK)
fig.savefig(OUT / "worldmem.png"); plt.close(fig)

# 4) 피벗(회전 중심) ------------------------------------------------------------------
fig, ax = canvas(10, 3.7)
ax.set_aspect("equal")
ax.text(0.15, 3.4, "카메라는 '봉' 끝에 달려 있어 센서 중심이 아니라 다른 점(피벗) 둘레로 돈다", fontsize=12.5, fontweight="bold", color=DARK)
Q = np.array([2.4, 1.2]); R = 1.25
for a0, al in [(160, 0.25), (110, 0.5), (60, 1.0)]:
    c = Q + R * np.array([np.cos(np.radians(a0)), np.sin(np.radians(a0))])
    ax.add_patch(Rectangle(c - np.array([0.5, 0.33]), 1.0, 0.66, angle=a0 - 90, rotation_point="center", fc=LBLUE, ec=BLUE, lw=1.8, alpha=al))
th = np.radians(np.linspace(55, 165, 30)); ax.plot(Q[0] + R * np.cos(th), Q[1] + R * np.sin(th), "--", color=GRAY, lw=1.3)
ax.add_patch(Circle(Q, 0.07, color=ORANGE)); ax.text(Q[0] + 0.12, Q[1] - 0.28, "피벗(회전 중심)", fontsize=11.5, color=ORANGE, fontweight="bold")
ax.text(2.4, 0.2, "센서 중심은 호를 그리며 움직인다", ha="center", fontsize=11, color=GRAY)
box(ax, 5.2, 0.55, 4.5, 2.3, "왜 중요한가", "피벗 위치를 칩 안에 상수로 박아 두면\n다른 날 찍은 영상에서는 어긋난다.\n(우리 실험: 각도 오차 0.67° → 61°)\n그래서 피벗을 데이터에서 직접 구한다", ORANGE, LORANGE, fs=14, sfs=11.5)
fig.savefig(OUT / "pivot.png"); plt.close(fig)

# 5) 자기보정 절차 --------------------------------------------------------------------
fig, ax = canvas(10, 2.7)
steps = [("1 처음 몇 구간", "회전각과 이동량을\n둘 다 자유롭게 추정"), ("2 직선 맞추기", "이동량이 각도로\n설명되는지 최소제곱"), ("3 판정", "설명력 r² ≥ 0.9 이면\n피벗 확정"), ("4 고정", "피벗을 고정하고\n회전각만 추정")]
xs = [0.15, 2.65, 5.15, 7.65]
for i, (x, (t, s)) in enumerate(zip(xs, steps)): box(ax, x, 0.45, 2.1, 1.6, t, s, ORANGE if i < 3 else GREEN, LORANGE if i < 3 else LGREEN, fs=13, sfs=10.5)
for a, b in zip(xs[:-1], xs[1:]): arrow(ax, (a + 2.14, 1.25), (b - 0.04, 1.25))
ax.text(5, 0.12, "설명력이 낮으면 이동량까지 계속 추정(안전장치)", ha="center", fontsize=10.5, color=GRAY)
fig.savefig(OUT / "selfcal.png"); plt.close(fig)

# 6) 검증 단계 ----------------------------------------------------------------------
fig, ax = canvas(10, 2.3)
st = [("RTL 설계", "회로를 코드로"), ("합성", "게이트로 변환"), ("배치배선", "칩 위에 배치"), ("signoff", "최종 시간 검사"), ("LEC", "설계와 같은지\n논리 비교"), ("게이트 시뮬", "실제 지연으로\n동작 확인")]
w = 1.35; gap = 0.28; x0 = 0.2
for i, (t, s) in enumerate(st):
    x = x0 + i * (w + gap); box(ax, x, 0.4, w, 1.4, t, s, BLUE, LBLUE, fs=12, sfs=9.8)
    if i < len(st) - 1: arrow(ax, (x + w + 0.02, 1.1), (x + w + gap - 0.02, 1.1), lw=2)
fig.savefig(OUT / "verify.png"); plt.close(fig)
print("done", sorted(p.name for p in OUT.glob("*.png")))
