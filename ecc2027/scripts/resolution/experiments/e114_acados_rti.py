"""e114: nonlinear team MPC with acados real-time iterations, team program vs full fleet.

README
------
Tests Theorem B / Corollary C2 of ~/Downloads/team_mpc_theory/theorems.md with an off-the-shelf
NMPC code (acados SQP_RTI, Gauss-Newton Hessian). For vehicles with translation-invariant dynamics
f(x + Delta, u) = f(x, u) + Delta, displacement formation costs, an almost equitable partition (AEP)
and lifted data (members track offset copies of their team reference, edge targets are offset
differences, start in formation), Gauss-Newton RTI on the full fleet OCP (P) started from a lifted
guess applies exactly the lifted inputs of RTI on the team OCP (Q) (one vehicle per team, own cost
weight |b|, merged inter-team weights W_bb' = sum w_ij, intra-team edges dropped).

What the script does
  1. Builds a lane formation: 4 teams with unequal sizes n/16*(2,3,5,6), random intra-lane path
     weights, round-robin biregular cross-lane edges (AEP, but not equitable, hence not an orbit
     partition). Team references are one aggressive reference trajectory (a, omega beyond the box)
     with a different time lead per lane, so inter-lane edges pull against tracking.
  2. Checks the hypotheses numerically: translation residual of the ERK4 map, AEP spread,
     equitable spread (not-orbit certificate), lifted data (L2)-(L4), quotient identity of Lemma 2.
  3. Builds two acados OCPs with identical options: SQP_RTI, GAUSS_NEWTON, LINEAR_LS cost, box limits
     on u, PARTIAL_CONDENSING_HPIPM (mode ROBUST, qp_tol 1e-14) by default. Dynamics: the classical
     RK4 (ERK4) step, one step per interval, given to acados as DISCRETE dynamics mapped over
     vehicles (--dyn rk4disc, compact code, sparse Jacobian); --dyn erk uses acados' own ERK
     integrator (4 stages, 1 step), the same scheme, but its generated VDE code grows like n^2.
  4. Warm guess: globalized GN-SQP (merit backtracking) on the team program at the initial state,
     lifted to the fleet. Closed loop with separate preparation / feedback phases (rti_phase 1/2),
     guess shifted by one sample, plant integrated with RK4 at h/10 (fleet plant for (P), team plant
     for (Q)). Reports max |u_fleet - lift(u_team)|, the input spread inside teams, active-limit
     counts, wall and acados timings, QP iteration counts and the fleet/team ratios.
  5. Converse: one cross-lane weight scaled by --perturb-factor (AEP broken; the team program uses
     the new merged weights). Reports the first-step input split inside the two affected teams and
     the closed-loop cost gap (fleet RTI vs lifted team RTI, both evaluated in the fleet cost).
  6. Cold start (x0 held, rest input; itself lifted) vs the warm lifted start for fleet RTI.
  Each invocation adds runs[label] to the --out JSON (label defaults to model_n_qpsolver).

Gotcha: FULL_CONDENSING_QPOASES returns status 0 even when it stops at qp_iter_max (nWSR) with a
wrong working set; at n = 16 with qp_iter_max 200 that gave |du| = 2e-2. Use qp_iter_max >= 5000.

Run (laptop):
  export ACADOS_SOURCE_DIR=~/tools/acados LD_LIBRARY_PATH=~/tools/acados/lib:$LD_LIBRARY_PATH
  python e114_acados_rti.py --model unicycle --n 64 --horizon 20 --steps 300
  python e114_acados_rti.py --n 16 --steps 100 --qp-solver FULL_CONDENSING_QPOASES --qp-iter-max 5000 \
      --skip-cold --skip-converse
  python e114_acados_rti.py --model quadrotor --n 16 --steps 200
Cluster: same file, e.g. --n 256 --build-dir $TMPDIR/e114. The script re-execs itself with
LD_LIBRARY_PATH set if ACADOS_SOURCE_DIR/lib is missing from it. Note that acados stores dense
stage matrices, so the fleet QP costs O(N (n nx)^3) per IPM iteration; n = 1024 unicycles means
4096-dimensional dense stages.
"""
import argparse
import json
import os
import sys
import time

import numpy as np

ACADOS_DIR = os.environ.get("ACADOS_SOURCE_DIR", os.path.expanduser("~/tools/acados"))
if os.path.join(ACADOS_DIR, "lib") not in os.environ.get("LD_LIBRARY_PATH", "").split(":"):
    env = dict(os.environ)
    env["ACADOS_SOURCE_DIR"] = ACADOS_DIR
    env["LD_LIBRARY_PATH"] = os.path.join(ACADOS_DIR, "lib") + ":" + env.get("LD_LIBRARY_PATH", "")
    os.execve(sys.executable, [sys.executable] + sys.argv, env)

import casadi as ca  # noqa: E402
from acados_template import AcadosModel, AcadosOcp, AcadosOcpSolver  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import e114_models as M  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_OUT = os.path.normpath(os.path.join(HERE, "..", "..", "..", "results", "e114_acados_rti.json"))


# ---------------------------------------------------------------- acados OCP

def build_solver(name, model, nveh, cost, N, h, args, sqp=False):
    ocp = AcadosOcp()
    am = AcadosModel()
    am.name = name
    if args.dyn == "erk":  # acados ERK (4 stages, 1 step); generated VDE code grows like n^2
        xs = ca.SX.sym("x", nveh * model.nx)
        us = ca.SX.sym("u", nveh * model.nu)
        am.f_expl_expr = ca.vertcat(*[model.f(xs[k * model.nx:(k + 1) * model.nx],
                                              us[k * model.nu:(k + 1) * model.nu]) for k in range(nveh)])
    else:  # same RK4 step as DISCRETE dynamics, mapped over vehicles: O(1) code, sparse Jacobian
        xs = ca.MX.sym("x", nveh * model.nx)
        us = ca.MX.sym("u", nveh * model.nu)
        fmap = M.rk4_function(model, h, 1).map(nveh)
        am.disc_dyn_expr = ca.reshape(fmap(ca.reshape(xs, model.nx, nveh), ca.reshape(us, model.nu, nveh)), -1, 1)
    am.x, am.u = xs, us
    ocp.model = am
    ocp.solver_options.N_horizon = N
    ocp.solver_options.tf = N * h
    ocp.cost.cost_type = "LINEAR_LS"
    ocp.cost.cost_type_e = "LINEAR_LS"
    ocp.cost.Vx, ocp.cost.Vu, ocp.cost.W = cost["Vx"], cost["Vu"], cost["W"]
    ocp.cost.Vx_e, ocp.cost.W_e = cost["Vx_e"], cost["W_e"]
    ocp.cost.yref = np.zeros(cost["ny"])
    ocp.cost.yref_e = np.zeros(cost["ny_e"])
    ocp.constraints.x0 = np.zeros(nveh * model.nx)
    ocp.constraints.idxbu = np.arange(nveh * model.nu)
    ocp.constraints.lbu = np.tile(model.lbu, nveh)
    ocp.constraints.ubu = np.tile(model.ubu, nveh)
    so = ocp.solver_options
    so.nlp_solver_type = "SQP_RTI"
    so.hessian_approx = "GAUSS_NEWTON"
    if args.dyn == "erk":
        so.integrator_type = "ERK"
        so.sim_method_num_stages = 4
        so.sim_method_num_steps = 1
    else:
        so.integrator_type = "DISCRETE"
    so.qp_solver = args.qp_solver
    if "HPIPM" in args.qp_solver:
        so.qp_solver_cond_N = N
        so.hpipm_mode = args.hpipm_mode
    so.qp_solver_iter_max = args.qp_iter_max
    so.qp_tol = args.qp_tol
    so.print_level = 0
    if sqp:  # globalized SQP, used only to compute the team warm guess
        so.nlp_solver_type = "SQP"
        so.globalization = "MERIT_BACKTRACKING"
        so.nlp_solver_max_iter = 200
        so.nlp_solver_tol_stat = 1e-10
        so.nlp_solver_tol_eq = 1e-10
        so.nlp_solver_tol_ineq = 1e-10
        so.nlp_solver_tol_comp = 1e-10
    ocp.code_gen_options.code_export_directory = os.path.join(args.build_dir, "c_" + name)
    ocp.code_gen_options.json_file = name + ".json"
    t0 = time.perf_counter()
    solver = AcadosOcpSolver(ocp, verbose=False)
    return solver, time.perf_counter() - t0


def set_W(solver, cost, N):
    for k in range(N):
        solver.cost_set(k, "W", cost["W"])
    solver.cost_set(N, "W", cost["W_e"])


def set_refs(solver, cost, xref_fn, s, N):
    nu_all = cost["Vu"].shape[1]
    for k in range(N):
        solver.set(k, "yref", np.concatenate([xref_fn(s + k), np.zeros(nu_all), cost["otarget"]]))
    solver.set(N, "yref", np.concatenate([xref_fn(s + N), cost["otarget"]]))


def set_guess(solver, X, U, N):
    for k in range(N + 1):
        solver.set(k, "x", X[k])
    for k in range(N):
        solver.set(k, "u", U[k])


def get_guess(solver, N):
    X = np.array([solver.get(k, "x") for k in range(N + 1)])
    U = np.array([solver.get(k, "u") for k in range(N)])
    return X, U


def converge_at_x0(solver, cost, xref_fn, x0, X, U, N):
    """Globalized GN-SQP (merit backtracking) on the team program at the initial state."""
    set_guess(solver, X, U, N)
    set_refs(solver, cost, xref_fn, 0, N)
    solver.set(0, "lbx", x0)
    solver.set(0, "ubx", x0)
    st = solver.solve()
    info = dict(status=int(st), sqp_iter=int(solver.get_stats("sqp_iter")),
                kkt_residuals=[float(v) for v in solver.get_residuals()])
    return get_guess(solver, N) + (info,)


def closed_loop(solver, cost, model, nveh, xref_fn, x0, X, U, N, h, steps, plant):
    """RTI closed loop: preparation, x0 embedding, feedback, apply u0, shift."""
    set_guess(solver, X, U, N)
    x = x0.copy()
    nx, nu = model.nx, model.nu
    Xs, Us = [x.copy()], []
    tprep, tfb, aprep, afb, status, qpit = [], [], [], [], [], []
    for s in range(steps):
        set_refs(solver, cost, xref_fn, s, N)
        solver.options_set("rti_phase", 1)
        t0 = time.perf_counter()
        solver.solve()
        t1 = time.perf_counter()
        aprep.append(solver.get_stats("time_tot"))
        solver.set(0, "lbx", x)
        solver.set(0, "ubx", x)
        solver.options_set("rti_phase", 2)
        t2 = time.perf_counter()
        st = solver.solve()
        t3 = time.perf_counter()
        afb.append(solver.get_stats("time_tot"))
        qpit.append(int(np.sum(solver.get_stats("qp_iter"))))
        status.append(int(st))
        tprep.append(t1 - t0)
        tfb.append(t3 - t2)
        u = np.array(solver.get(0, "u"))
        Us.append(u.copy())
        xm = np.array(plant(x.reshape(nveh, nx).T, u.reshape(nveh, nu).T))
        x = xm.T.ravel()
        Xs.append(x.copy())
        # shift
        Xg, Ug = get_guess(solver, N)
        Xg = np.vstack([Xg[1:], Xg[-1:]])
        Ug = np.vstack([Ug[1:], Ug[-1:]])
        set_guess(solver, Xg, Ug, N)
    Xs, Us = np.array(Xs), np.array(Us)
    J = sum(M.stage_cost(cost, Xs[s], Us[s], xref_fn(s)) for s in range(steps))
    return dict(X=Xs, U=Us, J=J, tprep=np.array(tprep), tfb=np.array(tfb),
                aprep=np.array(aprep), afb=np.array(afb), status=status, qp_iter=np.array(qpit))


def tstats(a):
    a = np.asarray(a) * 1e3
    return dict(mean_ms=float(a.mean()), median_ms=float(np.median(a)), max_ms=float(a.max()))


# ---------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="unicycle", choices=["unicycle", "quadrotor"])
    ap.add_argument("--n", type=int, default=64)
    ap.add_argument("--horizon", type=int, default=20)
    ap.add_argument("--steps", type=int, default=300)
    ap.add_argument("--h", type=float, default=0.05)
    ap.add_argument("--dyn", default="rk4disc", choices=["rk4disc", "erk"],
                    help="rk4disc: classical RK4 step as acados DISCRETE dynamics (mapped, compact code); "
                         "erk: acados ERK integrator, 4 stages, 1 step (identical scheme, n^2 code size)")
    ap.add_argument("--plant-substeps", type=int, default=10)
    ap.add_argument("--qp-solver", default="PARTIAL_CONDENSING_HPIPM")
    ap.add_argument("--hpipm-mode", default="ROBUST")
    ap.add_argument("--qp-tol", type=float, default=1e-14)
    ap.add_argument("--qp-iter-max", type=int, default=500)
    ap.add_argument("--converse-steps", type=int, default=100)
    ap.add_argument("--perturb-factor", type=float, default=4.0)
    ap.add_argument("--cold-steps", type=int, default=60)
    ap.add_argument("--skip-converse", action="store_true")
    ap.add_argument("--skip-cold", action="store_true")
    ap.add_argument("--build-dir", default=os.path.join(os.environ.get("TMPDIR", "/tmp"), "e114_acados_build"))
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--label", default=None, help="key under runs{} in --out (default model_n_qp)")
    args = ap.parse_args()
    os.makedirs(args.build_dir, exist_ok=True)
    tstart = time.perf_counter()

    N, h = args.horizon, args.h
    model = M.unicycle() if args.model == "unicycle" else M.quadrotor()
    nx, nu, d = model.nx, model.nu, model.dpos
    sizes = M.team_sizes(args.n)
    nb = len(sizes)
    team, offs, E = M.build_formation(sizes, d)
    n = len(team)
    Dfull = np.zeros((n, nx))
    Dfull[:, model.pos_idx] = offs
    T = (args.steps + N + 1) * h
    if args.model == "unicycle":
        refs = M.unicycle_reference(T, h, nb, model)
    else:
        refs = M.quadrotor_reference(T, h, nb, model)
    # initial team states: off the reference (lateral error, slower)
    y0 = refs[:, 0, :].copy()
    for b in range(nb):
        if args.model == "unicycle":
            y0[b, 1] += 0.3 * (b - 1.5)
            y0[b, 3] *= 0.8
        else:
            y0[b, 2] -= 0.3 * b
    x0 = (y0[team] + Dfull).ravel()                 # (L4)
    xref_P = lambda s: (refs[team, s] + Dfull).ravel()   # (L2) member i tracks r_b + Delta_i
    xref_Q = lambda s: refs[:, s].ravel()

    def programs(Elist):
        cP = M.ls_cost(model, n, Elist, np.ones(n), Dfull)
        EQ = M.quotient_edges(team, Elist)
        cQ = M.ls_cost(model, nb, EQ, np.array(sizes, float), np.zeros((nb, nx)))
        return cP, cQ, EQ

    costP, costQ, EQ = programs(E)

    # ---------------- hypothesis checks
    rng = np.random.default_rng(7)
    fh = M.rk4_function(model, h, 1)
    fplant1 = M.rk4_function(model, h, args.plant_substeps)
    tr_res = 0.0
    for _ in range(200):
        xx = rng.normal(size=nx) * 2
        if args.model == "quadrotor":
            xx[6:10] /= np.linalg.norm(xx[6:10])
        uu = rng.uniform(model.lbu, model.ubu)
        Dl = np.zeros(nx)
        Dl[model.pos_idx] = rng.normal(size=d) * 50
        for f in (fh, fplant1):
            r = np.array(f(xx + Dl, uu)).ravel() - np.array(f(xx, uu)).ravel() - Dl
            tr_res = max(tr_res, float(np.abs(r).max()))
    aep_spread, Wt = M.aep_check(team, E)
    eq_spread = M.equitable_spread(team, Wt)
    L3 = max(float(np.abs(costP["otarget"][d * e:d * e + d] - (offs[i] - offs[j])).max())
             for e, (i, j, w) in enumerate(E))
    L2 = max(float(np.abs(xref_P(s).reshape(n, nx) - Dfull - refs[team, s]).max()) for s in range(0, args.steps, 10))
    L4 = float(np.abs(x0.reshape(n, nx) - Dfull - y0[team]).max())
    # Lemma 2: J_P(iota zeta) = J_Q(zeta) for a random team trajectory
    Yr = rng.normal(size=(N + 1, nb * nx))
    Ur = rng.normal(size=(N, nb * nu))
    lift = lambda Y: (Y.reshape(-1, nb, nx)[:, team] + Dfull).reshape(Y.shape[0], -1)
    liftu = lambda Uq: Uq.reshape(-1, nb, nu)[:, team].reshape(Uq.shape[0], -1)
    JP = sum(M.stage_cost(costP, lift(Yr)[k], liftu(Ur)[k], xref_P(k)) for k in range(N)) + \
        M.terminal_cost(costP, lift(Yr)[N], xref_P(N))
    JQ = sum(M.stage_cost(costQ, Yr[k], Ur[k], xref_Q(k)) for k in range(N)) + M.terminal_cost(costQ, Yr[N], xref_Q(N))
    hyp = dict(translation_residual=tr_res, aep_spread=aep_spread, equitable_spread_not_orbit=eq_spread,
               L2_ref_residual=L2, L3_target_residual=L3, L4_formation_residual=L4,
               quotient_identity_rel=abs(JP - JQ) / abs(JP), min_input_weight=float(model.r.min()),
               gn_qp_unique="R > 0 and LINEAR_LS cost: GN QP strictly convex in u (Theorem B(1))")
    print("hypotheses:", json.dumps(hyp, indent=1))

    # ---------------- solvers
    tag = f"{args.model}_n{n}_N{N}_{args.dyn}_{args.qp_solver[:4]}"
    solP, tbP = build_solver(f"e114P_{tag}", model, n, costP, N, h, args)
    solQ, tbQ = build_solver(f"e114Q_{tag}", model, nb, costQ, N, h, args)
    solQs, _ = build_solver(f"e114Qsqp_{tag}", model, nb, costQ, N, h, args, sqp=True)
    print(f"build: fleet {tbP:.1f}s team {tbQ:.1f}s")
    plantP = M.rk4_function(model, h, args.plant_substeps).map(n)
    plantQ = M.rk4_function(model, h, args.plant_substeps).map(nb)

    def cold_guess(x0v, nveh):
        u_rest = np.zeros(nu)
        if args.model == "quadrotor":
            u_rest[0] = model.mass * model.g
        return np.tile(x0v, (N + 1, 1)), np.tile(np.tile(u_rest, nveh), (N, 1))

    def warm_team(cQ):
        Xc, Uc = cold_guess(y0.ravel(), nb)
        set_W(solQs, cQ, N)
        Yw, Uw, hist = converge_at_x0(solQs, cQ, xref_Q, y0.ravel(), Xc, Uc, N)
        return Yw, Uw, hist

    def compare(rP, rQ, steps):
        Ul = liftu(rQ["U"])
        du = np.abs(rP["U"] - Ul)
        Xl = lift(rQ["X"])
        lo, hi = np.tile(model.lbu, n), np.tile(model.ubu, n)
        tol = 1e-6 * np.maximum(1, np.abs(hi))
        act = (np.abs(rP["U"] - lo) < tol) | (np.abs(rP["U"] - hi) < tol)
        uq = rQ["U"]
        loq, hiq = np.tile(model.lbu, nb), np.tile(model.ubu, nb)
        tolq = 1e-6 * np.maximum(1, np.abs(hiq))
        actq = (np.abs(uq - loq) < tolq) | (np.abs(uq - hiq) < tolq)
        # inside-team spread of fleet inputs
        Ur = rP["U"].reshape(steps, n, nu)
        spread = np.zeros(steps)
        for b in range(nb):
            spread = np.maximum(spread, (Ur[:, team == b].max(1) - Ur[:, team == b].min(1)).max(1))
        JQl = sum(M.stage_cost(costP_cur[0], Xl[s], Ul[s], xref_P(s)) for s in range(steps))
        return dict(max_du=float(du.max()), max_du_first_step=float(du[0].max()),
                    du_per_step_max=[float(v) for v in du.max(1)],
                    max_state_gap=float(np.abs(rP["X"] - Xl).max()),
                    team_input_spread_first=float(spread[0]), team_input_spread_max=float(spread.max()),
                    steps_with_active_limit_fleet=int(act.any(1).sum()),
                    steps_with_active_limit_team=int(actq.any(1).sum()),
                    active_entries_fleet=int(act.sum()),
                    J_fleet=float(rP["J"]), J_lifted_team=float(JQl),
                    J_rel_gap=float((JQl - rP["J"]) / abs(rP["J"])),
                    status_nonzero_fleet=int(sum(1 for s_ in rP["status"] if s_ != 0)),
                    status_nonzero_team=int(sum(1 for s_ in rQ["status"] if s_ != 0)))

    def timing(rP, rQ):
        return dict(prep_fleet=tstats(rP["tprep"]), fb_fleet=tstats(rP["tfb"]),
                    prep_team=tstats(rQ["tprep"]), fb_team=tstats(rQ["tfb"]),
                    acados_prep_fleet=tstats(rP["aprep"]), acados_fb_fleet=tstats(rP["afb"]),
                    acados_prep_team=tstats(rQ["aprep"]), acados_fb_team=tstats(rQ["afb"]),
                    qp_iter_fleet=dict(mean=float(rP["qp_iter"].mean()), max=int(rP["qp_iter"].max())),
                    qp_iter_team=dict(mean=float(rQ["qp_iter"].mean()), max=int(rQ["qp_iter"].max())),
                    ratio_prep_median=float(np.median(rP["tprep"]) / np.median(rQ["tprep"])),
                    ratio_fb_median=float(np.median(rP["tfb"]) / np.median(rQ["tfb"])),
                    ratio_total_median=float(np.median(rP["tprep"] + rP["tfb"]) / np.median(rQ["tprep"] + rQ["tfb"])))

    out = dict(experiment="e114_acados_rti", model=args.model, n=n, teams=nb, team_sizes=sizes,
               edges=len(E), quotient_edges=[(int(b), int(c), float(w)) for b, c, w in EQ],
               horizon=N, h=h, steps=args.steps, plant="RK4, %d substeps per sample" % args.plant_substeps,
               acados=dict(nlp_solver="SQP_RTI", hessian="GAUSS_NEWTON", integrator=("acados ERK, 4 stages, 1 step" if args.dyn == "erk" else
                                                   "classical RK4 (ERK4), 1 step/interval, as DISCRETE dynamics"),
                           qp_solver=args.qp_solver, hpipm_mode=args.hpipm_mode if 'HPIPM' in args.qp_solver else None, qp_tol=args.qp_tol,
                           qp_iter_max=args.qp_iter_max, cost="LINEAR_LS", constraints="box on u",
                           commit=open(os.path.join(ACADOS_DIR, "lib", "git_commit_hash")).read().strip()
                           if os.path.exists(os.path.join(ACADOS_DIR, "lib", "git_commit_hash")) else None),
               limits=dict(lbu=model.lbu.tolist(), ubu=model.ubu.tolist()),
               build_seconds=dict(fleet=tbP, team=tbQ), hypotheses=hyp)

    # ---------------- AEP closed loop
    costP_cur = [costP]
    Yw, Uw, hist = warm_team(costQ)
    XwP, UwP = lift(Yw), liftu(Uw)
    rQ = closed_loop(solQ, costQ, model, nb, xref_Q, y0.ravel(), Yw, Uw, N, h, args.steps, plantQ)
    rP = closed_loop(solP, costP, model, n, xref_P, x0, XwP, UwP, N, h, args.steps, plantP)
    out["aep"] = compare(rP, rQ, args.steps)
    out["aep"]["warm_start_team_sqp"] = hist
    out["aep"]["timing"] = timing(rP, rQ)
    print("AEP:", {k: v for k, v in out["aep"].items() if k not in ("du_per_step_max", "timing")})
    print("timing:", out["aep"]["timing"]["ratio_total_median"])

    # ---------------- cold vs warm (fleet)
    if not args.skip_cold:
        cs = min(args.cold_steps, args.steps)
        XcP, UcP = cold_guess(x0, n)
        XcQ, UcQ = cold_guess(y0.ravel(), nb)
        rPc = closed_loop(solP, costP, model, n, xref_P, x0, XcP, UcP, N, h, cs, plantP)
        rQc = closed_loop(solQ, costQ, model, nb, xref_Q, y0.ravel(), XcQ, UcQ, N, h, cs, plantQ)
        Jw = sum(M.stage_cost(costP, rP["X"][s], rP["U"][s], xref_P(s)) for s in range(cs))
        out["cold_vs_warm"] = dict(
            steps=cs, J_fleet_warm=float(Jw), J_fleet_cold=float(rPc["J"]),
            J_rel_increase_cold=float((rPc["J"] - Jw) / Jw),
            max_du_cold_vs_warm=float(np.abs(rPc["U"] - rP["U"][:cs]).max()),
            du_cold_vs_warm_first5=[float(v) for v in np.abs(rPc["U"] - rP["U"][:cs]).max(1)[:5]],
            cold_fleet_vs_cold_team_max_du=float(np.abs(rPc["U"] - liftu(rQc["U"])).max()),
            note="the cold guess (x0 held, rest input) is itself lifted, so cold fleet and cold team also coincide")
        print("cold:", out["cold_vs_warm"])

    # ---------------- converse: break AEP with one cross-lane weight
    if not args.skip_converse:
        cross = [k for k, (i, j, w) in enumerate(E) if team[i] != team[j] and team[i] == 1]
        kpert = cross[0]
        i_, j_, w_ = E[kpert]
        E2 = list(E)
        E2[kpert] = (i_, j_, w_ * args.perturb_factor)
        costP2, costQ2, EQ2 = programs(E2)
        aep2, _ = M.aep_check(team, E2)
        set_W(solP, costP2, N)
        set_W(solQ, costQ2, N)
        costP_cur[0] = costP2
        # acados LINEAR_LS recomputes its Hessian after a runtime W change (W_changed flag)
        Yw2, Uw2, hist2 = warm_team(costQ2)
        cs = min(args.converse_steps, args.steps)
        rQ2 = closed_loop(solQ, costQ2, model, nb, xref_Q, y0.ravel(), Yw2, Uw2, N, h, cs, plantQ)
        rP2 = closed_loop(solP, costP2, model, n, xref_P, x0, lift(Yw2), liftu(Uw2), N, h, cs, plantP)
        c2 = compare(rP2, rQ2, cs)
        U0 = rP2["U"][0].reshape(n, nu)
        split = {}
        for b in sorted({int(team[i_]), int(team[j_])}):
            mem = np.where(team == b)[0]
            split[f"team{b}"] = dict(max_minus_min=[float(v) for v in (U0[mem].max(0) - U0[mem].min(0))],
                                     perturbed_member_u0=U0[i_ if team[i_] == b else j_].tolist(),
                                     lifted_team_u0=rQ2["U"][0].reshape(nb, nu)[b].tolist())
        c2.update(perturbed_edge=[int(i_), int(j_)], weight_from=float(w_), weight_to=float(w_ * args.perturb_factor),
                  aep_spread=float(aep2), warm_start_team_sqp=hist2, steps=cs, first_step_split=split,
                  first_step_active_entries=int(((np.abs(rP2["U"][0] - np.tile(model.lbu, n)) < 1e-6) |
                                                 (np.abs(rP2["U"][0] - np.tile(model.ubu, n)) < 1e-6)).sum()))
        c2.pop("du_per_step_max")
        out["converse_non_aep"] = c2
        print("converse:", c2)

    out["runtime_seconds"] = time.perf_counter() - tstart
    import platform
    import socket
    out["meta"] = {"host": socket.gethostname(), "job": os.environ.get("SLURM_JOB_ID", ""),
                   "array_task": os.environ.get("SLURM_ARRAY_TASK_ID", ""), "partition": os.environ.get("SLURM_JOB_PARTITION", ""),
                   "cpu": platform.processor() or platform.machine(), "python": platform.python_version()}
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    label = args.label or f"{args.model}_n{n}_{args.qp_solver}"
    allr = {"experiment": "e114_acados_rti", "runs": {}}
    if os.path.exists(args.out):
        try:
            allr = json.load(open(args.out))
        except (OSError, ValueError):
            pass
    allr.setdefault("runs", {})[label] = out
    with open(args.out, "w") as fh_:
        json.dump(allr, fh_, indent=1)
    print("wrote", args.out, f"({out['runtime_seconds']:.1f}s)")


if __name__ == "__main__":
    main()
