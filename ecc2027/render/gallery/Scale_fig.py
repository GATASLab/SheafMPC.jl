"""Gallery S: scale plate. A 1024-vehicle planted-squad fleet (drones round, cars square), its formation graph as
hairline texture, the coarsest exact teams of color refinement as thin outlines, a magnified lens on four teams,
and the team program on the same geometry (one node per team, area by member count, edge width by summed weight).

Data: results/teams_map.json ("squads": x, y, kind, edges, w, teams_aep). This is the seed-1 instance; the paper
reports only the median over seeds for this family (\\cnSimSqTeamsThousand), so the figure prints only counts read
from this file: vehicles = len(x), edges = len(edges), teams = max(teams_aep). No timings are printed.

    python3 render/gallery/Scale_fig.py [outdir]
Variants (lens on the four whole teams in the top-left corner, window x 0..7, y 27..34)
    S_a  column 3.5 x 2.5 in: lens and team program stacked on the left, fleet on the right; only the four lens
         teams are tinted (Okabe-Ito), the other 94 are thin grey outlines.
    S_b  as S_a, every team tinted from a 12-hue muted palette (spatially adjacent teams get different hues).
    S_c  full width 7.0 x 2.2 in: lens | fleet -> team program, four lens teams tinted.
    S_d  as S_c with every team tinted.
    S_a2 S_a restyled to match Fig. 1 (fig_overview.py): its rcParams, PALETTE, markers, greys, hull alpha,
         bold panel letters with upright titles and italic grey subtitles; 3.5 x 2.6 in.
    S_a3 Fig. 1 styling on a clean grid, 3.5 x 2.4 in: title row above both panels, fleet left, team program
         right, lens under the program fed by short leaders from a window at the right edge of the fleet
         (four whole teams). S_a3b: three-team window; S_a3c: central four-team window (long leaders).
"""
import json
import os
import sys

import numpy as np
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import LineCollection, PatchCollection
from matplotlib.patches import FancyArrowPatch, Polygon, Rectangle
from scipy.spatial import ConvexHull

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "render", "gallery")
plt.rcParams.update({
    "font.family": "serif", "font.serif": ["TeX Gyre Termes"], "mathtext.fontset": "cm", "font.size": 7.5,
    "axes.linewidth": 0.4, "pdf.fonttype": 42, "savefig.dpi": 300, "lines.solid_capstyle": "round",
})
PT = 1.0  # line widths below are in points

INK = "#1e1e1e"          # marks, type
HULL = "#3a3a3a"         # team outlines
EDGE = "#a39a8c"         # warm grey hairlines
EDGE_IN = "#7d7468"      # edges inside a team, a touch darker
FRAME = "#3a3a3a"
LEADER = "#8a8a8a"
# highlighted teams (Okabe-Ito, vermilion reserved for failure elsewhere in the paper)
HL = ["#0072B2", "#E69F00", "#009E73", "#CC79A7"]
HL_DARK = ["#005A8C", "#A87400", "#00704F", "#9E4F7F"]
# 12-hue muted palette for S_d (ordered so neighbours in the list are far apart in hue)
MUTED12 = ["#4E79A7", "#E0A04A", "#6B9E5E", "#B5655C", "#8C78B0", "#C9B458", "#5FA3A3", "#C27BA0",
           "#7F8C5A", "#D08A62", "#6A86C2", "#9C8270"]

LENS_TOPRIGHT = (26.4, 24.9, 7.2)   # x0, y0, side (data units): teams 16, 71 (drones), 83, 86 (cars)


def load():
    with open(os.path.join(ROOT, "results", "teams_map.json")) as f:
        D = json.load(f)["squads"]
    X, Y = np.array(D["x"]), np.array(D["y"])
    lab = np.array(D["teams_aep"]) - 1
    E = np.array(D["edges"]) - 1
    W = np.array(D["w"])
    kind = np.array(D["kind"])
    nt = lab.max() + 1
    mem = [np.flatnonzero(lab == t) for t in range(nt)]
    cen = np.array([[X[m].mean(), Y[m].mean()] for m in mem])
    tkind = [kind[m[0]] for m in mem]
    Wq = {}
    for (i, j), w in zip(E, W):
        a, b = sorted((lab[i], lab[j]))
        if a != b:
            Wq[(a, b)] = Wq.get((a, b), 0.0) + w
    inner = lab[E[:, 0]] == lab[E[:, 1]]
    return dict(X=X, Y=Y, P=np.c_[X, Y], lab=lab, E=E, W=W, kind=kind, nt=nt, mem=mem, cen=cen, tkind=tkind,
                Wq=Wq, inner=inner, n=len(X), ne=len(E))


def rounded_hull(P, r, k=20):
    th = np.linspace(0, 2 * np.pi, k, endpoint=False)
    Q = (P[:, None, :] + r * np.c_[np.cos(th), np.sin(th)][None]).reshape(-1, 2)
    h = ConvexHull(Q)
    return Q[h.vertices]


def segs(S, mask):
    P = S["P"]
    return np.stack([P[S["E"][mask, 0]], P[S["E"][mask, 1]]], axis=1)


def clean(ax, frame=False, lw=0.45):
    ax.set_xticks([]); ax.set_yticks([]); ax.set_aspect("equal")
    for s in ax.spines.values():
        s.set_visible(frame); s.set_linewidth(lw); s.set_color(FRAME)


def lims(S, pad=0.9):
    return (S["X"].min() - pad, S["X"].max() + pad), (S["Y"].min() - pad, S["Y"].max() + pad)


def marks(ax, S, idx, colors, s_drone, s_car, z=5, ec="none", elw=0.0):
    for kd, mk, s in (("drone", "o", s_drone), ("car", "s", s_car)):
        sel = [i for i in idx if S["kind"][i] == kd]
        if sel:
            c = colors if isinstance(colors, str) else [colors[i] for i in sel]
            ax.scatter(S["X"][sel], S["Y"][sel], s=s, marker=mk, c=c, linewidths=elw, edgecolors=ec, zorder=z)


def draw_fleet(ax, S, hl=None, tint=None, s_drone=1.1, s_car=0.95, hull_r=0.42, hull_lw=0.32,
               e_lw=0.18, e_alpha=0.32, hull_color=HULL, hl_alpha=0.30):
    """hl: dict team -> color index (filled teams). tint: list of colors per team (S_d)."""
    hl = hl or {}
    ax.add_collection(LineCollection(segs(S, ~S["inner"]), colors=EDGE, linewidths=e_lw, alpha=e_alpha, zorder=1))
    ax.add_collection(LineCollection(segs(S, S["inner"]), colors=EDGE_IN, linewidths=e_lw * 1.15,
                                     alpha=min(1, e_alpha * 1.8), zorder=2))
    polys, fills = [], []
    for t in range(S["nt"]):
        H = rounded_hull(S["P"][S["mem"][t]], hull_r)
        if t in hl:
            c = HL[hl[t]]
            ax.add_patch(Polygon(H, closed=True, fc=c, ec="none", alpha=hl_alpha, zorder=2.5))
            ax.add_patch(Polygon(H, closed=True, fc="none", ec=HL_DARK[hl[t]], lw=hull_lw * 1.6, zorder=3.2))
        elif tint is not None:
            ax.add_patch(Polygon(H, closed=True, fc=tint[t], ec="none", alpha=0.28, zorder=2.5))
            ax.add_patch(Polygon(H, closed=True, fc="none", ec=tint[t], lw=hull_lw * 1.3, zorder=3))
        else:
            polys.append(Polygon(H, closed=True))
    if polys:
        ax.add_collection(PatchCollection(polys, facecolor="none", edgecolor=hull_color, linewidths=hull_lw,
                                          zorder=3))
    marks(ax, S, range(S["n"]), INK, s_drone, s_car)


def draw_lens(ax, S, box, hl, s_drone=5.5, s_car=4.6, hull_r=0.42, tint=None):
    x0, y0, side = box
    ax.add_collection(LineCollection(segs(S, ~S["inner"]), colors=EDGE, linewidths=0.3, alpha=0.55, zorder=1))
    inn = segs(S, S["inner"])
    tl = S["lab"][S["E"][S["inner"], 0]]
    cols = [HL_DARK[hl[t]] if t in hl else (tint[t] if tint is not None else EDGE_IN) for t in tl]
    lws = [0.55 if t in hl else 0.35 for t in tl]
    ax.add_collection(LineCollection(inn, colors=cols, linewidths=lws, alpha=0.9, zorder=2))
    for t in range(S["nt"]):
        P = S["P"][S["mem"][t]]
        if not ((P[:, 0] > x0 - 3).any() and (P[:, 0] < x0 + side + 3).any() and (P[:, 1] > y0 - 3).any()
                and (P[:, 1] < y0 + side + 3).any()):
            continue
        H = rounded_hull(P, hull_r)
        if t in hl:
            ax.add_patch(Polygon(H, closed=True, fc=HL[hl[t]], ec="none", alpha=0.20, zorder=2.5))
            ax.add_patch(Polygon(H, closed=True, fc="none", ec=HL_DARK[hl[t]], lw=0.6, zorder=3))
        elif tint is not None:
            ax.add_patch(Polygon(H, closed=True, fc=tint[t], ec="none", alpha=0.24, zorder=2.5))
            ax.add_patch(Polygon(H, closed=True, fc="none", ec=tint[t], lw=0.6, zorder=3))
        else:
            ax.add_patch(Polygon(H, closed=True, fc="none", ec=INK, lw=0.4, zorder=3))
    marks(ax, S, range(S["n"]), INK, s_drone, s_car, ec="white", elw=0.25)
    ax.set_xlim(x0, x0 + side); ax.set_ylim(y0, y0 + side)


def draw_program(ax, S, hl, s_per=1.15, s0=1.0, wmin=0.15, wspan=1.5, ghost=False, tint=None, node_ec="white"):
    C, Wq, mem = S["cen"], S["Wq"], S["mem"]
    if ghost:
        marks(ax, S, range(S["n"]), "#cfc8bd", 0.55, 0.5, z=0.5)
    keys = sorted(Wq, key=lambda k: Wq[k])
    wmax = max(Wq.values())
    ax.add_collection(LineCollection([[C[a], C[b]] for a, b in keys], colors=EDGE_IN,
                                     linewidths=[wmin + wspan * Wq[k] / wmax for k in keys], alpha=0.85, zorder=1))
    for kd, mk, f in (("drone", "o", 1.0), ("car", "s", 0.82)):
        ts = [t for t in range(S["nt"]) if S["tkind"][t] == kd]
        cs = [HL[hl[t]] if t in hl else (tint[t] if tint is not None else INK) for t in ts]
        ax.scatter(C[ts, 0], C[ts, 1], s=[(s0 + s_per * len(mem[t])) * f for t in ts], marker=mk, c=cs,
                   edgecolors=node_ec, linewidths=0.3, zorder=3)


def lens_teams(S, box):
    x0, y0, side = box
    out = []
    for t in range(S["nt"]):
        P = S["P"][S["mem"][t]]
        if ((P[:, 0] >= x0) & (P[:, 0] <= x0 + side) & (P[:, 1] >= y0) & (P[:, 1] <= y0 + side)).all():
            out.append(t)
    # drones first, then cars, so colors read in a stable order
    out.sort(key=lambda t: (S["tkind"][t], -len(S["mem"][t])))
    return {t: k for k, t in enumerate(out[:4])}


def lens_rect(ax, box, lw=0.5):
    x0, y0, side = box
    ax.add_patch(Rectangle((x0, y0), side, side, fill=False, ec=INK, lw=lw, zorder=8))


def leader(fig, ax_from, box, ax_to, corners):
    """corners: list of ((data corner of box), (axes-fraction corner of ax_to))."""
    x0, y0, side = box
    for (cx, cy), (tx, ty) in corners:
        p = fig.transFigure.inverted().transform(ax_from.transData.transform((x0 + cx * side, y0 + cy * side)))
        q = fig.transFigure.inverted().transform(ax_to.transAxes.transform((tx, ty)))
        fig.add_artist(plt.Line2D([p[0], q[0]], [p[1], q[1]], transform=fig.transFigure, color=LEADER, lw=0.35,
                                  zorder=0))


def greedy_tint(S, palette):
    nt = S["nt"]
    adj = [set() for _ in range(nt)]
    C = S["cen"]
    for (a, b) in S["Wq"]:
        adj[a].add(b); adj[b].add(a)
    # also treat spatially close teams as adjacent, so nearby outlines never share a hue
    for a in range(nt):
        for b in range(a + 1, nt):
            if np.hypot(*(C[a] - C[b])) < 5.0:
                adj[a].add(b); adj[b].add(a)
    col = [-1] * nt
    for t in sorted(range(nt), key=lambda t: -len(adj[t])):
        used = {col[u] for u in adj[t] if col[u] >= 0}
        c = 0
        while c in used and c < len(palette) - 1:
            c += 1
        col[t] = c
    return [palette[c] for c in col]


def counts_text(S):
    return rf"{S['n']} vehicles, {S['ne']} formation edges $\to$ {S['nt']} teams"


def save(fig, name):
    for ext in ("pdf", "png"):
        fig.savefig(os.path.join(OUT, f"{name}.{ext}"), dpi=200 if ext == "png" else None)
    plt.close(fig)


# ---------------------------------------------------------------------------------------------------------------
LENS = (0.0, 27.0, 7.0)   # x0, y0, side: four whole teams in the top-left corner of the fleet


def window(ax, box, lw=0.5, color=INK, ls="-"):
    x0, y0, side = box
    ax.add_patch(Rectangle((x0, y0), side, side, fill=False, ec=color, lw=lw, ls=ls, zorder=8))


def column(S, tint=None, name="S_a_scale"):
    """Column: left strip holds the lens (top) and the team program (bottom); the fleet fills the right."""
    W, H = 3.5, 2.5
    fig = plt.figure(figsize=(W, H))
    box = LENS
    hl = {} if tint is not None else lens_teams(S, box)
    xl, yl = lims(S, pad=0.6)
    m = 0.02                        # keeps the frame inside the page
    sf = 2.24                       # fleet square, inches
    s2 = 1.09                       # strip squares
    top = H - 0.02
    axf = fig.add_axes([(W - sf) / W, (top - sf) / H, sf / W, sf / H])
    draw_fleet(axf, S, hl=hl, tint=tint, s_drone=1.15, s_car=1.0, hull_r=0.36, hull_lw=0.24, e_lw=0.17,
               e_alpha=0.30, hl_alpha=0.5)
    axf.set_xlim(*xl); axf.set_ylim(*yl); clean(axf)
    window(axf, box, lw=0.5)
    axl = fig.add_axes([m / W, (top - s2) / H, s2 / W, s2 / H])
    draw_lens(axl, S, box, hl, s_drone=5.0, s_car=4.2, hull_r=0.36, tint=tint)
    clean(axl, frame=True, lw=0.5)
    axp = fig.add_axes([m / W, (top - sf) / H, s2 / W, s2 / H])
    draw_program(axp, S, hl, s_per=0.62, s0=0.8, wmin=0.15, wspan=0.9, tint=tint, node_ec="white")
    axp.set_xlim(*xl); axp.set_ylim(*yl); clean(axp)
    window(axp, box, lw=0.35, color="0.55")
    leader(fig, axf, box, axl, [((0, 1), (1, 1)), ((0, 0), (1, 0))])
    yb = (top - sf) / H - 0.022
    fig.text((m + s2 / 2) / W, yb, rf"{S['nt']} teams", ha="center", va="top")
    fig.text((W - sf / 2) / W, yb, rf"{S['n']} vehicles, {S['ne']} formation edges", ha="center", va="top")
    save(fig, name)


def wide(S, tint=None, name="S_c_scale"):
    """Full width: lens | fleet | team program, on one baseline."""
    W, H = 7.0, 2.2
    fig = plt.figure(figsize=(W, H))
    box = LENS
    hl = {} if tint is not None else lens_teams(S, box)
    xl, yl = lims(S, pad=0.6)
    m = 0.02
    s = 1.96
    gap = (W - 2 * m - 3 * s) / 2
    yb = (H - s - m) / H
    axl = fig.add_axes([m / W, yb, s / W, s / H])
    draw_lens(axl, S, box, hl, s_drone=9.0, s_car=7.5, hull_r=0.36, tint=tint)
    clean(axl, frame=True, lw=0.5)
    axf = fig.add_axes([(m + s + gap) / W, yb, s / W, s / H])
    draw_fleet(axf, S, hl=hl, tint=tint, s_drone=1.2, s_car=1.05, hull_r=0.36, hull_lw=0.24, e_lw=0.17,
               e_alpha=0.30, hl_alpha=0.5)
    axf.set_xlim(*xl); axf.set_ylim(*yl); clean(axf)
    window(axf, box, lw=0.5)
    axp = fig.add_axes([(m + 2 * s + 2 * gap) / W, yb, s / W, s / H])
    draw_program(axp, S, hl, s_per=1.25, s0=1.2, wmin=0.18, wspan=1.6, tint=tint)
    axp.set_xlim(*xl); axp.set_ylim(*yl); clean(axp)
    window(axp, box, lw=0.4, color="0.6")
    leader(fig, axf, box, axl, [((0, 1), (1, 1)), ((0, 0), (1, 0))])
    xa0, xa1, ya = (m + 2 * s + gap + 0.13) / W, (m + 2 * s + 2 * gap - 0.13) / W, yb + 0.5 * s / H
    fig.add_artist(FancyArrowPatch((xa0, ya), (xa1, ya), transform=fig.transFigure, arrowstyle="-|>,head_length=3.2,head_width=1.6",
                                   lw=0.6, color=INK, shrinkA=0, shrinkB=0))
    ty = yb - 0.025
    nlens = len(lens_teams(S, box))
    fig.text((m + s / 2) / W, ty, rf"{nlens} of {S['nt']} teams", ha="center", va="top")
    fig.text((m + s + gap + s / 2) / W, ty, rf"{S['n']} vehicles, {S['ne']} formation edges", ha="center", va="top")
    fig.text((m + 2 * s + 2 * gap + s / 2) / W, ty, rf"team program, {S['nt']} vehicles", ha="center", va="top")
    save(fig, name)


# ---------------------------------------------------------------------------------------------------------------
# S_a2: S_a restyled to match the paper's Fig. 1 (render/fig_overview.py): same rcParams, PALETTE order, markers
# with white edges, edge greys, hull alpha (convex hull scaled 1.12 about its centroid), title and subtitle type.
F1_RC = {"font.family": "serif", "font.serif": ["TeX Gyre Termes", "Nimbus Roman", "Times New Roman"],
         "mathtext.fontset": "cm", "font.size": 8, "axes.linewidth": 0.5, "pdf.fonttype": 42, "savefig.dpi": 300}
F1_PALETTE = ["#0072B2", "#E69F00", "#009E73", "#D55E00", "#CC79A7", "#5E4FA2"]
F1_INK = "#3d3d3d"
F1_EDGE = "#c4c4c4"        # formation graph
F1_EDGE_X = "#e0e0e0"      # edges between teams
F1_QEDGE = "#8f8f8f"       # team program edges
FRAME2 = "0.25"            # lens frame and leader lines
OUTLINE2 = os.environ.get("S_OUTLINE", "0.55")  # team outlines in the fleet
LENS2 = (-0.6, 26.95, 6.2)  # x0, y0, height (data units); width follows the lens aspect


def f1_hull(P, scale=1.12):
    if len(P) < 3:
        return None
    h = P[ConvexHull(P).vertices]
    c = h.mean(0)
    return c + scale * (h - c)


def inside(S, t, x0, y0, w, h):
    P = S["P"][S["mem"][t]]
    return ((P[:, 0] >= x0) & (P[:, 0] <= x0 + w) & (P[:, 1] >= y0) & (P[:, 1] <= y0 + h)).all()


def f1_vehicles(ax, S, idx, colours, s_drone, s_car, ec="white", lw=0.35, alpha=1.0, z=4):
    for kd, mk, sz in (("drone", "o", s_drone), ("car", "s", s_car)):
        sel = [i for i in idx if S["kind"][i] == kd]
        if sel:
            ax.scatter(S["X"][sel], S["Y"][sel], s=sz, marker=mk, c=[colours[i] for i in sel], edgecolors=ec,
                       linewidths=lw, alpha=alpha, zorder=z)


def title_pair(fig, ax, letter, title, sub, ytit, ysub, W):
    b = ax.get_position(); xc = (b.x0 + b.x1) / 2
    tt = fig.text(xc, ytit, title, ha="center", va="top", fontsize=9.5, color="black")
    bb = tt.get_window_extent(renderer=fig.canvas.get_renderer()).transformed(fig.transFigure.inverted())
    fig.text(bb.x0 - 0.05 / W, ytit, "(%s)" % letter, ha="right", va="top", fontsize=9.5, fontweight="bold",
             color="black")
    fig.text(xc, ysub, sub, ha="center", va="top", fontsize=8.2, color="#555555", fontstyle="italic")


def column_f1(S, name="S_a2_scale"):
    with plt.rc_context(F1_RC):
        W, H = 3.5, 2.6
        m, gap = 0.03, 0.12
        Lw = 1.34                                   # left column: lens on top, team program below
        sf = W - 2 * m - Lw - gap                   # fleet square
        hdr = 0.31                                  # title + subtitle block
        yb = m
        fig = plt.figure(figsize=(W, H))
        n, nt = S["n"], S["nt"]
        # lens window and its teams (PALETTE order by team index)
        Lh = H - m - (yb + Lw + hdr + 0.07)
        x0, y0, lh_ = LENS2
        lw_ = lh_ * Lw / Lh
        hl_t = [t for t in range(nt) if inside(S, t, x0, y0, lw_, lh_)]
        col = {t: F1_PALETTE[k] for k, t in enumerate(hl_t)}
        vcol = [col.get(S["lab"][i], F1_INK) for i in range(n)]
        xl, yl = lims(S, pad=0.7)

        # (a) fleet
        axf = fig.add_axes([(W - m - sf) / W, yb / H, sf / W, sf / H])
        axf.add_collection(LineCollection(segs(S, np.ones(S["ne"], bool)), colors=F1_EDGE, linewidths=0.14,
                                          alpha=0.75, zorder=1))
        outl = []
        for t in range(nt):
            Hh = rounded_hull(S["P"][S["mem"][t]], 0.26)
            if t in col:
                hp = f1_hull(S["P"][S["mem"][t]])
                axf.add_patch(Polygon(rounded_hull(hp, 0.15), closed=True, fc=col[t], alpha=0.16, ec="none",
                                      zorder=2))
            else:
                outl.append(Polygon(Hh, closed=True))
        axf.add_collection(PatchCollection(outl, facecolor="none", edgecolor=OUTLINE2, linewidths=0.3, zorder=2))
        f1_vehicles(axf, S, [i for i in range(n) if S["lab"][i] not in col], vcol, 1.3, 1.1, ec="none", lw=0, z=3)
        inn = S["inner"] & np.isin(S["lab"][S["E"][:, 0]], list(col))
        axf.add_collection(LineCollection(segs(S, inn), colors=[col[S["lab"][i]] for i in S["E"][inn, 0]],
                                          linewidths=0.3, zorder=3.5))
        f1_vehicles(axf, S, [i for i in range(n) if S["lab"][i] in col], vcol, 2.4, 2.0, ec="none", lw=0, z=4)
        axf.add_patch(Rectangle((x0, y0), lw_, lh_, fill=False, ec=FRAME2, lw=0.5, zorder=8))
        axf.set_xlim(*xl); axf.set_ylim(*yl); axf.set_aspect("equal"); axf.axis("off")

        # lens
        axl = fig.add_axes([m / W, (H - m - Lh) / H, Lw / W, Lh / H])
        near = [t for t in range(nt) if t not in col]
        cross = ~S["inner"]
        axl.add_collection(LineCollection(segs(S, cross), colors=F1_EDGE_X, linewidths=0.3, alpha=0.7, zorder=1))
        for t in hl_t:
            axl.add_patch(Polygon(f1_hull(S["P"][S["mem"][t]]), closed=True, fc=col[t], alpha=0.09, ec="none",
                                  zorder=0))
        oth = S["inner"] & ~np.isin(S["lab"][S["E"][:, 0]], list(col))
        axl.add_collection(LineCollection(segs(S, oth), colors=F1_EDGE_X, linewidths=0.35, alpha=0.9, zorder=1.5))
        axl.add_collection(LineCollection(segs(S, inn), colors=[col[S["lab"][i]] for i in S["E"][inn, 0]],
                                          linewidths=0.55, zorder=2))
        f1_vehicles(axl, S, [i for i in range(n) if S["lab"][i] not in col], ["#c6c6c6"] * n, 8, 6.5, z=3)
        f1_vehicles(axl, S, [i for i in range(n) if S["lab"][i] in col], vcol, 13, 10.5, z=4)
        axl.set_xlim(x0, x0 + lw_); axl.set_ylim(y0, y0 + lh_); axl.set_xticks([]); axl.set_yticks([])
        for sp in axl.spines.values():
            sp.set_linewidth(0.5); sp.set_color(FRAME2); sp.set_zorder(10)
        print("S_a2 lens window", (x0, round(y0, 2), lw_, round(lh_, 2)), "teams", hl_t)

        # (b) team program
        axp = fig.add_axes([m / W, yb / H, Lw / W, Lw / H])
        C, Wq, mem = S["cen"], S["Wq"], S["mem"]
        for t in hl_t:
            axp.add_patch(Polygon(f1_hull(S["P"][mem[t]]), closed=True, fc=col[t], alpha=0.07, ec="none", zorder=0))
        keys = sorted(Wq, key=lambda k: Wq[k]); wmax = max(Wq.values())
        axp.add_collection(LineCollection([[C[a], C[b]] for a, b in keys], colors=F1_QEDGE,
                                          linewidths=[0.3 + 1.5 * Wq[k] / wmax for k in keys], capstyle="round",
                                          zorder=1))
        for kd, mk, f in (("drone", "o", 1.0), ("car", "s", 0.8)):
            ts = [t for t in range(nt) if S["tkind"][t] == kd]
            axp.scatter(C[ts, 0], C[ts, 1], s=[(2.6 + 1.25 * len(mem[t])) * f for t in ts], marker=mk,
                        c=[col.get(t, F1_INK) for t in ts], edgecolors="white", linewidths=0.35, zorder=3)
        axp.set_xlim(*xl); axp.set_ylim(*yl); axp.set_aspect("equal"); axp.axis("off")

        # leader lines from the window to the lens
        for (cx, cy), (tx, ty) in (((0, 1), (1, 1)), ((0, 0), (1, 0))):
            p = fig.transFigure.inverted().transform(axf.transData.transform((x0 + cx * lw_, y0 + cy * lh_)))
            q = fig.transFigure.inverted().transform(axl.transAxes.transform((tx, ty)))
            fig.add_artist(plt.Line2D([p[0], q[0]], [p[1], q[1]], transform=fig.transFigure, color=FRAME2, lw=0.5,
                                      zorder=0))

        ytit = (yb + sf + hdr) / H
        title_pair(fig, axf, "a", "Fleet and its exact teams", f"{n} drones and cars, {S['ne']} edges, {nt} teams",
                   ytit, ytit - 0.150 / H, W)
        ytp = (yb + Lw + hdr) / H
        title_pair(fig, axp, "b", "Team program", "one vehicle per team", ytp, ytp - 0.150 / H, W)
        save(fig, name)


def grid_f1(S, win, name="S_a3_scale"):
    """S_a3: Fig. 1 styling on a clean grid. Title row above both panels; fleet left, team program right with the
    lens under it; leaders from the lens window to the lens cross no text. win = (x0, y0, w, h), aspect 2:1."""
    with plt.rc_context(F1_RC):
        W, H = 3.5, 2.4
        m, gap, hdr = 0.03, 0.11, 0.36
        sf = H - 2 * m - hdr                        # fleet square
        pw = W - 2 * m - sf - gap                   # right column width (program square)
        fig = plt.figure(figsize=(W, H))
        n, nt = S["n"], S["nt"]
        x0, y0, lw_, lh_ = win
        Lh = pw * lh_ / lw_
        hl_t = [t for t in range(nt) if inside(S, t, x0 + 0.4, y0 + 0.4, lw_ - 0.8, lh_ - 0.8)]
        col = {t: F1_PALETTE[k] for k, t in enumerate(hl_t)}
        vcol = [col.get(S["lab"][i], F1_INK) for i in range(n)]
        isel = np.isin(S["lab"], list(col))
        xl, yl = lims(S, pad=0.7)
        top = H - m - hdr

        # (a) fleet
        axf = fig.add_axes([m / W, (top - sf) / H, sf / W, sf / H])
        axf.add_collection(LineCollection(segs(S, np.ones(S["ne"], bool)), colors=F1_EDGE, linewidths=0.14,
                                          alpha=0.75, zorder=1))
        outl = []
        for t in range(nt):
            if t in col:
                axf.add_patch(Polygon(rounded_hull(f1_hull(S["P"][S["mem"][t]]), 0.15), closed=True, fc=col[t],
                                      alpha=0.16, ec="none", zorder=2))
            else:
                outl.append(Polygon(rounded_hull(S["P"][S["mem"][t]], 0.26), closed=True))
        axf.add_collection(PatchCollection(outl, facecolor="none", edgecolor=OUTLINE2,
                                           linewidths=float(os.environ.get("S_OUTLINE_LW", "0.3")), zorder=2))
        f1_vehicles(axf, S, np.flatnonzero(~isel), vcol, 1.3, 1.1, ec="none", lw=0, z=3)
        inn = S["inner"] & isel[S["E"][:, 0]]
        axf.add_collection(LineCollection(segs(S, inn), colors=[col[S["lab"][i]] for i in S["E"][inn, 0]],
                                          linewidths=0.3, zorder=3.5))
        f1_vehicles(axf, S, np.flatnonzero(isel), vcol, 2.4, 2.0, ec="none", lw=0, z=4)
        axf.add_patch(Rectangle((x0, y0), lw_, lh_, fill=False, ec=FRAME2, lw=0.5, joinstyle="miter", zorder=8))
        axf.set_xlim(*xl); axf.set_ylim(*yl); axf.set_aspect("equal"); axf.axis("off")

        # (b) team program, top-aligned with the fleet
        axp = fig.add_axes([(W - m - pw) / W, (top - pw) / H, pw / W, pw / H])
        C, Wq, mem = S["cen"], S["Wq"], S["mem"]
        for t in hl_t:
            axp.add_patch(Polygon(f1_hull(S["P"][mem[t]]), closed=True, fc=col[t], alpha=0.07, ec="none", zorder=0))
        keys = sorted(Wq, key=lambda k: Wq[k]); wmax = max(Wq.values())
        axp.add_collection(LineCollection([[C[a], C[b]] for a, b in keys], colors=F1_QEDGE,
                                          linewidths=[0.3 + 1.5 * Wq[k] / wmax for k in keys], capstyle="round",
                                          zorder=1))
        for kd, mk, f in (("drone", "o", 1.0), ("car", "s", 0.8)):
            ts = [t for t in range(nt) if S["tkind"][t] == kd]
            axp.scatter(C[ts, 0], C[ts, 1], s=[(2.6 + 1.25 * len(mem[t])) * f for t in ts], marker=mk,
                        c=[col.get(t, F1_INK) for t in ts], edgecolors="white", linewidths=0.35,
                        zorder=[3][0])
        axp.set_xlim(*xl); axp.set_ylim(*yl); axp.set_aspect("equal"); axp.axis("off")

        # lens under the team program, bottom on the fleet baseline
        axl = fig.add_axes([(W - m - pw) / W, (top - sf) / H, pw / W, Lh / H])
        axl.add_collection(LineCollection(segs(S, ~S["inner"]), colors=F1_EDGE_X, linewidths=0.3, alpha=0.7,
                                          zorder=1))
        for t in hl_t:
            axl.add_patch(Polygon(f1_hull(S["P"][mem[t]]), closed=True, fc=col[t], alpha=0.09, ec="none", zorder=0))
        oth = S["inner"] & ~isel[S["E"][:, 0]]
        axl.add_collection(LineCollection(segs(S, oth), colors=F1_EDGE_X, linewidths=0.35, alpha=0.9, zorder=1.5))
        axl.add_collection(LineCollection(segs(S, inn), colors=[col[S["lab"][i]] for i in S["E"][inn, 0]],
                                          linewidths=0.55, zorder=2))
        f1_vehicles(axl, S, np.flatnonzero(~isel), ["#c6c6c6"] * n, 7, 5.8, z=3)
        f1_vehicles(axl, S, np.flatnonzero(isel), vcol, 11, 9, z=4)
        axl.set_xlim(x0, x0 + lw_); axl.set_ylim(y0, y0 + lh_); axl.set_xticks([]); axl.set_yticks([])
        for sp in axl.spines.values():
            sp.set_linewidth(0.5); sp.set_color(FRAME2); sp.set_zorder(10)

        # leaders: computed after layout (equal aspect resizes axf at draw time), window corner -> lens corner,
        # top-right -> top-left and bottom-right -> bottom-left (they do not cross each other or any content)
        fig.canvas.draw()
        lb = axl.get_position()
        to_fig = fig.transFigure.inverted()
        for (cx, cy), (tx, ty) in (((1, 1), (lb.x0, lb.y1)), ((1, 0), (lb.x0, lb.y0))):
            p = to_fig.transform(axf.transData.transform((x0 + cx * lw_, y0 + cy * lh_)))
            fig.add_artist(plt.Line2D([p[0], tx], [p[1], ty], transform=fig.transFigure, color=FRAME2, lw=0.5,
                                      solid_capstyle="butt", zorder=20))

        ytit = (H - m) / H
        ysub = ytit - 0.172 / H
        if os.environ.get("S_HEAD", "") == "exact":
            title_pair(fig, axf, "a", "Fleet and its exact teams", f"{n} drones and cars in {nt} teams", ytit, ysub, W)
            title_pair(fig, axp, "b", "Team program", f"{nt} vehicles, exact", ytit, ysub, W)
        else:
            title_pair(fig, axf, "a", "Fleet and its exact teams",
                       f"{n} drones and cars, {S['ne']} edges, {nt} teams", ytit, ysub, W)
            title_pair(fig, axp, "b", "Team program", "one vehicle per team", ytit, ysub, W)
        print(name, "window", win, "teams", hl_t, "sizes", [len(mem[t]) for t in hl_t])
        save(fig, name)


def main():
    S = load()
    tint = greedy_tint(S, MUTED12)
    column(S, name="S_a_scale")
    column(S, tint=tint, name="S_b_scale")
    wide(S, name="S_c_scale")
    wide(S, tint=tint, name="S_d_scale")
    column_f1(S)
    grid_f1(S, (21.75, 13.5, 12.6, 6.3), "S_a3_scale")
    grid_f1(S, (8.5, 16.0, 12.0, 6.0), "S_a3c_scale")
    grid_f1(S, (22.5, 18.0, 12.0, 6.0), "S_a3b_scale")


if __name__ == "__main__":
    main()
