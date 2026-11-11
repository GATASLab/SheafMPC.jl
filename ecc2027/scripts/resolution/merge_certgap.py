"""Merge the per-sample certificate data behind figures/fig_certgap.pdf into results/fig_certgap_data.json.

    python3 scripts/resolution/merge_certgap.py certgap_extract.json

certgap_extract.json is the output of scripts/resolution/extract_certgap.py on the HPG login node (part files of
E63, E65b, E69, E106 under /blue/fairbanksj/itaykadosh). E112 comes from results/e112_refine_structured.json,
whose "scatter" field already holds the per-sample (gap / J*, eta / J*) pairs of every team arm.

Every sample is stored as gap / V_N^0 and eta / V_N^0 at the measured state of that sample. Nothing is dropped
here; the solver-tolerance cut is applied by the figure script and the numbers generator.

E65b reruns the 256-vehicle second-order-cone instances of E63 with the same seeds and gives identical samples,
so the E63 group takes those from E65b and only the 1000-vehicle cone and 256-vehicle box instances from E63.
"""
import json
import os
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
RES = os.path.join(ROOT, "results")


def pack(samples, keys):
    return {
        "gap_rel": [s["gap"] / s["V"] for s in samples],
        "eta_rel": [s["eta"] / s["V"] for s in samples],
        **{k: [s.get(k) for s in samples] for k in keys},
    }


def main(extract_path):
    X = json.load(open(extract_path))["experiments"]
    out = {
        "description": "per-sample certificate eta (Lemma lem:cert) and true gap of the team plan, both over "
                       "V_N^0 at the measured state; HPG runs only",
        "produced_by": "scripts/resolution/extract_certgap.py on the HPG login node, then scripts/resolution/merge_certgap.py",
        "groups": {},
    }
    e63 = [s for s in X["E63"]["samples"] if not (s["cone"] == "soc" and s["n"] < 300)]
    e63_src = [r for r in X["E63"]["sources"] if "n256_eps0_soc" not in r["path"]]
    out["groups"]["E63"] = {
        "label": "irregular formations",
        "setting": "natural instance, 256 and about 1000 vehicles, cone and box limits, all team choices (E63 and E65b)",
        "sources": X["E65b"]["sources"] + e63_src,
        **pack(X["E65b"]["samples"] + e63, ["arm", "n", "cone", "seed", "step"]),
    }
    out["groups"]["E69"] = {
        "label": "inconsistent references",
        "setting": "natural instance, about 250 vehicles, reference noise sigma > 0, all team choices",
        "sources": X["E69"]["sources"],
        **pack(X["E69"]["samples"], ["arm", "n", "sigma", "seed", "step"]),
    }
    E = json.load(open(os.path.join(RES, "e112_refine_structured.json")))
    pairs = [(k, p) for k, v in E["scatter"].items() for p in v]
    out["groups"]["E112"] = {
        "label": "certified refinement",
        "setting": "planted squads, 256 and 1024 vehicles, every team arm (fixed and refined)",
        "sources": [{"path": "results/e112_refine_structured.json (field scatter, pairs [gap/J*, eta/J*])",
                     "jobs": E["jobs"], "hosts": E["hosts"], "commits": E["commits"]}],
        "gap_rel": [p[0] for _, p in pairs],
        "eta_rel": [p[1] for _, p in pairs],
        "arm": [k for k, _ in pairs],
    }
    out["groups"]["E106"] = {
        "label": "about 4000 vehicles",
        "setting": "natural instance, about 4070 vehicles, 200 ms period, one team per region",
        "sources": X["E106"]["sources"],
        **pack(X["E106"]["samples"], ["arm", "n", "seed", "step"]),
    }
    out["extract_host"] = json.load(open(extract_path))["host_extracted"]
    for g in out["groups"].values():
        g["n_samples"] = len(g["gap_rel"])
    path = os.path.join(RES, "fig_certgap_data.json")
    with open(path, "w") as f:
        json.dump(out, f, indent=1)
    print("wrote", path, {k: g["n_samples"] for k, g in out["groups"].items()})


if __name__ == "__main__":
    main(sys.argv[1])
