"""Tiny VCD reader + waveform drawing (matplotlib). Shared by the fig_*.py scripts."""
import re
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import font_manager

for f in ("Malgun Gothic", "NanumGothic", "AppleGothic"):
    if any(f == x.name for x in font_manager.fontManager.ttflist):
        plt.rcParams["font.family"] = f
        break
plt.rcParams["axes.unicode_minus"] = False


def read_vcd(path, scope_filter=None):
    """-> (timescale_ps, {full_name: (width, [(t, 'bits')...])}); full_name = scope.name (no [msb:lsb])."""
    ts = 1; ids = {}; scope = []; vals = {}; t = 0; in_dump = False
    with open(path) as fh:
        toks = []
        for line in fh:
            toks = line.split()
            if not toks:
                continue
            if toks[0] == "$timescale":
                m = re.search(r"(\d+)\s*(fs|ps|ns|us)", " ".join(toks) + " " + next(fh))
                ts = int(m.group(1)) * {"fs": 1e-3, "ps": 1, "ns": 1e3, "us": 1e6}[m.group(2)]
            elif toks[0] == "$scope":
                scope.append(toks[2])
            elif toks[0] == "$upscope":
                scope.pop()
            elif toks[0] == "$var":
                name = ".".join(scope + [toks[4]])
                ids.setdefault(toks[3], []).append(name)
                vals[name] = (int(toks[2]), [])
            elif toks[0].startswith("#"):
                t = int(toks[0][1:]) * ts
            elif toks[0][0] in "bB":
                for n in ids.get(toks[1], []):
                    vals[n][1].append((t, toks[0][1:]))
            elif toks[0][0] in "01xzXZ" and len(toks[0]) > 1:
                for n in ids.get(toks[0][1:], []):
                    vals[n][1].append((t, toks[0][0]))
    return vals


def value_at(ch, t):
    last = None
    for tt, v in ch[1]:
        if tt > t:
            break
        last = v
    return last


def to_int(bits):
    if bits is None or any(c in bits for c in "xzXZ"):
        return None
    return int(bits, 2)


def draw_digital(ax, ch, t0, t1, y0, h, color, tscale):
    pts = [(t0, value_at(ch, t0))] + [(t, v) for t, v in ch[1] if t0 < t <= t1] + [(t1, None)]
    xs, ys = [], []
    cur = None
    for t, v in pts:
        if cur is not None:
            xs.append(t / tscale)
            ys.append(y0 + (h if cur == "1" else 0))
        if v is not None:
            xs.append(t / tscale)
            ys.append(y0 + (h if v == "1" else 0))
            cur = v
    ax.plot(xs, ys, color=color, lw=2, drawstyle="default")


def draw_bus(ax, ch, t0, t1, y0, h, color, tscale, fmt, min_label_w, zero_dim=True):
    """Bus as boxes; label when box is wide enough (in axis x-units)."""
    ev = [(t0, value_at(ch, t0))] + [(t, v) for t, v in ch[1] if t0 < t <= t1]
    for i, (t, v) in enumerate(ev):
        te = ev[i + 1][0] if i + 1 < len(ev) else t1
        x, w = t / tscale, (te - t) / tscale
        iv = to_int(v)
        dim = zero_dim and iv == 0
        ax.add_patch(plt.Rectangle((x, y0), w, h, fc="#EEF1F2" if dim else color, ec="#5B6B76", lw=0.8, alpha=1.0))
        if iv is not None and not dim and w >= min_label_w:
            ax.text(x + w / 2, y0 + h / 2, fmt(iv), ha="center", va="center", fontsize=13, color="#1B2630")
