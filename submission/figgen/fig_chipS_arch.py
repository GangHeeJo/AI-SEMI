import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch, Rectangle, Circle, Arc, Polygon

plt.rcParams['font.family'] = 'Malgun Gothic'
plt.rcParams['axes.unicode_minus'] = False

INK = '#22252B'; MUTE = '#7A808C'
BLUE = '#1F5FA8'; BLUE_L = '#CFE0F3'; BLUE_P = '#F3F7FC'
ORG = '#B8561A'; ORG_L = '#F3D3BA'; ORG_P = '#FDF6EF'
GRN = '#2F6E57'; GRN_L = '#CFE6DA'; GRN_P = '#F2F8F5'

W, H = 13.2, 6.55
fig, ax = plt.subplots(figsize=(W, H), facecolor='white')
ax.set_xlim(0, W); ax.set_ylim(0, H); ax.axis('off')


def panel(x, y, w, h, label, fc, ec):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle='round,pad=0.0,rounding_size=0.2', fc=fc, ec=ec, lw=1.6, ls=(0, (6, 3))))
    tw = 0.24 * len(label) + 0.55
    ax.add_patch(FancyBboxPatch((x + 0.28, y + h - 0.22), tw, 0.44, boxstyle='round,pad=0.0,rounding_size=0.1', fc=ec, ec=ec))
    ax.text(x + 0.28 + tw / 2, y + h, label, ha='center', va='center', color='white', fontsize=12.5, fontweight='bold')


def block(x, y, w, h, name, sub, line, ec, name_fs=14.5, fs=12.5):
    ax.add_patch(FancyBboxPatch((x + 0.05, y - 0.06), w, h, boxstyle='round,pad=0.0,rounding_size=0.14', fc='#00000018', ec='none'))
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle='round,pad=0.0,rounding_size=0.14', fc='white', ec=ec, lw=2.2))
    ax.text(x + w / 2, y + h - 0.3, name, ha='center', va='center', fontsize=name_fs, fontweight='bold', color=ec)
    ax.text(x + w / 2, y + h - 0.6, sub, ha='center', va='center', fontsize=9.3, color=MUTE)
    ax.text(x + w / 2, y + h - 0.98, line, ha='center', va='center', fontsize=fs, color=INK, linespacing=1.4)


def arrow(p1, p2, color=INK, lw=3.4, ms=26):
    ax.add_patch(FancyArrowPatch(p1, p2, arrowstyle='-|>', mutation_scale=ms, color=color, lw=lw, shrinkA=0, shrinkB=0,
                                 capstyle='round', joinstyle='round'))


def poly(pts, color, lw=3.4):
    xs, ys = zip(*pts)
    ax.plot(xs, ys, color=color, lw=lw, solid_capstyle='round', solid_joinstyle='round')


def tag(x, y, text, color, fs=11):
    ax.text(x, y, text, ha='center', va='center', fontsize=fs, color=color, fontweight='bold', zorder=7,
            bbox=dict(boxstyle='round,pad=0.32,rounding_size=0.7', fc='white', ec=color, lw=1.4))


def badge(x, y, n, color):
    ax.add_patch(Circle((x, y), 0.2, fc=color, ec='white', lw=2, zorder=8))
    ax.text(x, y, str(n), ha='center', va='center', color='white', fontsize=12, fontweight='bold', zorder=9)


# ---------- 아이콘 ----------
def icon_bits(cx, cy):        # 워드 → 비트 칸
    pat = [1, 0, 1, 1, 0, 1, 0, 1]
    for i, v in enumerate(pat):
        ax.add_patch(Rectangle((cx - 0.8 + i * 0.2, cy - 0.09), 0.16, 0.18, fc=BLUE if v else BLUE_L, ec=BLUE, lw=0.8))


def icon_rotate(cx, cy):      # 회전 화살표 (반시계)
    r = 0.27
    ax.add_patch(Arc((cx, cy), 2 * r, 2 * r, theta1=40, theta2=325, color=BLUE, lw=3))
    t = np.radians(325)
    ex, ey = cx + r * np.cos(t), cy + r * np.sin(t)
    tx, ty = -np.sin(t), np.cos(t)           # 진행 방향(반시계 접선)
    nx, ny = np.cos(t), np.sin(t)
    tip = (ex + tx * 0.2, ey + ty * 0.2)
    ax.add_patch(Polygon([tip, (ex + nx * 0.12, ey + ny * 0.12), (ex - nx * 0.12, ey - ny * 0.12)], fc=BLUE, ec=BLUE))
    ax.add_patch(Circle((cx, cy), 0.05, fc=BLUE, ec=BLUE))


def icon_merge(cx, cy):       # 여러 줄 → 한 줄
    for k, dy in enumerate([-0.2, 0, 0.2]):
        ax.plot([cx - 0.5, cx - 0.1], [cy + dy, cy], color=BLUE, lw=2.2, solid_capstyle='round')
    arrow((cx - 0.1, cy), (cx + 0.5, cy), color=BLUE, lw=2.6, ms=14)


def icon_bars(cx, cy):        # 카운터 막대
    for k, hh in enumerate([0.16, 0.3, 0.46]):
        ax.add_patch(Rectangle((cx - 0.3 + k * 0.22, cy - 0.25), 0.15, hh, fc=BLUE, ec=BLUE))


def icon_grid(cx, cy):        # 메모리 뱅크
    for i in range(9):
        for j in range(2):
            lit = (i == 3 and j == 0)
            ax.add_patch(Rectangle((cx - 1.2 + i * 0.27, cy - 0.17 + j * 0.2), 0.22, 0.15, fc=GRN if lit else GRN_L, ec=GRN, lw=0.8))


def icon_dots(cx, cy):        # 픽셀 스트림
    for i in range(7):
        ax.add_patch(Circle((cx - 0.7 + i * 0.23, cy + (0.08 if i % 2 else -0.08)), 0.065, fc=ORG, ec=ORG))


def icon_planes(cx, cy):      # 1비트 지도 3장
    for k, c in enumerate(['#FBEEE3', '#F6DCC6', ORG_L]):
        ax.add_patch(Rectangle((cx - 0.55 + k * 0.17, cy - 0.2 + k * 0.1), 0.55, 0.32, fc=c, ec=ORG, lw=1.1))
    for k in range(5):
        ax.add_patch(Rectangle((cx - 0.3 + k * 0.11 + 0.34, cy - 0.04 + 0.2), 0.07, 0.07, fc=ORG, ec=ORG))


def icon_wave(cx, cy):        # 사인파
    t = np.linspace(0, 2 * np.pi, 80)
    ax.plot(cx - 0.8 + t * 0.25, cy + 0.2 * np.sin(t), color=ORG, lw=2.6)
    ax.plot(cx - 0.8 + t * 0.25, cy + 0.2 * np.cos(t), color=ORG, lw=2.6, alpha=0.45)


# ---------- 제목 배너 ----------
ax.add_patch(FancyBboxPatch((0.15, H - 0.62), W - 0.3, 0.5, boxstyle='round,pad=0.0,rounding_size=0.1', fc=INK, ec=INK))
ax.text(0.5, H - 0.37, '칩 S 내부 구조와 동작 흐름', color='white', fontsize=15.5, fontweight='bold', va='center')
ax.text(W - 0.5, H - 0.37, '번호 순서로 동작', color='#D6D9DE', fontsize=12, va='center', ha='right')

# ---------- 패널 ----------
TY, TH = 3.1, 2.45
panel(0.15, TY, 2.65, TH, '입력', BLUE_P, BLUE)
panel(3.0, TY, 6.05, TH, '좌표 변환 · 쓰기', BLUE_P, BLUE)
panel(9.25, TY, 3.8, TH, '월드 메모리', GRN_P, GRN)
panel(3.0, 0.2, 10.05, 2.5, '자세 추정', ORG_P, ORG)

BY, BH = 3.25, 1.9
block(0.4, BY, 2.15, BH, '디코더', 'aer_decoder', '센서 워드를\n픽셀 주소로', BLUE)
icon_bits(1.475, BY + 0.28)
block(3.2, BY, 2.35, BH, '좌표 변환', 'xf_b8', '회전을 되돌린\n월드 좌표', BLUE)
icon_rotate(4.375, BY + 0.3)
block(5.85, BY, 1.6, BH, '직렬화', 'pix_serializer', '한 줄로 정렬', BLUE, name_fs=14, fs=12)
icon_merge(6.65, BY + 0.3)
block(7.7, BY, 1.15, BH, '라이터', 'world_writer', '셀 카운터\n올림', BLUE, name_fs=13.5, fs=11.5)
ax.texts[-2].set_fontsize(8.2)
icon_bars(8.275, BY + 0.38)
block(9.45, BY, 3.4, BH, '월드 메모리', 'world_mem', '쓰는 행만 클록 ON', GRN)
icon_grid(11.15, BY + 0.38)

EY, EH = 0.38, 1.85
block(3.2, EY, 2.2, EH, '픽셀 공급', 'est_tok_expand', '같은 픽셀을\n추정기에도', ORG)
icon_dots(4.3, EY + 0.28)
block(5.85, EY, 3.7, EH, '자세 추정기', 'est_core', '1비트 지도로 회전각을 구한다', ORG, name_fs=15)
icon_planes(7.75, EY + 0.33)
block(9.95, EY, 2.9, EH, 'CORDIC', 'est_cordic', '각도 → cos · sin', ORG)
icon_wave(11.4, EY + 0.32)

# ---------- 화살표 ----------
my = BY + BH / 2 + 0.1
arrow((2.55, my), (3.2, my))
arrow((5.55, my), (5.85, my), ms=20)
arrow((7.45, my), (7.7, my), ms=18)
arrow((8.85, my), (9.45, my))
tag(2.87, my + 0.7, '픽셀', INK, 10.5)
tag(9.15, my + 0.7, '갱신', INK, 10.5)

ex = 1.47; ey = EY + EH / 2 + 0.1
poly([(ex, BY), (ex, ey)], ORG)
arrow((ex, ey), (3.2, ey), color=ORG)
tag(ex, 2.5, '픽셀', ORG, 10.5)

arrow((5.4, ey), (5.85, ey), color=ORG, ms=22)
arrow((9.55, ey), (9.95, ey), color=ORG, ms=22)
tag(9.75, ey + 0.65, '각도', ORG, 10.5)

ry = 2.9
poly([(12.4, EY + EH), (12.4, ry), (5.2, ry)], ORG)
arrow((5.2, ry), (5.2, BY), color=ORG)
tag(8.4, ry, '프레임마다 변환 값 전달', ORG, 12)

# ---------- 번호 ----------
badge(0.4, BY + BH, 1, BLUE); badge(ex, 1.6, 2, ORG); badge(5.85, EY + EH, 3, ORG)
badge(3.2, BY + BH, 4, BLUE); badge(7.7, BY + BH, 5, BLUE)

plt.tight_layout(pad=0.15)
plt.savefig('arch3.png', dpi=170, facecolor='white')
print('ok')
