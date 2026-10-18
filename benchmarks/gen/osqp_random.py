"""
osqp_random.py: the random MPC instances of the OSQP benchmark suite
(Stellato et al. 2020; osqp_benchmarks, problem_classes/control.py,
ControlExample.__init__), reproduced statement by statement with numpy's
global RandomState, so that a given (n, seed) gives the instance of the
benchmark suite. Writes the model data; the QP is assembled in Julia exactly
as control.py's _generate_qp_problem assembles it (src/families/mpc.jl).

    python gen/osqp_random.py OUTDIR n1,n2,... seed1,seed2,...
"""
import json, os, sys
import numpy as np
import scipy
import scipy.linalg as sla
import scipy.sparse as spa


def control_example(n, seed=1):
    np.random.seed(seed)
    nx = int(n)
    nu = int(n / 2)
    A = spa.eye(nx) + .1 * spa.random(nx, nx, density=1.0, data_rvs=np.random.randn)
    lambda_values, V = np.linalg.eig(A.todense())
    abs_lambda_values = np.abs(lambda_values)
    for i in range(len(lambda_values)):
        lambda_values[i] = lambda_values[i] if abs_lambda_values[i] < 1 - 1e-02 else \
            lambda_values[i] / (abs_lambda_values[i] + 1e-02)
    A = spa.csc_matrix(V.dot(np.diag(lambda_values)).dot(np.linalg.inv(V)).real)
    B = spa.random(nx, nu, density=1.0, data_rvs=np.random.randn)
    R = .1 * spa.eye(nu)
    ind07 = np.random.rand(nx) < 0.7
    diagQ = np.multiply(np.random.rand(nx), ind07)
    Q = spa.diags(diagQ)
    QN = sla.solve_discrete_are(A.todense(), B.todense(), Q.todense(), R.todense())
    QN = QN.dot(QN.T)
    umin = - 1.0 * np.random.rand(nu)
    umax = -umin
    xmin = -1.0 - np.random.rand(nx)
    xmax = -xmin
    x0 = np.random.rand(nx)
    min_x0 = .5 * xmin
    max_x0 = .5 * xmax
    for i in range(nx):
        x0[i] = min_x0[i] + x0[i] * (max_x0[i] - min_x0[i])
    T = 10
    rows = lambda M: np.asarray(M.todense() if spa.issparse(M) else M).tolist()
    return dict(nx=nx, nu=nu, T=T, seed=seed, A=rows(A), B=rows(B), Qdiag=diagQ.tolist(), QN=rows(QN),
                R=rows(R), umin=umin.tolist(), umax=umax.tolist(), xmin=xmin.tolist(), xmax=xmax.tolist(),
                x0=x0.tolist(), numpy=np.__version__, scipy=scipy.__version__)


if __name__ == "__main__":
    out = sys.argv[1]
    ns = [int(v) for v in sys.argv[2].split(",")]
    seeds = [int(v) for v in sys.argv[3].split(",")]
    os.makedirs(out, exist_ok=True)
    for n in ns:
        for s in seeds:
            with open(os.path.join(out, f"osqprand_n{n}_s{s}.json"), "w") as f:
                json.dump(control_example(n, s), f)
    print("wrote", len(ns) * len(seeds), "instances to", out)
