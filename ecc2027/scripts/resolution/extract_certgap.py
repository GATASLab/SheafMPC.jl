# Runs on the HPG login node (light JSON parsing only): pulls the per-sample (eta, gap, V_N^0) triples
# from the part files and prints them as JSON.
#   ssh hpg python3 /blue/fairbanksj/itaykadosh/extract_certgap.py > certgap_extract.json
# Then scripts/resolution/merge_certgap.py merges them with E112 into results/fig_certgap_data.json.
import json, glob, os, hashlib, socket
B = "/blue/fairbanksj/itaykadosh"
def md5(p): return hashlib.md5(open(p, "rb").read()).hexdigest()
out = {"host_extracted": socket.gethostname(), "experiments": {}}

def add(exp, src, meta, samples):
    e = out["experiments"].setdefault(exp, {"sources": [], "samples": []})
    e["sources"].append({"path": src, "md5": md5(src), "job": meta.get("job"), "host": meta.get("host"),
                         "cpu": meta.get("cpu"), "julia": meta.get("julia")})
    e["samples"].extend(samples)

# E69: incoherent references, sigma > 0, all team choices
for p in sorted(glob.glob(B + "/e69/parts/*.json")):
    d = json.load(open(p)); s = []
    for sig, blk in d["sigmas"].items():
        if float(sig) == 0.0: continue
        for arm, c in blk["choices"].items():
            for st in c["steps"]:
                s.append({"eta": st["eta"], "gap": st["gap"], "V": st["Jstar"], "arm": arm,
                          "sigma": float(sig), "seed": d["seed"], "n": d["n"], "step": st["step"]})
    add("E69", p, d["meta"], s)

# E65b and E63: per-step records of every choice
def e63style(exp, pattern):
    for p in sorted(glob.glob(pattern)):
        d = json.load(open(p)); s = []
        for arm, c in d["choices"].items():
            for st in c.get("steps", []):
                if "eta" not in st or st.get("status_team") != "SOLVED" or st.get("status_full") != "SOLVED": continue
                s.append({"eta": st["eta"], "gap": st["gap"], "V": st["Jstar"], "arm": arm,
                          "seed": d["seed"], "n": d["n"], "cone": d["cone"], "step": st["step"]})
        add(exp, p, d["meta"], s)
e63style("E65b", B + "/e65b/parts/*.json")
e63style("E63", B + "/e63/partsg/*.json")

# E106: final overrun run (parts4h), the team arm (one team per region)
for p in sorted(glob.glob(B + "/e106/parts4h/*.json")):
    d = json.load(open(p)); s = []
    for arm, c in d["controllers"].items():
        if not arm.startswith("team_resp"): continue
        for st in c["steps"]:
            ce = st.get("cert")
            if not ce or not ce.get("finite", False): continue
            s.append({"eta": ce["eta"], "gap": ce["gap"], "V": ce["Jstar_u"], "arm": arm,
                      "seed": d["seed"], "n": d["n"], "step": st["step"]})
    add("E106", p, d["meta"], s)
print(json.dumps(out))
