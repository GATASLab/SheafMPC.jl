"""Write results/setup.json: the scenario and solver parameters of Section VI, read from the experiment sources.

    python3 scripts/resolution/setup_params.py      (from the repository root)
"""
import json, re

E = "scripts/resolution/experiments/"
fleet = open(E + "fleet_dc.jl").read()
flag = open(E + "e26_flagship.jl").read()
tube = open(E + "e62_tube.jl").read()


def const(src, name):
    m = re.search(r"const %s\s*=\s*(?:parse\((?:Float64|Int), get\(ENV, \"[A-Z0-9_]+\", \")?([0-9.e-]+)" % name, src)
    return float(m.group(1))


def weight(src, fn):
    body = src[src.index("function " + fn):]
    body = body[:body.index("\nend")]
    qf = re.search(r"Qf = Matrix\(Diagonal\(\[([0-9., ]+)\]\)\)", body).group(1).split(",")
    return float(qf[0]), float(qf[-1])


qf_pos, qf_vel = weight(fleet, "drone_dc")
qf_pos_car, qf_vel_car = weight(fleet, "car_dc")
assert (qf_pos, qf_vel) == (qf_pos_car, qf_vel_car)
eps = re.search(r'BENCH_SM_EPS", "([0-9.e-]+)"', flag).group(1)
cpus = json.load(open("results/e26_flagship.json"))["cpus"]
out = {
    "experiment": "setup: parameters of Section VI read from fleet_dc.jl, e26_flagship.jl and e62_tube.jl",
    "horizon": int(const(flag, "H26")),
    "h_s": const(flag, "DT26"),
    "umax_drone": const(fleet, "UMAX_DRONE_DC"),
    "umax_car": const(fleet, "UMAX_CAR_DC"),
    "drag_car": const(fleet, "DRAG_CAR_DC"),
    "r_drone": const(fleet, "R_DRONE_DC"),
    "r_car": const(fleet, "R_CAR_DC"),
    "q_position": float(re.search(r"Q = Matrix\(([0-9.]+)I", fleet).group(1)),
    "qf_position": qf_pos,
    "qf_velocity": qf_vel,
    "solver_eps": float(eps),
    "cpus": cpus,
    "tube_qv": const(tube, "QV62"),
    "tube_horizon": int(const(tube, "H62")),
}
json.dump(out, open("results/setup.json", "w"), indent=1)
print(out)
