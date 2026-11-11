"""Helpers for e114 (acados RTI, team program vs full fleet).

Vehicle models (casadi), formation graphs with an almost equitable partition (AEP),
lifted data (Definition L of theorems.md), the quotient (team) program data of Lemma 2,
and numpy checks of the hypotheses.
"""
import math
import numpy as np
import casadi as ca


# ---------------------------------------------------------------- vehicle models

class Model:
    """One vehicle class: continuous dynamics, positions, box limits, tracking weights."""

    def __init__(self, name, nx, nu, pos_idx, f, lbu, ubu, q, r, q_term):
        self.name, self.nx, self.nu = name, nx, nu
        self.pos_idx = list(pos_idx)          # C = rows of I picking positions
        self.dpos = len(self.pos_idx)
        self.f = f                            # casadi Function (x,u) -> xdot
        self.lbu, self.ubu = np.asarray(lbu, float), np.asarray(ubu, float)
        self.q, self.r, self.q_term = (np.asarray(v, float) for v in (q, r, q_term))


def unicycle(a_max=1.0, w_max=0.8):
    """Acceleration-input unicycle: x = (px, py, theta, v), u = (a, omega).
    xdot does not depend on (px, py), so D = span{e_px, e_py} (H3)."""
    x, u = ca.SX.sym("x", 4), ca.SX.sym("u", 2)
    xdot = ca.vertcat(x[3] * ca.cos(x[2]), x[3] * ca.sin(x[2]), u[1], u[0])
    f = ca.Function("f_uni", [x, u], [xdot])
    return Model("unicycle", 4, 2, [0, 1], f, [-a_max, -w_max], [a_max, w_max],
                 q=[4.0, 4.0, 1.0, 1.0], r=[0.5, 0.5], q_term=[20.0, 20.0, 5.0, 5.0])


def quadrotor(mass=0.5, Tmax_over_mg=1.6, tau_max=0.05, kd=0.1):
    """Quaternion quadrotor: x = (p, v, q=(qw,qx,qy,qz), omega), u = (T, tau_x, tau_y, tau_z),
    T in [0, Tmax], linear drag. xdot does not depend on p, so D = {(dp,0,0,0)} (H3)."""
    g = 9.81
    J = np.diag([2.5e-3, 2.5e-3, 4.5e-3])
    Jinv = np.linalg.inv(J)
    x, u = ca.SX.sym("x", 13), ca.SX.sym("u", 4)
    v, q, w = x[3:6], x[6:10], x[10:13]
    qw, qx, qy, qz = q[0], q[1], q[2], q[3]
    # body z axis in world frame
    zb = ca.vertcat(2 * (qx * qz + qw * qy), 2 * (qy * qz - qw * qx), 1 - 2 * (qx ** 2 + qy ** 2))
    vdot = u[0] / mass * zb - ca.vertcat(0, 0, g) - kd / mass * v
    Om = ca.vertcat(ca.horzcat(0, -w[0], -w[1], -w[2]),
                    ca.horzcat(w[0], 0, w[2], -w[1]),
                    ca.horzcat(w[1], -w[2], 0, w[0]),
                    ca.horzcat(w[2], w[1], -w[0], 0))
    qdot = 0.5 * ca.mtimes(Om, q)
    wdot = ca.mtimes(Jinv, u[1:4] - ca.cross(w, ca.mtimes(J, w)))
    xdot = ca.vertcat(v, vdot, qdot, wdot)
    f = ca.Function("f_quad", [x, u], [xdot])
    Tmax = Tmax_over_mg * mass * g
    m = Model("quadrotor", 13, 4, [0, 1, 2], f, [0.0, -tau_max, -tau_max, -tau_max],
              [Tmax, tau_max, tau_max, tau_max],
              q=[4, 4, 8, 0.5, 0.5, 1, 1, 1, 1, 1, 0.05, 0.05, 0.05],
              r=[0.5, 50.0, 50.0, 50.0],
              q_term=[20, 20, 40, 2, 2, 4, 2, 2, 2, 2, 0.1, 0.1, 0.1])
    m.mass, m.g = mass, g
    return m


def rk4_function(model, h, steps=1):
    """Discrete map x+ = f_h(x,u), explicit RK4 with `steps` substeps (same scheme as acados ERK4)."""
    x, u = ca.SX.sym("x", model.nx), ca.SX.sym("u", model.nu)
    dt = h / steps
    xk = x
    for _ in range(steps):
        k1 = model.f(xk, u)
        k2 = model.f(xk + dt / 2 * k1, u)
        k3 = model.f(xk + dt / 2 * k2, u)
        k4 = model.f(xk + dt * k3, u)
        xk = xk + dt / 6 * (k1 + 2 * k2 + 2 * k3 + k4)
    return ca.Function("rk4", [x, u], [xk])


# ---------------------------------------------------------------- formation

def team_sizes(n, units=(2, 3, 5, 6)):
    """Unequal lane sizes proportional to `units` (sum 16). Requires n % sum(units) == 0."""
    s = sum(units)
    if n % s != 0:
        raise ValueError(f"n={n} must be a multiple of {s}")
    return [n // s * k for k in units]


def build_formation(sizes, dpos, lane_gap=3.0, spacing=1.5, w_cross=1.0, seed=0):
    """Lanes (teams) side by side.
    Intra-lane: a path with weights varying along the lane (irrelevant to AEP, but it kills
    every nontrivial weight-preserving automorphism, so the partition is not an orbit partition).
    Cross-lane (adjacent lanes b, b+1 of sizes m, m'): round-robin biregular multigraph, member a of
    lane b joined to member c = k mod m' for k = a, a+m, ..., weight w0 per occurrence, so every member of b
    has total weight w_cross towards b+1 regardless of the lane sizes (AEP).
    Returns team id per vehicle, offsets Delta (positions), edge list [(i, j, w)]."""
    rng = np.random.default_rng(seed)
    team, local, offs = [], [], []
    for b, m in enumerate(sizes):
        for k in range(m):
            team.append(b)
            local.append(k)
            d = np.zeros(dpos)
            d[0] = -spacing * k
            d[1] = lane_gap * b
            if dpos == 3:
                d[2] = 0.5 * (k % 2)  # small vertical stagger for 3D
            offs.append(d)
    team = np.array(team)
    start = np.concatenate([[0], np.cumsum(sizes)])
    edges = {}

    def add(i, j, w):
        key = (min(i, j), max(i, j))
        edges[key] = edges.get(key, 0.0) + w

    for b, m in enumerate(sizes):
        for k in range(m - 1):
            add(start[b] + k, start[b] + k + 1, 0.5 + 1.5 * rng.random())
    for b in range(len(sizes) - 1):
        m, mp = sizes[b], sizes[b + 1]
        L = m * mp // math.gcd(m, mp)
        w0 = w_cross * m / L  # member of b appears L/m times -> total w_cross
        for k in range(L):
            add(start[b] + k % m, start[b + 1] + k % mp, w0)
    E = [(i, j, w) for (i, j), w in sorted(edges.items())]
    return team, np.array(offs), E


def aep_check(team, E):
    """max over teams b, b' != b of the spread (max - min) of w(i, b') over i in b."""
    nb = team.max() + 1
    n = len(team)
    Wt = np.zeros((n, nb))
    for i, j, w in E:
        Wt[i, team[j]] += w
        Wt[j, team[i]] += w
    spread = 0.0
    for b in range(nb):
        mem = team == b
        for bp in range(nb):
            if bp != b:
                col = Wt[mem, bp]
                spread = max(spread, col.max() - col.min())
    return spread, Wt


def quotient_edges(team, E):
    """Merged inter-team weights W_bb' = sum_{i in b, j in b'} w_ij; intra-team edges vanish."""
    Q = {}
    for i, j, w in E:
        b, bp = team[i], team[j]
        if b == bp:
            continue
        key = (min(b, bp), max(b, bp))
        Q[key] = Q.get(key, 0.0) + w
    return [(b, bp, w) for (b, bp), w in sorted(Q.items())]


def equitable_spread(team, Wt):
    """Spread of w(i, b) over i in b for b' = b (own team). Orbit partitions of weight-preserving
    automorphism groups are equitable (spread 0 for every b' including b); a positive value here
    certifies that the AEP partition is not an orbit partition."""
    out = 0.0
    for b in range(team.max() + 1):
        col = Wt[team == b, b]
        out = max(out, col.max() - col.min())
    return out


# ---------------------------------------------------------------- references

def unicycle_reference(T, h, nteams, model, phase=0.3, seed=1):
    """Team references r_b(t), states (px, py, theta, v) at t = 0, h, ..., T.
    One reference vehicle driven by a(t), omega(t) that exceed the box limits at times
    (sharp S-turns, a hard acceleration and a braking pulse); team b follows it with a time lead
    phase*b, so the team references differ in deviation coordinates and the inter-lane formation
    edges pull against tracking."""
    K = int(round(T / h)) + 1
    lead = int(round(phase / h))
    Kt = K + lead * nteams + 1
    a_max, w_max = model.ubu
    t = np.arange(Kt) * h
    a = np.where((t > 1.0) & (t < 1.6), 1.4 * a_max, 0.0) - np.where((t > 9.0) & (t < 9.6), 1.4 * a_max, 0.0)
    w = 1.15 * w_max * np.sin(2 * np.pi * t / 6.0) * ((t > 2.5) & (t < 14.5))
    f = rk4_function(model, h, steps=4)
    X = np.zeros((Kt, 4))
    X[0] = [0.0, 0.0, 0.0, 1.0]
    for k in range(Kt - 1):
        X[k + 1] = np.array(f(X[k], [a[k], w[k]])).ravel()
    refs = np.stack([X[lead * b: lead * b + K] for b in range(nteams)])  # (nteams, K, 4)
    return refs


def quadrotor_reference(T, h, nteams, model, phase=0.4):
    """Team references: a climb whose vertical acceleration needs T > Tmax, then a drop that
    needs T < 0, plus a lateral sweep; team b leads by phase*b. Hover attitude, zero rates."""
    K = int(round(T / h)) + 1
    lead = int(round(phase / h))
    Kt = K + lead * nteams + 1
    t = np.arange(Kt) * h
    px = 1.0 * t
    py = 1.5 * np.sin(2 * np.pi * t / 5.0)
    pz = 1.0 + 1.2 * (np.tanh(3 * (t - 2.0)) + 1) - 1.6 * (np.tanh(4 * (t - 6.0)) + 1) * 0.6
    P = np.stack([px, py, pz], 1)
    V = np.gradient(P, h, axis=0)
    X = np.zeros((Kt, 13))
    X[:, 0:3], X[:, 3:6], X[:, 6] = P, V, 1.0
    refs = np.stack([X[lead * b: lead * b + K] for b in range(nteams)])
    return refs


# ---------------------------------------------------------------- least-squares cost data

def ls_cost(model, nveh, edges, own_scale, offsets_full):
    """LINEAR_LS data for one program with `nveh` vehicles of `model`.
    Residual y = [x - xref (all vehicles) ; u ; p_i - p_j - o_e (edges)], W diagonal.
    own_scale[k] multiplies vehicle k's tracking weights (|b| in the team program).
    Returns Vx, Vu, W, Vx_e, W_e and a function yref(stage refs) -> vector."""
    nx, nu, d = model.nx, model.nu, model.dpos
    NX, NU, ne = nveh * nx, nveh * nu, len(edges)
    ny = NX + NU + d * ne
    Vx = np.zeros((ny, NX))
    Vu = np.zeros((ny, NU))
    Vx[:NX, :NX] = np.eye(NX)
    Vu[NX:NX + NU, :] = np.eye(NU)
    wdiag = np.concatenate([np.concatenate([s * model.q for s in own_scale]),
                            np.concatenate([s * model.r for s in own_scale]),
                            np.repeat([w for (_, _, w) in edges], d)])
    wdiag_e = np.concatenate([np.concatenate([s * model.q_term for s in own_scale]),
                              np.repeat([w for (_, _, w) in edges], d)])
    otarget = np.zeros(d * ne)
    for e, (i, j, w) in enumerate(edges):
        for c, pi in enumerate(model.pos_idx):
            r = NX + NU + d * e + c
            Vx[r, i * nx + pi] = 1.0
            Vx[r, j * nx + pi] = -1.0
        # (L3) o_e = C Delta_i - C Delta_j
        otarget[d * e:d * e + d] = offsets_full[i][model.pos_idx] - offsets_full[j][model.pos_idx]
    Vx_e = np.concatenate([Vx[:NX], Vx[NX + NU:]], 0)
    return dict(Vx=Vx, Vu=Vu, W=np.diag(wdiag), Vx_e=Vx_e, W_e=np.diag(wdiag_e), ny=ny,
                ny_e=NX + d * ne, otarget=otarget, wdiag=wdiag, wdiag_e=wdiag_e)


def stage_cost(cost, x, u, xref):
    """0.5 (y - yref)' W (y - yref) for one stage (numpy)."""
    y = cost["Vx"] @ x + cost["Vu"] @ u
    yr = np.concatenate([xref, np.zeros(cost["Vu"].shape[1]), cost["otarget"]])
    r = y - yr
    return 0.5 * float(r @ (cost["wdiag"] * r))


def terminal_cost(cost, x, xref):
    y = cost["Vx_e"] @ x
    yr = np.concatenate([xref, cost["otarget"]])
    r = y - yr
    return 0.5 * float(r @ (cost["wdiag_e"] * r))
