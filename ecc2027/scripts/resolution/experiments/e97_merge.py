"""e97_merge.py: the parts of E97 (e97_baselines.jl and env/e55_hpipm_dc.py) -> results/e97_baselines.json.

    python scripts/resolution/experiments/e97_merge.py <primary parts dir> [<cross-check parts dir> ...] [out.json]

The first directory gives the reported numbers; the others are merged the same way under "crosscheck/<dir name>".

Per formation and cone: every arm's median and worst ms per step, its largest deviation from the reference optimum
J_ref (the team program at Clarabel tol 1e-9, broadcast; lossless on these formations) and whether it is accepted
(dev <= 1e-6 at every step). HPIPM plans are scored by e55_hpipm_dc.py's rollout (inputs clipped to the boxes), which
it checks against two Julia-scored plans to 1e-9 before solving. The fastest accepted centralized arm and the speedup
of the team program over it: with the team arm of Table I (clarabel_cond_team) and with the fastest accepted team arm.
"""
import json, os, sys, glob, statistics

TOL = 1e-6


def med(v):
    return statistics.median(v)


def merge(D):
    TOL = 1e-6


    out = dict(experiment="E97 structure-exploiting centralized baselines on the Table I formations (E74 closed loop, same steps), "
                          "dedicated node, tolerance 1e-6", tol=TOL, period_ms=200.0, source=os.path.basename(os.path.abspath(D)),
               note="parts_fb: every arm of a formation in one job, one after another, on one shared rome node (6 cpus allocated, "
                    "arms pinned to 1 or 4 of them); parts_dev: the same, one exclusive hpg-dev node (AMD EPYC Milan, 64 cores) per formation; parts_warm: 31 steps on one pinned core of an exclusive hpg-dev node, the cold first step left out of the timing, Clarabel on the team program only", formations={}, threads4={})
    refs = {}
    for f in sorted(glob.glob(os.path.join(D, "e97_*_N*_t*.json"))):
        r = json.load(open(f))
        v, cone, th = r["variant"], r["cone"], r["threads"]
        arms = {}
        for a, s in r["arms"].items():
            # runs of 10 or more steps (parts_warm): the cold first step is left out of the timing
            if s["nsteps"] >= 10:
                tw = [1e3 * x["t"] for x in s["steps"][1:]]
                s = dict(s, ms_med=med(tw), ms_max=max(tw))
            arms[a] = dict(ms_med=s["ms_med"], ms_max=s["ms_max"], dev_max=s["dev_max"], accepted=s["accepted"], nsteps=s["nsteps"],
                           capped=s["capped"], iters=[x["iters"] for x in s["steps"]], status=[x["status"] for x in s["steps"]],
                           viol_max=max(x["viol"] for x in s["steps"]), ms=[1e3 * x["t"] for x in s["steps"]])
        ent = dict(n=r["n"], teams=r["teams"], vars=r["vars"], build_s=r["build_s"], arms=arms, meta=r["meta"],
                   J_ref=[x["J_ref"] for x in r["ref"]], ref_status=[x["status"] for x in r["ref"]],
                   fine_check=dict(full=r.get("fine_check_full"), team=r.get("fine_check_team")))
        if th == 1:
            out["formations"].setdefault(v, {})[cone] = ent
            refs[(v, cone)] = ent["J_ref"]
        else:
            out["threads4"].setdefault(v, {})[cone] = ent

    for f in sorted(glob.glob(os.path.join(D, "e55_hpipm_*_e97_*.json"))):
        h = json.load(open(f))
        tag = os.path.basename(h["input"]).replace("e55_input_e97_", "").replace(".json", "")
        v = tag.split("_N")[0]
        Jr = refs.get((v, "box"))
        if Jr is None:
            continue
        for run in h["runs"]:
            st = run["steps"]
            devs = [abs(s["J_clip"] - Jr[s["step"]]) / abs(Jr[s["step"]]) for s in st]
            name = f"hpipm_b{run['b']}_" + ("full" if h["program"] == "stacked" else "team")
            a = dict(ms_med=1e3 * med([s["t_wall"] for s in st]), ms_max=1e3 * max(s["t_wall"] for s in st), dev_max=max(devs),
                     accepted=all(d <= TOL for d in devs) and all(s["status"] == "solved" for s in st), nsteps=len(st),
                     iters=[s["iter"] for s in st], status=[s["status"] for s in st], steps=[s["step"] for s in st],
                     viol_max=max(s["input_violation"] for s in st), ms=[1e3 * s["t_wall"] for s in st],
                     ms_qp=[1e3 * s["t_qp"] for s in st], nx=run["nx"], nu=run["nu"], t_build_s=run["t_build"],
                     peak_rss_gb=run["peak_rss_gb"], warm=h["warm"], host=h["host"], job=h["slurm_job"],
                     scorer_check=max(c["rel_diff"] for c in h["scorer_check"]))
            a["ms_per_iter"] = [m / max(i, 1) for m, i in zip(a["ms"], a["iters"])]
            out["formations"].setdefault(v, {}).setdefault("box", {"arms": {}})["arms"][name] = a

    for v, cones in out["formations"].items():
        if "box" in cones and "hpipm_b2_full" not in cones["box"]["arms"]:
            cones["box"]["arms"]["hpipm_b2_full"] = dict(pending=True, accepted=False, note="HPIPM stacked run not finished")
        for cone, ent in cones.items():
            arms = ent["arms"]
            for a, s in arms.items():
                if s.get("pending"):
                    continue
                why = []
                if s["dev_max"] > TOL:
                    why.append(f"objective deviation {s['dev_max']:.1e} > {TOL:g} (solver reported {sorted(set(s['status']))})")
                if not all(str(x).lower() == "solved" for x in s["status"]):
                    why.append(f"status {s['status']}")
                if why:
                    s["reject_reason"] = "; ".join(why)
            ent["host"] = ent.get("meta", {}).get("host", arms.get("hpipm_b2_full", {}).get("host"))
            ent["load"] = ent.get("meta", {}).get("load")
            cen = {a: s for a, s in arms.items() if a.endswith("_full") and s.get("accepted")}
            tm = {a: s for a, s in arms.items() if a.endswith("_team") and s.get("accepted")}
            if not cen:
                continue
            best = min(cen, key=lambda a: cen[a]["ms_med"])
            ent["best_central"] = best
            ent["best_central_ms_med"] = cen[best]["ms_med"]
            ent["best_central_ms_max"] = cen[best]["ms_max"]
            ent["rejected"] = sorted(a for a, s in arms.items() if not s["accepted"])
            if "clarabel_cond_team" in tm:
                ent["speedup_best_central_over_team_clarabel"] = cen[best]["ms_med"] / tm["clarabel_cond_team"]["ms_med"]
            if tm:
                bt = min(tm, key=lambda a: tm[a]["ms_med"])
                ent["best_team"] = bt
                ent["best_team_ms_med"] = tm[bt]["ms_med"]
                ent["speedup_best_central_over_best_team"] = cen[best]["ms_med"] / tm[bt]["ms_med"]
                same = best.replace("_full", "_team")
                if same in tm:
                    ent["speedup_same_solver"] = cen[best]["ms_med"] / tm[same]["ms_med"]
                    ent["same_solver_team"] = same
                    ent["same_solver_team_ms_med"] = tm[same]["ms_med"]

    return out


DIRS = [a for a in sys.argv[1:] if not a.endswith(".json")]
OUT = next((a for a in sys.argv[1:] if a.endswith(".json")), os.path.join(os.path.dirname(__file__), "..", "..", "..", "results", "e97_baselines.json"))
out = merge(DIRS[0])
if len(DIRS) > 1:
    out["crosscheck"] = {os.path.basename(os.path.abspath(d)): merge(d) for d in DIRS[1:]}
os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
with open(OUT, "w") as f:
    json.dump(out, f, indent=1)
print("wrote", os.path.abspath(OUT))
for v, cones in out["formations"].items():
    for cone, ent in cones.items():
        print(f"{v:5s} {cone}: best central {ent.get('best_central')} {ent.get('best_central_ms_med', float('nan')):.1f} ms, "
              f"best team {ent.get('best_team')} {ent.get('best_team_ms_med', float('nan')):.2f} ms, "
              f"speedup {ent.get('speedup_best_central_over_best_team', float('nan')):.0f}, rejected {ent.get('rejected')}")
        for a, s in sorted(ent["arms"].items()):
            if s.get("pending"):
                print(f"    {a:22s} PENDING"); continue
            print(f"    {a:22s} med {s['ms_med']:12.2f} max {s['ms_max']:12.2f} ms  dev {s['dev_max']:.1e}  {'ok' if s['accepted'] else 'REJECTED'}  it {s['iters']}")
