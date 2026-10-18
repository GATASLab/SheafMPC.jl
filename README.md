# SheafMPC.jl

An operator-splitting conic QP solver for sheaf programs and multi-agent model
predictive control.

    minimize    (1/2) x'Px + q'x + c
    subject to  A x = z,  z in C,

with `C` a product of intervals (equality, one-sided, two-sided rows) and
translated second-order cones (`b_B - A_B x in SOC`, the convention of
Clarabel and of sheaf programs).

## Algorithm

* ADMM of OSQP (Stellato et al. 2020, Algorithm 1) with over-relaxation
  `alpha = 1.6`, per-row penalties (`rho_eq_scale * rho` on equality rows,
  `rho_min` on free rows), adaptive rho with a refactorization only when the
  estimate moves by more than a factor `adaptive_rho_tolerance`, OSQP's
  unscaled termination criteria, and primal and dual infeasibility
  certificates (extended to second-order cones). Second-order cones are handled
  by projection, as in COSMO.
* Modified Ruiz equilibration (OSQP), uniform within each SOC block.
* One quasi-definite KKT matrix `[P + sigma I, A'; A, -R^{-1}]`, ordered and
  factored once in `setup` (QDLDL with AMD, MMD or AMF ordering, or the
  supernodal multifrontal LDLt of CliqueTrees; `linsys = :auto` keeps the
  fastest solve). The iteration allocates nothing.
* Polish (active-set refinement). The equality-constrained QP on the guessed
  active set is solved with a matrix of the same sparsity pattern as the ADMM
  KKT matrix (inactive rows get `-1/delta`, active rows `-delta` on the
  diagonal), so a polish costs one numerical factorization and no symbolic
  work, and nothing at all when the active set is the one factored last time;
  iterative refinement against the exact reduced system gives full accuracy.
  The polished point is accepted only if it meets the termination tolerance
  including the signs of the multipliers. Rejected points get one
  primal-dual active-set correction and then restart ADMM (Moreau
  decomposition of `A x + y / rho`). Polish attempts are also made during the
  iterations once the active-set guess is stable, with exponential back-off.
* Second-order cone blocks on their boundary are polished by Newton's method
  on the boundary manifold `s = tau (1, u)`, `y = eta (1, -u)`: in the basis
  `(e_s, e_y, U)` of the block its linearization is the row block
  `A_B x - N y = b_B` with `N = (1/delta) e_s e_s' + delta e_y e_y' +
  (tau/eta) U U'`, symmetric positive definite, so the polish system stays
  quasi-definite on the same pattern (the (2,2) block of each SOC block is
  stored dense).
* Receding horizon: `update!(solver; q, l, u, b)` changes the data without
  refactoring, `warm_start!` / `warm_start_shifted!` move the previous plan,
  and a warm-started `solve!` first tries the polish on the active set of the
  warm start (with the cached polish factorization if it is the same).

## API

```julia
using SheafMPC
p = ConicQP(P, q, A, l, u)                      # OSQP form, or
p = ConicQP(P, q, A, b, [(:zero, m0), (:nonneg, m1), (:soc, 3), ...])   # b - A x in K
p = sheaf_qp(program)                           # a sheaf program (fine or pushed forward)
s = setup(p; eps_abs = 1e-7, eps_rel = 1e-7)    # keywords override Settings()
info = solve!(s)                                # info.status, info.obj, info.iter, ...
s.xsol, s.ysol, s.zsol                          # unscaled solution
update!(s; q = q2, b = b2)                      # new data, same factorization
warm_start_shifted!(s, xmap, ymap)              # previous plan, shifted
solve!(s)
reset!(s)                                       # next solve is a cold start
```

`sheaf_qp` reads a program by its fields (nodes with `Q, q, c, A, b, cones`,
edges with `tail, head, Ft, Fh, hard, W, b`, stalk `offsets`): node costs and
soft edges go into `P, q, c`, hard edges and node cones become rows (hard
edges first, the row order of the paper's `solve_direct`).

## Tests and benchmarks

    julia --project=. -e 'using Pkg; Pkg.test()'

The tests compare with Clarabel on random QPs and SOCPs, infeasible problems,
the fleet QP of the paper repository's `bench/central`, and fine and pushed
forward sheaf programs of its Resolution module (read only, from
`SHEAFMPC_PAPER`, default `~/Projects/GATAS/mpc-sheaf-pushforward`).

    julia --project=bench -e 'using Pkg; Pkg.develop(path = "."); Pkg.instantiate()'
    julia --project=bench bench/single.jl     # one QP: SheafMPC, OSQP, Clarabel
    julia --project=bench bench/rh.jl         # receding horizon, 30 steps
    julia --project=bench bench/reduced.jl    # fine program vs pushforwards

Results go to `bench/results/`.
