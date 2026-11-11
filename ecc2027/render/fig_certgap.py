"""fig_certgap.pdf: the certificate eta of Lemma lem:cert against the true gap of the team plan, both over V_N^0
at the measured state, every certified sample of the HPG runs E63/E65b, E69, E112 and E106
(results/fig_certgap_data.json, built by scripts/resolution/merge_certgap.py).

Samples with gap below GAP_FLOOR * V_N^0 are dropped, as in scripts/resolution/numbers_certgap.jl. The random
formation group holds most of the samples; SUBSAMPLE of them, drawn uniformly with a fixed seed, are plotted, and
the legend counts are the kept samples of each group. Same plain style as render/fig_offformation.py.

    python3 render/fig_certgap.py
"""
import json
import os

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
RES = os.path.join(ROOT, "results")
FIG = os.path.join(ROOT, "figures")
COLW = 3.4
GAP_FLOOR = 1e-5
SUBSAMPLE = 1500

plt.rcParams.update({
    "font.family": "serif", "font.serif": ["TeX Gyre Termes", "Nimbus Roman", "Times New Roman"],
    "mathtext.fontset": "cm", "font.size": 8, "axes.labelsize": 8, "legend.fontsize": 6.5,
    "xtick.labelsize": 7.5, "ytick.labelsize": 7.5, "axes.linewidth": 0.6,
    "xtick.direction": "in", "ytick.direction": "in", "xtick.top": True, "ytick.right": True,
    "xtick.major.width": 0.5, "ytick.major.width": 0.5, "xtick.minor.width": 0.4, "ytick.minor.width": 0.4,
    "axes.grid": True, "grid.color": "#d4d4d4", "grid.linewidth": 0.4, "grid.linestyle": "-",
    "legend.frameon": True, "legend.edgecolor": "0.55", "legend.fancybox": False, "legend.framealpha": 1.0,
    "legend.borderpad": 0.35, "legend.handlelength": 2.2, "lines.linewidth": 1.0, "lines.markersize": 3.2,
    "savefig.dpi": 300, "pdf.fonttype": 42,
})
# Okabe-Ito
BLUE, ORANGE, GREEN, VERM, PURPLE, SKY, BLACK = "#0072B2", "#E69F00", "#009E73", "#D55E00", "#CC79A7", "#56B4E9", "#000000"

GROUPS = [  # key, color, marker, size, alpha (drawn in this order, the sparsest last)
    ("E63", SKY, "o", 4, 0.35),
    ("E69", ORANGE, "s", 4, 0.30),
    ("E112", GREEN, "^", 6, 0.45),
    ("E106", VERM, "D", 7, 0.75),
]


def main():
    with open(os.path.join(RES, "fig_certgap_data.json")) as f:
        D = json.load(f)["groups"]
    fig, ax = plt.subplots(figsize=(COLW, 2.2))
    rng = np.random.default_rng(0)
    lo, hi = np.inf, 0.0
    for key, c, m, s, a in GROUPS:
        g = np.asarray(D[key]["gap_rel"], float)
        e = np.asarray(D[key]["eta_rel"], float)
        _, first = np.unique(np.stack([g, e], 1), axis=0, return_index=True)
        first = np.sort(first)
        g, e = g[first], e[first]
        keep = g >= GAP_FLOOR
        g, e = g[keep], e[keep]
        n = len(g)
        if n > SUBSAMPLE:
            idx = rng.choice(n, SUBSAMPLE, replace=False)
            g, e = g[idx], e[idx]
        lo, hi = min(lo, g.min(), e.min()), max(hi, g.max(), e.max())
        ax.scatter(g, e, s=s, marker=m, facecolor=c, edgecolor="none", alpha=a, rasterized=True, zorder=3,
                   label=f"{D[key]['label']} ({n})")
    x0, x1 = 10 ** np.floor(np.log10(lo)), 10 ** np.ceil(np.log10(hi))
    xs = np.array([x0, x1])
    ax.plot(xs, xs, color=BLACK, lw=0.9, zorder=4)
    ax.plot(xs, 2 * xs, color=BLACK, lw=0.8, ls=(0, (4, 2)), zorder=4)
    ax.set_xscale("log")
    ax.set_yscale("log")
    ax.set_xlim(x0, x1)
    ax.set_ylim(x0, x1)
    ax.set_xlabel(r"true gap $\gamma_\varphi\,/\,V_N^0$")
    ax.set_ylabel(r"certificate $\eta\,/\,V_N^0$")
    # inline line labels, rotated to the on-screen slope of y = x
    fig.canvas.draw()
    p0, p1 = ax.transData.transform([(1e-3, 1e-3), (1e-2, 1e-2)])
    ang = np.degrees(np.arctan2(p1[1] - p0[1], p1[0] - p0[0]))
    ax.text(3e-2, 3e-2 / 1.6, "certificate = gap", rotation=ang, rotation_mode="anchor", ha="center", va="center",
            fontsize=6.5, zorder=5)
    ax.text(2.2e-5, 2 * 2.2e-5 * 2.4, r"$\eta = 2\gamma_\varphi$", rotation=ang, rotation_mode="anchor",
            ha="center", va="center", fontsize=6.5, zorder=5)
    leg = ax.legend(loc="lower right", markerscale=1.6, handletextpad=0.3, labelspacing=0.25, borderpad=0.35,
                    handlelength=1.0)
    for h in leg.legend_handles:
        h.set_alpha(1.0)
    fig.savefig(os.path.join(FIG, "fig_certgap.pdf"), bbox_inches="tight", pad_inches=0.015)
    fig.savefig(os.path.join(FIG, "fig_certgap.png"), bbox_inches="tight", pad_inches=0.015, dpi=200)
    plt.close(fig)


if __name__ == "__main__":
    main()
