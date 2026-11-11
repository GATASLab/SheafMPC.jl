"""Gallery D3: the certificate figure redesigned (alternatives to Fig. 2, render/fig_certgap.py).

Data: results/fig_certgap_data.json, filtered exactly as render/fig_certgap.py and
scripts/resolution/numbers_certgap.jl (per-group dedup of (gap, eta) pairs, gap >= 1e-5 V_N^0).
Medians printed on the figure are recomputed here and asserted against preamble/numbers_certgap.tex.

  D3a  log-log scatter with direct labels, plus a side strip of eta / gamma per group
  D3b  ratio only: eta / gamma per group as jittered strips, tight line at 1, medians labeled

    python3 render/gallery/D3_certificate.py
"""
import json
import os
import re

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
RES = os.path.join(ROOT, "results")
OUT = os.environ.get("OUT_DIR", os.path.join(os.path.dirname(__file__), "out"))
COLW = 3.5
GAP_FLOOR = 1e-5
SUBSAMPLE = 1500

plt.rcParams.update({
    "font.family": "serif", "font.serif": ["TeX Gyre Termes", "Nimbus Roman", "Times New Roman"],
    "mathtext.fontset": "cm", "font.size": 8, "axes.labelsize": 8,
    "xtick.labelsize": 7, "ytick.labelsize": 7, "axes.linewidth": 0.5,
    "xtick.direction": "out", "ytick.direction": "out",
    "xtick.major.width": 0.5, "ytick.major.width": 0.5, "xtick.minor.width": 0.35, "ytick.minor.width": 0.35,
    "xtick.major.size": 2.5, "ytick.major.size": 2.5, "xtick.minor.size": 1.5, "ytick.minor.size": 1.5,
    "axes.spines.top": False, "axes.spines.right": False,
    "axes.grid": False, "savefig.dpi": 300, "pdf.fonttype": 42,
})
BLUE, ORANGE, GREEN, VERM, SKY, GREY = "#0072B2", "#E69F00", "#009E73", "#D55E00", "#56B4E9", "#7a7a7a"

# key, color, marker, size, alpha, label used on the figure, macro prefix
GROUPS = [
    ("E63", SKY, "o", 3.5, 0.35, "irregular formations", "Rand"),
    ("E69", ORANGE, "s", 3.5, 0.30, "inconsistent references", "Incons"),
    ("E112", GREEN, "^", 6, 0.50, "certified refinement", "Refine"),
    ("E106", VERM, "D", 4, 0.8, "about 4000 vehicles", "Big"),
]
DARK = {SKY: "#2b7fb0", ORANGE: "#b77a00", GREEN: GREEN, VERM: VERM}  # text versions, readable on white


def macros():
    txt = open(os.path.join(ROOT, "preamble", "numbers_certgap.tex")).read()
    return {k: v for k, v in re.findall(r"\\newcommand\{\\(cnCg\w+)\}\{([^}]*)\}", txt)}


def load():
    with open(os.path.join(RES, "fig_certgap_data.json")) as f:
        D = json.load(f)["groups"]
    M = macros()
    out = {}
    allr = []
    for key, *_, pre in GROUPS:
        g = np.asarray(D[key]["gap_rel"], float)
        e = np.asarray(D[key]["eta_rel"], float)
        _, first = np.unique(np.stack([g, e], 1), axis=0, return_index=True)
        first = np.sort(first)
        g, e = g[first], e[first]
        keep = g >= GAP_FLOOR
        g, e = g[keep], e[keep]
        r = e / g
        assert len(g) == int(M[f"cnCg{pre}N"]), (key, len(g))
        assert f"{np.median(r):.3g}" == M[f"cnCg{pre}Med"], (key, np.median(r), M[f"cnCg{pre}Med"])
        out[key] = (g, e, r)
        allr.append(r)
    allr = np.concatenate(allr)
    assert len(allr) == int(M["cnCgN"])
    assert f"{np.median(allr):.2g}" == M["cnCgMed"], np.median(allr)
    assert (allr >= 1).all()
    return out, allr, M


def save(fig, name):
    fig.savefig(os.path.join(OUT, name + ".pdf"), bbox_inches="tight", pad_inches=0.02)
    fig.savefig(os.path.join(OUT, name + ".png"), bbox_inches="tight", pad_inches=0.02, dpi=200)
    plt.close(fig)


def sub(rng, *arrs):
    n = len(arrs[0])
    if n <= SUBSAMPLE:
        return arrs
    idx = rng.choice(n, SUBSAMPLE, replace=False)
    return tuple(a[idx] for a in arrs)


def fig_a(data, M):
    """Scatter (left) and a strip of the ratio per group (right), sharing nothing but the colors."""
    fig = plt.figure(figsize=(COLW, 2.25))
    ax = fig.add_axes([0.0, 0.0, 0.60, 1.0])
    sx = fig.add_axes([0.73, 0.0, 0.27, 1.0])
    rng = np.random.default_rng(0)
    for key, c, m, s, a, lab, pre in GROUPS:
        g, e, r = data[key]
        g, e = sub(rng, g, e)
        ax.scatter(g, e, s=s, marker=m, facecolor=c, edgecolor="none", alpha=a, rasterized=True, zorder=3)
    x0, x1 = 1e-5, 1e0
    xs = np.array([x0, x1])
    ax.plot(xs, xs, color="k", lw=0.8, zorder=4)
    ax.plot(xs, 2 * xs, color="k", lw=0.6, ls=(0, (3, 2)), zorder=4)
    ax.set_xscale("log")
    ax.set_yscale("log")
    ax.set_xlim(x0, x1)
    ax.set_ylim(x0, x1)
    ax.set_aspect("equal")
    ax.set_xticks([1e-5, 1e-4, 1e-3, 1e-2, 1e-1, 1e0])
    ax.set_yticks([1e-5, 1e-4, 1e-3, 1e-2, 1e-1, 1e0])
    ax.set_xlabel(r"true gap $\gamma_\varphi/V_N^0$")
    ax.set_ylabel(r"certificate $\eta/V_N^0$", labelpad=1)
    fig.canvas.draw()
    p0, p1 = ax.transData.transform([(1e-3, 1e-3), (1e-2, 1e-2)])
    ang = np.degrees(np.arctan2(p1[1] - p0[1], p1[0] - p0[0]))
    ax.text(1.2e-1, 1.2e-1 / 1.75, r"$\eta=\gamma_\varphi$", rotation=ang, rotation_mode="anchor", ha="center",
            va="center", fontsize=6.5)
    ax.text(6e-4, 2 * 6e-4 * 2.0, r"$\eta=2\gamma_\varphi$", rotation=ang, rotation_mode="anchor", ha="center",
            va="center", fontsize=6.5)
    # direct labels at the clouds
    lbl = {
        "E63": (6e-3, 4.5e-2, "irregular\nformations", "right"),
        "E69": (1.0e-1, 1.2e-2, "inconsistent\nreferences", "left"),
        "E112": (3.5e-3, 6.0e-4, "certified\nrefinement", "left"),
        "E106": (1.25e-5, 5.0e-4, "about 4000\nvehicles", "left"),
    }
    for key, c, *_ in GROUPS:
        x, y, t, ha = lbl[key]
        ax.text(x, y, t, color=DARK[c], fontsize=6.5, ha=ha, va="center", linespacing=0.95)

    # side strip: eta / gamma per group, all kept samples
    for i, (key, c, m, s, a, lab, pre) in enumerate(GROUPS):
        r = data[key][2]
        jit = rng.uniform(-0.28, 0.28, len(r))
        sx.scatter(i + jit, r, s=1.2, facecolor=c, edgecolor="none", alpha=min(1, a + 0.15), rasterized=True)
        med = np.median(r)
        sx.plot([i - 0.38, i + 0.38], [med, med], color="k", lw=0.9, solid_capstyle="butt", zorder=5)
        sx.text(i, 3.42, M[f"cnCg{pre}Med"], ha="center", va="bottom", fontsize=6.5, color=DARK[c])
    sx.axhline(1, color="k", lw=0.8)
    sx.axhline(2, color="k", lw=0.6, ls=(0, (3, 2)))
    sx.set_ylim(0.9, 3.4)
    sx.set_xlim(-0.6, 3.6)
    sx.set_xticks([])
    sx.spines["bottom"].set_visible(False)
    sx.set_yticks([1, 1.5, 2, 2.5, 3])
    sx.set_yticklabels(["1", "", "2", "", "3"])
    sx.set_ylabel(r"$\eta/\gamma_\varphi$", labelpad=1)
    sx.text(1.5, 3.62, "median", ha="center", va="bottom", fontsize=6.5)
    sx.text(3.65, 1.0, "tight", ha="left", va="center", fontsize=6.5, clip_on=False)
    sx.text(3.65, 2.0, r"$2\times$", ha="left", va="center", fontsize=6.5, clip_on=False)
    save(fig, "D3a_certificate_scatter_strip")


def fig_b(data, allr, M):
    """Ratio only: one row per group, the tight line at 1, the factor-2 line, medians labeled."""
    fig, ax = plt.subplots(figsize=(COLW, 1.75))
    rng = np.random.default_rng(1)
    rows = list(GROUPS)
    ny = len(rows)
    for i, (key, c, m, s, a, lab, pre) in enumerate(rows):
        y0 = ny - i  # top to bottom in the paper's order
        r = data[key][2]
        rr = sub(rng, r)[0]
        jit = rng.uniform(-0.27, 0.27, len(rr))
        ax.scatter(rr, y0 + jit, s=1.6, facecolor=c, edgecolor="none", alpha=min(1, a + 0.1), rasterized=True)
        med = np.median(r)
        ax.plot([med, med], [y0 - 0.36, y0 + 0.36], color="k", lw=1.0, solid_capstyle="butt", zorder=5)
        ax.text(3.45, y0, M[f"cnCg{pre}Med"], ha="left", va="center", fontsize=7)
        ax.text(0.97, y0, lab, ha="right", va="center", fontsize=7, color=DARK[c])
        ax.text(0.97, y0 - 0.33, f"{len(r)} samples", ha="right", va="center", fontsize=5.8, color=GREY)
    ax.axvline(1, color="k", lw=0.8, ymin=0, ymax=1)
    ax.axvline(2, color="k", lw=0.6, ls=(0, (3, 2)))
    ax.axvspan(1.2, 2.0, ymin=0.0, ymax=(ny + 0.42 - 0.05) / (ny + 0.75 - 0.05), color="#efefef", lw=0, zorder=0)
    ax.text(1.6, ny + 0.55, f"{M['cnCgBand']}% of all samples", ha="center", va="center", fontsize=6.5,
            color="#555555")
    ax.text(3.45, 0.25, f"all {M['cnCgMed']}", ha="left", va="center", fontsize=7)
    ax.text(3.45, ny + 0.55, "median", ha="left", va="center", fontsize=7)
    ax.text(1.03, 0.25, r"tight, $\eta=\gamma_\varphi$", ha="left", va="center", fontsize=6.5)
    ax.text(2.03, 0.25, r"$\eta=2\gamma_\varphi$", ha="left", va="center", fontsize=6.5)
    ax.set_xlim(1.0, 3.4)
    ax.set_ylim(0.05, ny + 0.75)
    ax.set_yticks([])
    ax.spines["left"].set_visible(False)
    ax.set_xticks([1, 1.5, 2, 2.5, 3])
    ax.set_xticklabels(["1", "1.5", "2", "2.5", "3"])
    ax.set_xlabel(r"certificate over true gap, $\eta/\gamma_\varphi$", labelpad=2)
    ax.set_clip_on(False)
    save(fig, "D3b_certificate_ratio")


def main():
    data, allr, M = load()
    fig_a(data, M)
    fig_b(data, allr, M)


if __name__ == "__main__":
    main()
