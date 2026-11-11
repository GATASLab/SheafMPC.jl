"""D3a_v3: certificate against true gap plus the ratio strip, print-legible sizes (style_ecc.apply(large=True)).

Axis labels 8.5 pt, ticks 7.5 pt, group labels and medians 8 pt, line labels 7 pt. To fit the larger text in one
column the scatter labels every other decade, the strip is wider and drops its right-hand line labels (the
scatter names both lines), and the strip columns are named under the axis in two staggered rows.

Data and filtering from D3_certificate.load() (results/fig_certgap_data.json; counts and medians asserted against
preamble/numbers_certgap.tex). Printed medians are the macro strings.

    python3 render/gallery/D3a_v3_certificate.py
"""
import os
import sys

import matplotlib.ticker as mt
import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import D3_certificate as D3  # noqa: E402  (loader and asserts only)
import style_ecc as S  # noqa: E402

S.apply(large=True)
# groups in shades of the slate of Fig. 1, so that hue always means "team" in Figs. 1 and 2
if os.environ.get("F3_PAL", "slate") == "muted":   # soft, distinct hues, darker text versions
    SL1, SL2, SL3, SL4 = "#7a9cc6", "#d9a066", "#78b07f", "#3d5a80"
    S.TEXT.update({SL1: "#4f73a0", SL2: "#b07a3c", SL3: "#4c8a55", SL4: "#2c4566"})
else:
    SL1, SL2, SL3, SL4 = "#9fb4c8", "#6d8aa6", "#41617f", "#1f3a55"
    S.TEXT.update({SL1: "#6f879d", SL2: "#516e8a", SL3: "#36526d", SL4: "#1f3a55"})
REF2 = os.environ.get("F3_REF2", S.CENTRAL)   # the eta = 2 gamma line, lighter than eta = gamma
GROUPS = [
    ("E63", SL1, "o", 3.0, 0.45, "Rand", "irregular"),
    ("E69", SL2, "s", 3.0, 0.40, "Incons", "inconsistent"),
    ("E112", SL3, "^", 5.0, 0.60, "Refine", "refinement"),
    ("E106", SL4, "D", 3.5, 0.85, "Big", r"$\approx$4000"),
]


def main():
    data, allr, M = D3.load()
    TW, TH = S.COLW, 2.30
    fig = S.plt.figure(figsize=(TW, TH))
    sq = 1.50
    xb, yb = 0.44, 0.43
    ax = S.axes_in(fig, xb, yb, sq, sq)
    sxl = xb + sq + 0.33
    sxw = TW - sxl - 0.24
    sx = S.axes_in(fig, sxl, yb, sxw, sq)
    rng = np.random.default_rng(0)

    # ---- scatter
    for key, c, m, s, a, pre, _ in GROUPS:
        g, e, r = data[key]
        g, e = D3.sub(rng, g, e)
        ax.scatter(g, e, s=s, marker=m, facecolor=c, edgecolor="none", alpha=a, rasterized=True, zorder=3)
    x0, x1 = 1e-5, 1e0
    xs = np.array([x0, x1])
    ax.plot(xs, xs, color=S.CENTRAL, lw=S.LW_REF + 0.2, zorder=4)
    ax.plot(xs, 2 * xs, color=REF2, lw=S.LW_REF, ls=S.DASH, zorder=4)
    ax.set_xscale("log")
    ax.set_yscale("log")
    ax.set_xlim(x0, x1)
    ax.set_ylim(x0, x1)
    for a in (ax.xaxis, ax.yaxis):
        a.set_major_locator(mt.FixedLocator([1e-4, 1e-2, 1e0]))
        a.set_minor_locator(mt.FixedLocator([1e-5, 1e-3, 1e-1]))
        a.set_minor_formatter(mt.NullFormatter())
    ax.tick_params(which="minor", length=2.5, width=S.LW_SPINE)
    GRID = os.environ.get("F3_GRID", "panel")
    ax.set_axisbelow(True)
    if GRID == "panel":       # tinted plotting area, white major grid
        ax.set_facecolor("#f3f4f6")
        ax.grid(which="major", color="white", lw=0.8, zorder=0)
    elif GRID == "dots":      # fine dotted hairlines at the major ticks only
        ax.grid(which="major", color="#b9bec5", lw=0.4, ls=(0, (0.6, 1.8)), zorder=0)
    ax.set_xlabel(r"true gap $\hat\gamma/V_N^0$")
    ax.set_ylabel(r"certificate $\eta/V_N^0$", labelpad=1)
    ax.text(3e-2, 3e-2 / 4.6, r"$\eta=\hat\gamma$", rotation=45, rotation_mode="anchor", ha="center",
            va="center", fontsize=S.FS_REF)
    ax.text(2.2e-4, 2 * 2.2e-4 * 4.4, r"$\eta=2\hat\gamma$", rotation=45, rotation_mode="anchor", ha="center",
            va="center", fontsize=S.FS_REF, color=REF2)
    # key that does work: name, marker, median ratio, aligned in the empty lower-right triangle
    kx, ky0, dy = 0.47, 0.30, 0.08
    names = {"E63": "irregular", "E69": "inconsistent", "E112": "refinement", "E106": "k-means"}
    for i, (key, c, m, s_, a_, pre, _) in enumerate(GROUPS):
        y = ky0 - i * dy
        ax.scatter([kx + 0.025], [y], transform=ax.transAxes, s=14, marker=m, facecolor=c, edgecolor="none",
                   clip_on=False, zorder=6)
        ax.text(kx + 0.07, y, names[key], transform=ax.transAxes, ha="left", va="center",
                fontsize=S.FS_ANNOT, color=S.TEXT[c])

    # ---- strip: eta / gamma per group, all kept samples
    for i, (key, c, m, s, a, pre, short) in enumerate(GROUPS):
        r = data[key][2]
        jit = rng.uniform(-0.3, 0.3, len(r))
        sx.scatter(i + jit, r, s=1.0, facecolor=c, edgecolor="none", alpha=min(1, a + 0.15), rasterized=True)
        med = np.median(r)
        sx.plot([i - 0.42, i + 0.42], [med, med], color=S.CENTRAL, lw=1.0, solid_capstyle="butt", zorder=5)
        sx.text(i, 3.43, M[f"cnCg{pre}Med"], ha="center", va="bottom", fontsize=S.FS_ANNOT, color=S.TEXT[c])
    sx.axhline(1, color=S.CENTRAL, lw=S.LW_REF + 0.2)
    sx.axhline(2, color=REF2, lw=S.LW_REF, ls=S.DASH)
    sx.set_ylim(0.9, 3.4)
    sx.set_xlim(-0.5, 3.5)
    if os.environ.get("F3_XLAB", "1") == "1":   # name each strip under the axis, staggered
        labs = {"E63": "irregular", "E69": "inconsistent", "E112": "refinement", "E106": "k-means"}
        for i, (key, c, *_r) in enumerate(GROUPS):
            sx.text(i, 0.86 - 0.13 * (i % 2), labs[key], ha="center", va="top", fontsize=S.FS_REF,
                    color=S.TEXT[c], clip_on=False)
    sx.set_xticks([])
    sx.spines["bottom"].set_visible(False)
    sx.set_yticks([1, 2, 3])
    sx.set_axisbelow(True)
    if GRID == "panel":
        sx.set_facecolor("#f3f4f6")
        sx.grid(axis="y", which="major", color="white", lw=0.8, zorder=0)
    elif GRID == "dots":
        sx.grid(axis="y", which="major", color="#b9bec5", lw=0.4, ls=(0, (0.6, 1.8)), zorder=0)
    sx.set_ylabel(r"$\eta/\hat\gamma$", labelpad=1)
    sx.text(1.5, 3.68, r"median $\eta/\hat\gamma$", ha="center", va="bottom", fontsize=S.FS_REF, color=S.INK)
    sx.text(3.6, 1.0, "tight", ha="left", va="center", clip_on=False, fontsize=S.FS_REF, color=S.INK)
    sx.text(3.6, 2.0, r"2$\times$", ha="left", va="center", clip_on=False, fontsize=S.FS_REF, color=REF2)
    S.save(fig, "D3a_v4_certificate" + ("" if GRID == "panel" else "_" + GRID))


if __name__ == "__main__":
    main()
