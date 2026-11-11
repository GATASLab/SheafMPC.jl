"""fig_overview.pdf: Fig. 1, the team MPC pipeline (results/overview_fleet.json, key n56_s4).

Drawn by render/gallery/F1_final.py, which lays the figure out from measured ink (titles centred on
their drawings, equal gaps, arrow clearances, card padding). This wrapper fixes the paper's settings:
bold style, ring nodes in panel (c), slate card and arrows, 9.5 pt titles and 8.2 pt secondary text.

    python3 render/fig_overview.py
"""
import os
import runpy
import shutil
import tempfile

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
SETTINGS = {"F1N_STYLE": "bold", "F1_CARD": "#4F6D8A", "F1_ARROW": "#3A5674", "F1_LOOP": "#7D93A8",
            "F1_CARDLW": "0.8", "F1_TFS": "9.5", "F1_SFS": "8.2", "F1_CLFS": "8.2", "F1_CNUM": "#1d1d1d"}

if __name__ == "__main__":
    tmp = tempfile.mkdtemp()
    os.environ.update(SETTINGS)
    os.environ["OUT_DIR"] = tmp
    runpy.run_path(os.path.join(ROOT, "render", "gallery", "F1_final.py"), run_name="__main__")
    for ext in ("pdf", "png"):
        shutil.copy(os.path.join(tmp, "F1F_bold." + ext), os.path.join(ROOT, "figures", "fig_overview." + ext))
    shutil.rmtree(tmp)
