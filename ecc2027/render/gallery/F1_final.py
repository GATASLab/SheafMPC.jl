"""F1_final: Fig. 1 overview, laid out from measured ink.

Four panels: (a) fleet and formation graph, (b) teams, (c) team program, (d) members copy the input. Every
placement is computed from the rendered ink of each piece (drawings and text are rasterised alone at high
resolution first), so titles sit on their drawing's ink centre, the card has equal padding, and every arrow end
keeps a fixed clearance. F1N_STYLE=card draws the card around (b) and (c); F1N_STYLE=plain draws no card.

    OUT_DIR=<dir> F1N_STYLE=card python3 render/gallery/F1_final.py

Also writes <OUT_DIR>/F1F_<style>_layout.json and two auxiliary masks for panel (c) labels (used by the
measurement script).
"""
import json
import os

import numpy as np
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.backends.backend_agg import FigureCanvasAgg
from matplotlib.collections import LineCollection
from matplotlib.figure import Figure
from matplotlib.lines import Line2D
from matplotlib.patches import FancyBboxPatch, Polygon, PathPatch
from matplotlib.path import Path
from scipy.spatial import ConvexHull

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.environ.get("OUT_DIR", os.path.join(ROOT, "figures"))
KEY = os.environ.get("OV_KEY", "n56_s4")
STY = os.environ.get("F1N_STYLE", "card")
TEXTW = 7.0
H0 = 3.0                       # working canvas height; the saved figure is cropped to the ink
SX = 1.15                      # schematic: widen the planted layout a little
plt.rcParams.update({
    "font.family": "serif", "font.serif": ["TeX Gyre Termes", "Nimbus Roman", "Times New Roman"],
    "mathtext.fontset": "cm", "font.size": 8, "axes.linewidth": 0.5, "pdf.fonttype": 42, "savefig.dpi": 300,
})
PALETTE = ["#0072B2", "#E69F00", "#009E73", "#D55E00", "#CC79A7", "#5E4FA2"]
BOLD = STY == "bold"           # committed look: dark (a), full size markers, ring nodes in (c)
NODE_A = "#3d3d3d" if BOLD else "#6E6E6E"   # node fill in (a)
SEC = "#555555"                # every piece of secondary text
ARROW = os.environ.get("F1_ARROW", "#3f3f3f")
LOOPC = os.environ.get("F1_LOOP", "#8c8c8c")
CARD_EC, CARD_LW, CARD_R = os.environ.get("F1_CARD", "#A9B0B8" if BOLD else "#BFC5CD"), float(os.environ.get("F1_CARDLW", "0.6")), 2.0 / 72
MS = {"drone": ("o", 16.2), "car": ("s", 13.0)}   # 10% smaller (linear) than before, same in every panel
if BOLD:
    _ms = float(os.environ.get("F1_MSCALE", "0.7"))   # marker area scale: less overlap between vehicles
    MS = {"drone": ("o", 20.0 * _ms), "car": ("s", 16.0 * _ms)}
TFS, SFS = float(os.environ.get("F1_TFS", "8.5")), float(os.environ.get("F1_SFS", "7.5"))   # title, secondary sizes
MDPI = 600                     # measurement resolution

# layout rules (inches)
PAD = 0.08                     # card padding to outermost ink
CARD_GAP = 0.04                # arrow end to card
CL = 0.17                      # arrow end to drawing ink (minimum)
INSET = 0.02 if BOLD else 0.03                   # (b), (c) drawings sit this far inside their title block
AA = 0.005                     # antialias fringe of the card border at 200 dpi
HEAD_L, HEAD_W = 0.062, 0.028  # arrow head length, half width
MARG = 0.02                    # crop margin around the ink
BW = CARD_LW / 72.0            # card border width


# ---------------------------------------------------------------------------------------------- measurement
def raster_ink(fig, dpi=MDPI, thr=250):
    """Ink bbox (x0, y0, x1, y1) in inches, y up, of everything drawn on fig."""
    fig.set_dpi(dpi)
    cv = FigureCanvasAgg(fig)
    cv.draw()
    a = np.asarray(cv.buffer_rgba())[:, :, :3]
    m = a.min(2) < thr
    ys, xs = np.nonzero(m)
    hpx = a.shape[0]
    return np.array([xs.min() / dpi, (hpx - ys.max() - 1) / dpi, (xs.max() + 1) / dpi, (hpx - ys.min()) / dpi])


_TCACHE = {}


def text_ink(s, **kw):
    """Ink of a text relative to its anchor, inches: (l, b, r, t)."""
    key = (s, tuple(sorted(kw.items())))
    if key not in _TCACHE:
        f = Figure(figsize=(8, 1.6), facecolor="white")
        f.text(0.5, 0.5, s, **kw)
        bb = raster_ink(f)
        _TCACHE[key] = bb - np.array([4.0, 0.8, 4.0, 0.8])
    return _TCACHE[key]


# ---------------------------------------------------------------------------------------------- data
with open(os.path.join(ROOT, "results", "overview_fleet.json")) as f:
    D = json.load(f)[KEY]
X, Y = SX * np.array(D["x"]), np.array(D["y"])
# move the purple team (team 6) up and to the left, where the layout has room, so it does not sit on green and pink
_pm = np.array(D["teams"]) == 6
_sh = [float(v) for v in os.environ.get("F1_PSHIFT", "-1.0,1.4").split(",")]
X[_pm] += _sh[0]; Y[_pm] += _sh[1]
_dmin = float(os.environ.get("F1_RELAX", "0.45"))   # nudge stacked vehicles apart (data units), all panels alike
if _dmin > 0:
    for _ in range(200):
        moved = False
        for a_ in range(len(X)):
            for b_ in range(a_ + 1, len(X)):
                dx, dy = X[b_] - X[a_], Y[b_] - Y[a_]
                d = np.hypot(dx, dy)
                if d < _dmin:
                    if d < 1e-9:
                        dx, dy, d = 1.0, 0.0, 1.0
                    s = (_dmin - d) / 2 / d
                    X[a_] -= s * dx; Y[a_] -= s * dy; X[b_] += s * dx; Y[b_] += s * dy
                    moved = True
        if not moved:
            break
lab, E, W, kinds = D["teams"], D["edges"], D["w"], D["kind"]
n, nt = len(lab), max(lab)
tc = PALETTE[:nt]
vc = [tc[l - 1] for l in lab]
mem = [[k for k in range(n) if lab[k] == t + 1] for t in range(nt)]
cen = np.array([[X[m].mean(), Y[m].mean()] for m in mem])
segs = [[(X[i - 1], Y[i - 1]), (X[j - 1], Y[j - 1])] for i, j in E]
inner = [lab[i - 1] == lab[j - 1] for i, j in E]
span = max(np.ptp(X), np.ptp(Y))
rng = np.random.default_rng(7)
ang = np.deg2rad(18) + rng.uniform(-0.25, 0.25, nt)
Ld = 0.12 * span * rng.uniform(0.85, 1.1, nt)
disp = np.c_[np.cos(ang), np.sin(ang)] * Ld[:, None]
tl = np.array(lab) - 1
Xe, Ye = X + disp[tl, 0], Y + disp[tl, 1]
perp = np.c_[-disp[:, 1], disp[:, 0]]
S = np.linspace(0, 1, 24)
curves = [np.c_[X[k] + S * disp[tl[k], 0] + 0.45 * S * (1 - S) * perp[tl[k], 0],
                Y[k] + S * disp[tl[k], 1] + 0.45 * S * (1 - S) * perp[tl[k], 1]] for k in range(n)]
DSTYLE = os.environ.get("F1_DSTYLE", "vA")
if DSTYLE == "vA":   # panel (d) as in variant A (F1v2a): each team fans out along its own gently curved path
    _ang = np.deg2rad(float(os.environ.get("F1_DFAN", "0.5")) * np.array([30, 12, -28, 34, 20, -6], float)[:nt])
    disp = 0.26 * span * np.c_[np.cos(_ang), np.sin(_ang)]
    perp = np.c_[-disp[:, 1], disp[:, 0]]
    S = np.linspace(0, 1, 30)
    _bend = np.array([0.30 * (1 if t % 2 else -1) for t in range(nt)])
    curves = [np.c_[X[k] + S * disp[tl[k], 0] + _bend[tl[k]] * S * (1 - S) * perp[tl[k], 0],
                    Y[k] + S * disp[tl[k], 1] + _bend[tl[k]] * S * (1 - S) * perp[tl[k], 1]] for k in range(n)]
    Xe, Ye = X + disp[tl, 0], Y + disp[tl, 1]


def _tint(hexc, a):
    c = np.array(matplotlib.colors.to_rgb(hexc))
    return tuple(a * c + (1 - a))
Wq = {}
for (i, j), w in zip(E, W):
    a, b = sorted((lab[i - 1] - 1, lab[j - 1] - 1))
    if a != b:
        Wq[(a, b)] = Wq.get((a, b), 0.0) + w
wmax = max(Wq.values())
team_kind = [kinds[m[0]] for m in mem]

# panel (c) node style
CN = {"drone": ("o", 30.0), "car": ("s", 22.0)}
C_LFS = 7.0
C_NUDGED = 0.0
RING_LW = 1.4
if BOLD:
    CN = {"drone": ("o", 125.0), "car": ("s", 100.0)}
    C_LFS = float(os.environ.get("F1_CLFS", "7.5"))
CSTRETCH = 1.35


def node_r(kind):
    """Outer radius of a (c) node in inches (half diagonal for squares)."""
    mk, s = CN[kind]
    side = np.sqrt(s) / 72.0
    return side / 2 * (np.sqrt(2) if mk == "s" else 1.0) + (RING_LW / 2 / 72 if BOLD else 0.0)


def vehicles(ax, XX, YY, colours, z=4, ec="white", lw=0.35, alpha=1.0):
    for kind, (mk, ms) in MS.items():
        idx = [k for k in range(len(XX)) if kinds[k] == kind]
        ax.scatter(XX[idx], YY[idx], c=[colours[k] for k in idx], marker=mk, s=ms, linewidths=lw,
                   edgecolors=ec, zorder=z, alpha=alpha, clip_on=False)


# ---------------------------------------------------------------------------------------------- panel (c) geometry
def c_layout(sc):
    """Node positions (data units) for (c), nudged so nodes keep >= 0.06 in clear, and label placements."""
    P = cen.copy()
    if BOLD:
        return c_layout_ring(sc)
    P[:, 1] = P[:, 1].mean() + CSTRETCH * (P[:, 1] - P[:, 1].mean())   # schematic: open the layout vertically
    P = P / sc                                           # inches
    rr = np.array([node_r(team_kind[t]) for t in range(nt)])
    for _ in range(400):
        moved = False
        for a in range(nt):
            for b in range(a + 1, nt):
                d = P[b] - P[a]
                dist = np.linalg.norm(d)
                need = rr[a] + rr[b] + 0.10
                if dist < need:
                    u = d / dist
                    P[a] -= u * (need - dist) / 2 * 1.02
                    P[b] += u * (need - dist) / 2 * 1.02
                    moved = True
        if not moved:
            break
    # labels: candidate directions around each node, rejected if they touch a node, an edge or a label
    edges = list(Wq.keys())
    lws = {e: (0.35 + 0.9 * Wq[e] / wmax) / 72.0 for e in edges}
    placed = {}

    def seg_rect_dist(p, q, rect):
        # min distance from segment pq to axis aligned rect (x0, y0, x1, y1), by dense sampling
        ts = np.linspace(0, 1, 200)
        pts = p[None] + ts[:, None] * (q - p)[None]
        dx = np.maximum.reduce([rect[0] - pts[:, 0], np.zeros(len(ts)), pts[:, 0] - rect[2]])
        dy = np.maximum.reduce([rect[1] - pts[:, 1], np.zeros(len(ts)), pts[:, 1] - rect[3]])
        return np.sqrt(dx ** 2 + dy ** 2).min()

    def rect_gap(r1, r2):
        dx = max(r1[0] - r2[2], r2[0] - r1[2], 0)
        dy = max(r1[1] - r2[3], r2[1] - r1[3], 0)
        return np.hypot(dx, dy)

    order = sorted(range(nt), key=lambda t: -sum(1 for e in edges if t in e))
    for t in order:
        ink = text_ink(str(len(mem[t])), fontsize=C_LFS, ha="center", va="center")
        hw, hh = (ink[2] - ink[0]) / 2, (ink[3] - ink[1]) / 2
        cx0, cy0 = (ink[0] + ink[2]) / 2, (ink[1] + ink[3]) / 2
        inc = [P[b if a == t else a] - P[t] for (a, b) in edges if t in (a, b)]
        inc = [v / np.linalg.norm(v) for v in inc]
        best = None
        for gap in (0.03, 0.045, 0.06, 0.08):
            for th in np.deg2rad(np.arange(0, 360, 7.5)):
                u = np.array([np.cos(th), np.sin(th)])
                # distance from node centre to a rect of half size (hw, hh) along u, plus the gap
                tt = min(hw / abs(u[0]) if abs(u[0]) > 1e-9 else 1e9, hh / abs(u[1]) if abs(u[1]) > 1e-9 else 1e9)
                c = P[t] + u * (rr[t] + gap + tt)
                rect = (c[0] - hw, c[1] - hh, c[0] + hw, c[1] + hh)
                ok = True
                for s in range(nt):
                    cs = P[s]
                    dx = max(rect[0] - cs[0], 0, cs[0] - rect[2]); dy = max(rect[1] - cs[1], 0, cs[1] - rect[3])
                    if np.hypot(dx, dy) < rr[s] + 0.025:
                        ok = False; break
                if not ok:
                    continue
                for e in edges:
                    if seg_rect_dist(P[e[0]], P[e[1]], rect) < lws[e] / 2 + 0.025:
                        ok = False; break
                if not ok:
                    continue
                if any(rect_gap(rect, r2) < 0.03 for r2 in placed.values()):
                    continue
                angsep = min([np.arccos(np.clip(u @ v, -1, 1)) for v in inc] or [np.pi])
                score = angsep - 4.0 * gap + 0.15 * (u[1] > 0.3)   # mild preference for labels above
                if best is None or score > best[0]:
                    best = (score, rect, c)
            if best is not None:
                break
        assert best is not None, "no label slot for team %d" % t
        placed[t] = best[1]
    labels = {t: ((r[0] + r[2]) / 2, (r[1] + r[3]) / 2) for t, r in placed.items()}
    # anchors so that the label ink centre lands on the chosen centre
    anchors = {}
    for t, (x, y) in labels.items():
        ink = text_ink(str(len(mem[t])), fontsize=C_LFS, ha="center", va="center")
        anchors[t] = (x - (ink[0] + ink[2]) / 2, y - (ink[1] + ink[3]) / 2)
    return P * sc, {t: (a[0] * sc, a[1] * sc) for t, a in anchors.items()}, \
        {t: [v * sc for v in r] for t, r in placed.items()}, lws


def c_layout_ring(sc):
    """Bold style: ring nodes at the team centroids (nudged to keep 0.04 in clear), size number centred inside."""
    P = cen.copy() / sc
    rr = np.array([node_r(team_kind[t]) for t in range(nt)])
    for _ in range(400):
        moved = False
        for a in range(nt):
            for b in range(a + 1, nt):
                d = P[b] - P[a]
                dist = np.linalg.norm(d)
                need = rr[a] + rr[b] + 0.045     # only acts if the centroids are closer than this
                if dist < need:
                    u = d / dist
                    P[a] -= u * (need - dist) / 2 * 1.02
                    P[b] += u * (need - dist) / 2 * 1.02
                    moved = True
        if not moved:
            break
    global C_NUDGED
    C_NUDGED = float(np.abs(P - cen / sc).max())
    lws = {e: (0.6 + 1.9 * Wq[e] / wmax) / 72.0 for e in Wq}
    anchors, rects = {}, {}
    for t in range(nt):
        ink = text_ink(str(len(mem[t])), fontsize=C_LFS, ha="center", va="center")
        anchors[t] = (P[t][0] - (ink[0] + ink[2]) / 2, P[t][1] - (ink[1] + ink[3]) / 2)
        hw, hh = (ink[2] - ink[0]) / 2, (ink[3] - ink[1]) / 2
        rects[t] = [P[t][0] - hw, P[t][1] - hh, P[t][0] + hw, P[t][1] + hh]
    return P * sc, {t: (a[0] * sc, a[1] * sc) for t, a in anchors.items()}, \
        {t: [v * sc for v in r] for t, r in rects.items()}, lws


# ---------------------------------------------------------------------------------------------- drawings
def draw_panel(ax, k, sc, cgeo=None, labels=True, only_labels=False):
    if k == 0:
        ax.add_collection(LineCollection(segs, colors="#c4c4c4" if BOLD else "#c8c8c8", linewidths=0.4, zorder=1))
        vehicles(ax, X, Y, [NODE_A] * n)
    elif k == 1:
        for t in range(nt):
            Pm = np.c_[X[mem[t]], Y[mem[t]]]
            hull = Pm[ConvexHull(Pm).vertices]
            cc = hull.mean(0)
            ax.add_patch(Polygon(cc + 1.12 * (hull - cc), closed=True, facecolor=tc[t], alpha=0.09,
                                 edgecolor="none", zorder=0, clip_on=False))
        ax.add_collection(LineCollection([s for s, a in zip(segs, inner) if not a], colors="#e0e0e0" if BOLD else "#dcdcdc",
                                         linewidths=0.35, zorder=1))
        ax.add_collection(LineCollection([s for s, a in zip(segs, inner) if a],
                                         colors=[vc[i - 1] for (i, j), a in zip(E, inner) if a],
                                         linewidths=0.55, zorder=2))
        vehicles(ax, X, Y, vc)
    elif k == 2:
        Pn, anchors, rects, lws = cgeo
        if BOLD:
            if not only_labels:
                for t in range(nt):
                    Pm = np.c_[X[mem[t]], Y[mem[t]]]
                    hull = Pm[ConvexHull(Pm).vertices]
                    cc = hull.mean(0)
                    ax.add_patch(Polygon(cc + 1.12 * (hull - cc), closed=True, facecolor=tc[t], alpha=0.05,
                                         edgecolor="none", zorder=0, clip_on=False))
                vehicles(ax, X, Y, vc, alpha=0.15, z=1, ec="none", lw=0)
                for (a, b), w in Wq.items():
                    ax.plot(*zip(Pn[a], Pn[b]), color="#7d7d7d", lw=lws[(a, b)] * 72, solid_capstyle="butt",
                            zorder=2, clip_on=False)
                for t in range(nt):
                    mk, s = CN[team_kind[t]]
                    ax.scatter(*Pn[t], s=s, c="white", marker=mk, edgecolors=[tc[t]], linewidths=RING_LW,
                               zorder=3, clip_on=False)
            if labels or only_labels:
                for t in range(nt):
                    ax.text(*anchors[t], str(len(mem[t])), fontsize=C_LFS, color=os.environ.get("F1_CNUM", tc[t]), ha="center",
                            va="center", zorder=4, clip_on=False)
            return
        if not only_labels:
            for (a, b), w in Wq.items():
                ax.plot(*zip(Pn[a], Pn[b]), color="#7d7d7d", lw=lws[(a, b)] * 72, solid_capstyle="butt",
                        zorder=2, clip_on=False)
            for t in range(nt):
                mk, s = CN[team_kind[t]]
                ax.scatter(*Pn[t], s=s, c=[tc[t]], marker=mk, edgecolors="white", linewidths=0.6, zorder=3,
                           clip_on=False)
        if labels or only_labels:
            for t in range(nt):
                ax.text(*anchors[t], str(len(mem[t])), fontsize=C_LFS, color=SEC, ha="center", va="center",
                        zorder=4, clip_on=False)
    elif k == 3 and DSTYLE == "vA":
        rr = float(os.environ.get("F1_DPAD", "0.06")) * span   # soft margin around each team
        th = np.linspace(0, 2 * np.pi, 28, endpoint=False)
        for t in range(nt):   # rounded team outline with a margin: hull of discs around the members
            Pm = np.c_[Xe[mem[t]], Ye[mem[t]]]
            Q = (Pm[:, None, :] + rr * np.c_[np.cos(th), np.sin(th)][None]).reshape(-1, 2)
            hull = Q[ConvexHull(Q).vertices][::2]
            for _ in range(4):   # Chaikin corner cutting: a soft, hand-drawn-looking closed curve
                nxt = np.roll(hull, -1, axis=0)
                hull = np.vstack([np.c_[0.75 * hull + 0.25 * nxt], np.c_[0.25 * hull + 0.75 * nxt]]).reshape(2, -1, 2).transpose(1, 0, 2).reshape(-1, 2)
            ax.add_patch(Polygon(hull, closed=True, facecolor=_tint(tc[t], 0.10), edgecolor=_tint(tc[t], 0.45),
                                 linewidth=0.45, joinstyle="round", zorder=0, clip_on=False))
        ax.add_collection(LineCollection(curves, colors=[_tint(c, 0.80) for c in vc], linewidths=0.55, zorder=2,
                                         capstyle="round"))
        vehicles(ax, Xe, Ye, vc, z=4)
    elif k == 3:
        segE = [[(Xe[i - 1], Ye[i - 1]), (Xe[j - 1], Ye[j - 1])] for i, j in E]
        ax.add_collection(LineCollection([q for q, a in zip(segE, inner) if not a], colors="#d4d4d4",
                                         linewidths=0.4, zorder=1))
        ax.add_collection(LineCollection(curves, colors=vc, linewidths=0.45, alpha=0.6, zorder=2,
                                         capstyle="round"))
        if BOLD:
            vehicles(ax, X, Y, vc, alpha=0.22, z=1, ec="none", lw=0)
        vehicles(ax, Xe, Ye, vc, z=4)


def data_box(k, cgeo):
    if k == 3:
        xs = np.concatenate([X, Xe] + [c[:, 0] for c in curves]); ys = np.concatenate([Y, Ye] + [c[:, 1] for c in curves])
    elif k == 2:
        xs, ys = cgeo[0][:, 0], cgeo[0][:, 1]
        if BOLD:
            xs, ys = np.r_[xs, X], np.r_[ys, Y]
    else:
        xs, ys = X, Y
    return xs.min(), xs.max(), ys.min(), ys.max()


def panel_ink(k, sc, cgeo):
    """Ink bbox of panel k in data units, measured from a solo raster."""
    x0, x1, y0, y1 = data_box(k, cgeo)
    m = 0.3 * sc
    x0 -= m; x1 += m; y0 -= m; y1 += m
    w, h = (x1 - x0) / sc, (y1 - y0) / sc
    f = Figure(figsize=(w, h), facecolor="white")
    ax = f.add_axes([0, 0, 1, 1]); ax.set_xlim(x0, x1); ax.set_ylim(y0, y1); ax.axis("off")
    draw_panel(ax, k, sc, cgeo)
    bb = raster_ink(f)
    return np.array([x0 + bb[0] * sc, y0 + bb[1] * sc, x0 + bb[2] * sc, y0 + bb[3] * sc]), (x0, x1, y0, y1)


# ---------------------------------------------------------------------------------------------- text pieces
titles = ["Fleet and formation graph", "Teams", "Team program", "Members copy the input"]
subs = [os.environ.get("F1_SUBA", "heterogeneous drones and cars"), "equal weight into other teams", "one vehicle per team", "each team moves as one"]
alabels = ["color\nrefinement", os.environ.get("F1_ARRB", "reduce"), "copy\nteam input"]
LOOPTXT = os.environ.get("F1_LOOPTXT", "certify the plan, split teams with a large certificate $\\eta$")
TKW = dict(fontsize=TFS, color="black", ha="left", va="baseline")
LKW = dict(fontsize=TFS, color="black", ha="left", va="baseline", fontweight="bold")
SKW = dict(fontsize=SFS, color=SEC, ha="left", va="baseline", fontstyle="italic")
AKW = dict(fontsize=SFS, color=SEC, ha="center", va="baseline", fontstyle="italic", linespacing=1.1,
           multialignment="center")
LGAP = 0.045                    # ink gap between "(a)" and its title


def title_geom(k):
    li = text_ink("(%s)" % "abcd"[k], **LKW)
    ti = text_ink(titles[k], **TKW)
    si = text_ink(subs[k], **SKW)
    wt = (li[2] - li[0]) + LGAP + (ti[2] - ti[0])
    return li, ti, si, wt, si[2] - si[0]


def legend_pieces():
    tw = [text_ink(s, **SKW) for s in ("drone", "car")]
    return tw


# ---------------------------------------------------------------------------------------------- layout
def layout(sc):
    """Shared scale sc for (a), (b), (d); (b) and (c) are shrunk, if needed, until their drawings sit at least
    0.03 in inside their title block, so the card padding is set by the text and the arrows clear the drawings."""
    tg = [title_geom(k) for k in range(4)]
    sck = [sc] * 4
    cg = c_layout(sc)
    inks = []
    for k in range(4):
        ib, _ = panel_ink(k, sck[k], cg)
        if BOLD and k == 2:
            # (c) as wide as the drawing of (b); the arrow leaving the card is measured to the card only
            for _ in range(4):
                w = (ib[2] - ib[0]) / sck[k]
                if abs(w - wd1) < 5e-4:
                    break
                sck[k] *= w / wd1
                cg = c_layout(sck[k])
                ib, _ = panel_ink(k, sck[k], cg)
        elif k in (1, 2):
            tw = max(tg[k][3], tg[k][4]) - 2 * INSET
            for _ in range(3):
                w = (ib[2] - ib[0]) / sck[k]
                if w <= tw + 1e-4:
                    break
                sck[k] *= w / tw * 1.002
                if k == 2:
                    cg = c_layout(sck[k])
                ib, _ = panel_ink(k, sck[k], cg)
        inks.append(ib)
        if k == 1:
            wd1 = (ib[2] - ib[0]) / sck[k]
    wd = [(ib[2] - ib[0]) / sck[k] for k, ib in enumerate(inks)]
    hd = [(ib[3] - ib[1]) / sck[k] for k, ib in enumerate(inks)]
    blk = [max(wd[k], tg[k][3], tg[k][4]) for k in range(4)]
    aw = [text_ink(s, **AKW) for s in alabels]
    awid = [a[2] - a[0] for a in aw]
    # arrow length: labels centred on the arrow must keep 0.03 in off the card
    L = max(max(awid) - 2 * (CARD_GAP - 0.035), 0.40)
    x = {}
    x["a"] = MARG + blk[0] / 2
    a1 = (x["a"] + wd[0] / 2 + CL, None)
    a1 = (a1[0], a1[0] + L)
    cardL = a1[1] + CARD_GAP + AA + BW / 2               # card path (centre of the border line)
    x["b"] = cardL + BW / 2 + PAD + AA + blk[1] / 2
    t2 = x["b"] + wd[1] / 2 + CL
    a2 = (t2, t2 + L)
    x["c"] = a2[1] + CL + wd[2] / 2
    sep = 0.14                                       # ink gap between the (b) and (c) title blocks
    need = x["b"] + blk[1] / 2 + sep + blk[2] / 2
    if x["c"] < need:                                # widen the inner gap evenly around the arrow
        extra = need - x["c"]
        a2 = (a2[0] + extra / 2, a2[1] + extra / 2); x["c"] = need
    cardR = x["c"] + blk[2] / 2 + PAD + AA + BW / 2
    a3 = (cardR + BW / 2 + CARD_GAP + AA, cardR + BW / 2 + CARD_GAP + AA + L)
    x["d"] = a3[1] + CL + wd[3] / 2
    right = x["d"] + blk[3] / 2
    # centre the outer arrows in their gaps (drawing ink to card line), keeping every position
    gl, gr = x["a"] + wd[0] / 2, cardL - BW / 2
    a1 = ((gl + gr - L) / 2, (gl + gr + L) / 2)
    gl, gr = cardR + BW / 2, x["d"] - wd[3] / 2
    a3 = ((gl + gr - L) / 2, (gl + gr + L) / 2)
    return dict(sck=sck, cg=cg, inks=inks, wd=wd, hd=hd, tg=tg, blk=blk, aw=aw, L=L, xc=[x["a"], x["b"], x["c"], x["d"]],
                arrows=[a1, a2, a3], card=[cardL, cardR], right=right)


def solve():
    # bisection on the shared scale so the layout fills exactly TEXTW - MARG on the right
    lo, hi = 3.0, 30.0                             # data units per inch
    cg = None
    for _ in range(22):
        sc = np.sqrt(lo * hi)
        lay = layout(sc)
        cg = lay["cg"]
        if lay["right"] > TEXTW - MARG:
            lo = sc
        else:
            hi = sc
        if abs(lay["right"] - (TEXTW - MARG)) < 0.002:
            break
    return sc, cg, lay


def build(sc, cg, lay, mode="full", Hf=H0, dy=0.0):
    """mode: full | c_nolabels | c_labels (the last two only draw panel (c), for the label check)."""
    fig = plt.figure(figsize=(TEXTW, Hf), facecolor="white")
    tg = lay["tg"]
    # vertical: title baseline, subtitle baseline, drawing centres
    yT = H0 - 0.30 + dy
    yS = yT - 0.145
    sub_bottom = yS + min(t[2][1] for t in tg)
    hmax = max(lay["hd"])
    yM = sub_bottom - 0.075 - hmax / 2
    info = {"panels": [], "arrows": [], "titles": [], "c_labels": []}
    axs = []
    for k in range(4):
        sc = lay["sck"][k]
        ib = lay["inks"][k]
        icx, icy = (ib[0] + ib[2]) / 2, (ib[1] + ib[3]) / 2
        x0, x1, y0, y1 = data_box(k, cg)
        m = 0.3 * sc
        x0 -= m; x1 += m; y0 -= m; y1 += m
        w, h = (x1 - x0) / sc, (y1 - y0) / sc
        axl = lay["xc"][k] - (icx - x0) / sc
        ayl = yM - (icy - y0) / sc
        ax = fig.add_axes([axl / TEXTW, ayl / Hf, w / TEXTW, h / Hf])
        ax.set_xlim(x0, x1); ax.set_ylim(y0, y1); ax.axis("off")
        if mode == "full":
            draw_panel(ax, k, sc, cg)
        elif k == 2:
            draw_panel(ax, k, sc, cg, labels=(mode != "c_nolabels"), only_labels=(mode == "c_labels"))
        axs.append(ax)
        ink_in = [lay["xc"][k] - lay["wd"][k] / 2, yM - lay["hd"][k] / 2, lay["xc"][k] + lay["wd"][k] / 2,
                  yM + lay["hd"][k] / 2]
        info["panels"].append(ink_in)
        if k == 2:
            for t, r in cg[2].items():
                info["c_labels"].append([axl + (r[0] - x0) / sc, ayl + (r[1] - y0) / sc,
                                         axl + (r[2] - x0) / sc, ayl + (r[3] - y0) / sc])
    if mode != "full":
        return fig, info
    # titles and subtitles centred on each drawing's ink centre
    for k in range(4):
        li, ti, si, wt, ws = tg[k]
        xc = lay["xc"][k]
        g0 = xc - wt / 2                                   # left ink edge of the group
        xl = g0 - li[0]
        xt = g0 + (li[2] - li[0]) + LGAP - ti[0]
        fig.text(xl / TEXTW, yT / Hf, "(%s)" % "abcd"[k], **LKW)
        fig.text(xt / TEXTW, yT / Hf, titles[k], **TKW)
        xs = xc - (si[0] + si[2]) / 2
        fig.text(xs / TEXTW, yS / Hf, subs[k], **SKW)
        info["titles"].append(dict(title=[g0, yT + min(li[1], ti[1]), g0 + wt, yT + max(li[3], ti[3])],
                                   sub=[xc - ws / 2, yS + si[1], xc + ws / 2, yS + si[3]]))
    # card
    tops = [yT + max(tg[k][0][3], tg[k][1][3]) for k in (1, 2)]
    bots = [yM - lay["hd"][k] / 2 for k in (1, 2)]
    cT = max(tops) + PAD - AA + BW / 2
    cB = min(bots) - PAD - AA - BW / 2
    cL, cR = lay["card"]
    cL -= CARD_ADJ["left"]; cR += CARD_ADJ["right"]; cT += CARD_ADJ["top"]; cB -= CARD_ADJ["bottom"]
    info["card"] = [cL, cB, cR, cT] if STY in ("card", "bold") else None
    if STY in ("card", "bold"):
        fig.add_artist(FancyBboxPatch((cL, cB), cR - cL, cT - cB,
                                      boxstyle="round,pad=0,rounding_size=%f" % CARD_R, transform=fig.dpi_scale_trans,
                                      facecolor="none", edgecolor=CARD_EC, linewidth=CARD_LW, zorder=-5))

    def arrow(pts, color, lw):
        """Polyline (inches) ending in a filled head at pts[-1]; exact ink, no stroke overshoot."""
        pts = [np.asarray(p, float) for p in pts]
        u = pts[-1] - pts[-2]; u /= np.linalg.norm(u)
        base = pts[-1] - HEAD_L * u
        body = pts[:-1] + [base + 0.004 * u]
        fig.add_artist(PathPatch(Path(np.array(body)), transform=fig.dpi_scale_trans, facecolor="none",
                                 edgecolor=color, lw=lw, capstyle="butt", joinstyle="round"))
        nrm = np.array([-u[1], u[0]])
        fig.add_artist(Polygon([pts[-1], base + HEAD_W * nrm, base - HEAD_W * nrm], closed=True,
                               transform=fig.dpi_scale_trans, facecolor=color, edgecolor="none", lw=0))

    # horizontal arrows at the common drawing centre line, labels centred above them
    for k, (x0, x1) in enumerate(lay["arrows"]):
        arrow([(x0, yM), (x1, yM)], ARROW, float(os.environ.get("F1_ALW", "1.1")))
        ai = lay["aw"][k]
        xm = (x0 + x1) / 2
        fig.text((xm - (ai[0] + ai[2]) / 2) / TEXTW, (yM + 0.05 - ai[1]) / Hf, alabels[k], **AKW)
        info["arrows"].append(dict(x0=x0, x1=x1, y=yM, label=[xm - (ai[2] - ai[0]) / 2, yM + 0.05,
                                                              xm + (ai[2] - ai[0]) / 2, yM + 0.05 + ai[3] - ai[1]]))
    # legend under (a): 0.08 in below the drawing ink, centred on its ink centre
    tw = legend_pieces()
    mside = {"o": np.sqrt(MS["drone"][1]) / 72, "s": np.sqrt(MS["car"][1]) / 72}
    sp_mt, sp_grp = 0.035, 0.12
    parts = [("o", mside["o"]), ("drone", tw[0]), ("s", mside["s"]), ("car", tw[1])]
    widths = [p[1] if isinstance(p[1], float) else p[1][2] - p[1][0] for p in parts]
    total = widths[0] + sp_mt + widths[1] + sp_grp + widths[2] + sp_mt + widths[3]
    xa = lay["xc"][0]
    ytop_leg = yM - lay["hd"][0] / 2 - 0.08
    th = max(t[3] for t in tw)                     # tallest text ink above baseline
    tb = min(t[1] for t in tw)
    hgt = max(th - tb, mside["o"], mside["s"])
    ymid = ytop_leg - hgt / 2
    xcur = xa - total / 2
    for i, (p, _) in enumerate(parts):
        wv = widths[i]
        if p in ("o", "s"):
            ms = np.sqrt(MS["drone" if p == "o" else "car"][1])
            fig.add_artist(Line2D([xcur + wv / 2], [ymid], ls="", marker=p, ms=ms, mfc=NODE_A, mec="none",
                                  transform=fig.dpi_scale_trans))
            xcur += wv + sp_mt
        else:
            ti = parts[i][1]
            fig.text((xcur - ti[0]) / TEXTW, (ymid - (ti[1] + ti[3]) / 2) / Hf, p, **SKW)
            xcur += wv + sp_grp
    info["legend"] = [xa - total / 2, ymid - hgt / 2, xa + total / 2, ymid + hgt / 2]
    # loop: from under (d), along the bottom, up to just below the card under (b)
    xd, xb = lay["xc"][3], lay["xc"][1]
    y_tail = yM - lay["hd"][3] / 2 - CL
    y_tip = cB - BW / 2 - CARD_GAP - AA
    rad = 0.06
    li = text_ink(LOOPTXT, **SKW)
    th_loop = li[3] - li[1]
    y_row = min(y_tip - HEAD_L - rad - 0.03, y_tail - rad - 0.02)
    xm = (xd + xb) / 2
    hw = (li[2] - li[0]) / 2
    gapx = 0.06

    def corner_path(pts):
        verts, codes = [pts[0]], [Path.MOVETO]
        for a, b, c in zip(pts[:-2], pts[1:-1], pts[2:]):
            a, b, c = map(np.asarray, (a, b, c))
            u = (a - b) / np.linalg.norm(a - b); v = (c - b) / np.linalg.norm(c - b)
            verts += [tuple(b + rad * u), tuple(b), tuple(b + rad * v)]
            codes += [Path.LINETO, Path.CURVE3, Path.CURVE3]
        verts.append(pts[-1]); codes.append(Path.LINETO)
        return Path(verts, codes)
    fig.add_artist(PathPatch(corner_path([(xd, y_tail), (xd, y_row), (xm + hw + gapx, y_row)]),
                             transform=fig.dpi_scale_trans, facecolor="none", edgecolor=LOOPC, lw=0.9,
                             capstyle="butt"))
    # second piece: horizontal from the text to under (b), corner, up, head
    base = y_tip - HEAD_L
    fig.add_artist(PathPatch(corner_path([(xm - hw - gapx, y_row), (xb, y_row), (xb, base + 0.004)]),
                             transform=fig.dpi_scale_trans, facecolor="none", edgecolor=LOOPC, lw=0.9,
                             capstyle="butt"))
    fig.add_artist(Polygon([(xb, y_tip), (xb - HEAD_W, base), (xb + HEAD_W, base)], closed=True,
                           transform=fig.dpi_scale_trans, facecolor=LOOPC, edgecolor="none"))
    fig.text((xm - (li[0] + li[2]) / 2) / TEXTW, (y_row - (li[1] + li[3]) / 2) / Hf, LOOPTXT, **SKW)
    info["loop"] = dict(tail=[xd, y_tail], tip=[xb, y_tip], row=y_row,
                        label=[xm - hw, y_row - th_loop / 2, xm + hw, y_row + th_loop / 2])
    return fig, info


CARD_ADJ = dict(left=0.0, right=0.0, top=0.0, bottom=0.0)


def card_pads(fig, card, dpi=200):
    """Card padding as it rasterises at dpi: border pixels found near the card, interior ink bbox, corners out."""
    fig.set_dpi(dpi)
    cv = FigureCanvasAgg(fig); cv.draw()
    a = np.asarray(cv.buffer_rgba())[:, :, :3]
    ink = a.min(2) < 245
    Hp = a.shape[0]
    cL, cB, cR, cT = card
    px = lambda x: int(round(x * dpi)); py = lambda y: int(round(Hp - y * dpi))
    rows = slice(py(cT - 0.06), py(cB + 0.06)); cols = slice(px(cL + 0.06), px(cR - 0.06))
    bc = lambda xc: [c for c in range(px(xc - 0.03), px(xc + 0.03)) if ink[rows, c].mean() > 0.9]
    br = lambda yc: [r for r in range(py(yc + 0.03), py(yc - 0.03)) if ink[r, cols].mean() > 0.9]
    L_in, R_in = max(bc(cL)) + 1, min(bc(cR))
    T_in, B_in = max(br(cT)) + 1, min(br(cB))
    m = np.zeros_like(ink); m[T_in:B_in, L_in:R_in] = True
    k = px(0.045)
    m[T_in:T_in + k, L_in:L_in + k] = m[T_in:T_in + k, R_in - k:R_in] = False
    m[B_in - k:B_in, L_in:L_in + k] = m[B_in - k:B_in, R_in - k:R_in] = False
    rs, cs = np.nonzero(ink & m)
    return dict(left=(cs.min() - L_in) / dpi, right=(R_in - cs.max() - 1) / dpi, top=(rs.min() - T_in) / dpi,
                bottom=(B_in - rs.max() - 1) / dpi)


def main():
    sc, cg, lay = solve()
    fig, info = build(sc, cg, lay)
    full = raster_ink(fig)
    plt.close(fig)
    y0, y1 = full[1] - MARG, full[3] + MARG
    Hf = y1 - y0
    fig, info = build(sc, cg, lay, Hf=Hf, dy=-y0)
    if info["card"]:
        # snap the card to the 200 dpi grid: move each side by its rasterised padding error
        pads = card_pads(fig, info["card"])
        plt.close(fig)
        for sd, v in pads.items():
            CARD_ADJ[sd] = PAD - v
        fig, info = build(sc, cg, lay, Hf=Hf, dy=-y0)
        print("card padding before snap: " + " ".join("%s %.3f" % kv for kv in pads.items()))
    os.makedirs(OUT, exist_ok=True)
    tag = "F1F_%s" % STY
    fig.savefig(os.path.join(OUT, tag + ".pdf"), pad_inches=0, facecolor="white")
    fig.savefig(os.path.join(OUT, tag + ".png"), pad_inches=0, dpi=200, facecolor="white")
    plt.close(fig)
    aux = os.path.join(OUT, "F1F_aux"); os.makedirs(aux, exist_ok=True)
    for mode in ("c_nolabels", "c_labels"):
        f2, _ = build(sc, cg, lay, mode, Hf=Hf, dy=-y0)
        f2.savefig(os.path.join(aux, "%s_%s.png" % (tag, mode)), pad_inches=0, dpi=200,
                   facecolor="white")
        plt.close(f2)

    info.update(height=Hf, width=TEXTW, scale=sc, L=lay["L"])
    with open(os.path.join(OUT, tag + "_layout.json"), "w") as f:
        json.dump(info, f, indent=1, default=float)
    if BOLD:
        print("(c) width %.3f in, (b) width %.3f in, max nudge %.4f in" % (lay["wd"][2], lay["wd"][1], C_NUDGED))
    print("scale %.4f  height %.3f in  arrow L %.3f" % (sc, y1 - y0, lay["L"]))


if __name__ == "__main__":
    main()
