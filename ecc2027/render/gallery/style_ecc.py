"""Shared style for the ECC 2027 figure set (H3c_v2, D3a_v2, D2b_v2, D4b_v2).

Every figure is drawn at printed size: one IEEE column is 3.5 in (252 pt). Figures are saved with a fixed
figsize (no tight bbox), so the PDF is exactly the size that goes into the column.

Type
    TeX Gyre Termes (the ieeeconf body font) with Computer Modern math.
    _v2: axis labels 8 pt, tick labels 7 pt, annotations and direct labels 7 pt.
    large (v3 and the redesigns): axis labels 8.5 pt, ticks 7.5 pt, direct labels 8 pt, reference-line labels 7 pt.

Lines
    data lines 1.0 pt, reference lines (y = x, period, tight) 0.6 pt, spines and ticks 0.5 pt,
    left and bottom spines only, ticks outward 2.5 pt.

Color (Okabe-Ito, one meaning per hue across all figures)
    TEAM      blue        the team program / the teams with local feedback K_c / the large-fleet team runs
    CENTRAL   black       centralized MPC, always black (dashed line or open marker)
    FAIL      vermilion   what breaks: team input alone, bands that are not flat
    ALT       purple      the local alternative: one diffusion step per team (never orange next to vermilion)
    REFINE    green       certified refinement (splitting teams on the certificate)
    IRREG     sky blue    irregular formations (certificate samples)
    INCONS    orange      inconsistent references (certificate samples; never shares a figure with vermilion)
    NEUTRAL   greys       structure: team delimiters, shading, the period
Light hues get a darker twin for text (TEXT[...]) so labels stay readable on white.

Labels
    direct labels next to the data, never a legend box.

    import style_ecc as S; S.apply()
"""
import os

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

COLW = 3.5  # in, one ieeeconf column (252 pt)
OUT = os.environ.get("OUT_DIR", os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "..", "figures")))

FS_LABEL = 8
FS_TICK = 7
FS_ANNOT = 7

LW_DATA = 1.0
LW_REF = 0.6
LW_SPINE = 0.5
DASH = (0, (3, 2))

# Okabe-Ito
BLUE, SKY, GREEN, ORANGE, VERM, PURPLE, BLACK = ("#0072B2", "#56B4E9", "#009E73", "#E69F00", "#D55E00",
                                                  "#CC79A7", "#000000")
TEAM, CENTRAL, FAIL, ALT, REFINE, IRREG, INCONS = BLUE, BLACK, VERM, PURPLE, GREEN, SKY, ORANGE
TEXT = {BLUE: BLUE, SKY: "#2B7FB0", GREEN: "#007A59", ORANGE: "#B77A00", VERM: VERM, PURPLE: "#A8558A",
        BLACK: "#000000"}
INK = "0.25"      # secondary text
SHADE = "0.93"    # background shading
STRUCT = "0.40"   # structural lines


FS_REF = 7  # labels on reference lines (eta = gamma, period)


def apply(large=False):
    """large=True is the print-legible set the author asked for (v3, D2c/D2d, D4c/D4d): axis labels 8.5 pt,
    ticks 7.5 pt, direct labels 8 pt, reference-line labels 7 pt. large=False keeps the _v2 sizes (8/7/7)."""
    global FS_LABEL, FS_TICK, FS_ANNOT, FS_REF
    FS_LABEL, FS_TICK, FS_ANNOT, FS_REF = (8.5, 7.5, 8, 7) if large else (8, 7, 7, 7)
    plt.rcParams.update({
        "font.family": "serif", "font.serif": ["TeX Gyre Termes", "Nimbus Roman", "Times New Roman"],
        "mathtext.fontset": "cm",
        "font.size": FS_ANNOT, "axes.labelsize": FS_LABEL, "axes.titlesize": FS_LABEL,
        "xtick.labelsize": FS_TICK, "ytick.labelsize": FS_TICK,
        "axes.linewidth": LW_SPINE, "axes.edgecolor": "black",
        "axes.spines.top": False, "axes.spines.right": False,
        "axes.labelpad": 2.0,
        "xtick.direction": "out", "ytick.direction": "out",
        "xtick.major.width": LW_SPINE, "ytick.major.width": LW_SPINE,
        "xtick.minor.width": 0.35, "ytick.minor.width": 0.35,
        "xtick.major.size": 2.5, "ytick.major.size": 2.5, "xtick.minor.size": 1.5, "ytick.minor.size": 1.5,
        "xtick.major.pad": 1.5, "ytick.major.pad": 1.5,
        "lines.linewidth": LW_DATA, "axes.grid": False, "legend.frameon": False,
        "savefig.dpi": 300, "pdf.fonttype": 42, "ps.fonttype": 42,
    })


def axes_in(fig, x, y, w, h):
    """Axes placed in inches from the lower left corner of the figure."""
    W, H = fig.get_size_inches()
    return fig.add_axes([x / W, y / H, w / W, h / H])


def save(fig, name):
    """Fixed-size save: the PDF is exactly figsize, the PNG is the same at 200 dpi."""
    fig.savefig(os.path.join(OUT, name + ".pdf"))
    fig.savefig(os.path.join(OUT, name + ".png"), dpi=200)
    plt.close(fig)
