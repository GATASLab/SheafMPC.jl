# SheafMPC.jl

The open-source companion of "Real-Time Team MPC of Large Fleets with Certified
Optimality Gaps by Sheaf Pushforward" (Kadosh, Samuelson and Fairbanks).

Model predictive control of a fleet solves, at every sampling instant, one
program whose size grows with the number of agents times the horizon. The
package poses it as a program on a cellular sheaf over the time-expanded
graph (formation preferences are soft edges, dynamics are hard edges) and
reduces it by sheaf pushforward along a quotient of that graph:

* in time, blocks of instants give partial or full condensing, which is exact;
* over agents, teams give reduced-order models: each team is one agent
  confined to its agreement subspace, and every lifted plan is one each
  vehicle can execute;
* reductions compose (teams of teams) and the two kinds commute;
* the optimality gap of a reduction is bounded from the reduced solve (above)
  and the fine solve (below), and for quadratic programs a gap kernel gives the
  gap of every team structure at once, which drives a team selector;
* a receding-horizon controller keeps the fibers, the reduced QP's structure
  and every factorization across steps, so a step costs a few sparse products
  plus a warm solve;
* distributed MPC by consensus ADMM runs over agents or over teams of the
  pushforward, each agent or team solving its own small QP.

The solver underneath is an ADMM conic QP solver for sheaf programs (below).

## Example

```julia
using SheafMPC

sc = GridScenario(rows = 8, cols = 8, H = 10, coherence = :agents)   # the paper's grid fleet
fl = fleet(sc)                                    # 64 agents, quadrotors and ground vehicles
refs, term = references(sc, 0.0)                  # tracking references over the horizon
fp = FleetProgram(fl; x0 = formation_start(sc), references = refs, terminal = term)

fine = solve(fp)                                  # the fine MPC program
R = reduce(fp, Teams(row_teams(sc)) ⊠ partial_condensing(5))  # rows as teams, blocks of 5 instants
red = solve(R)
x = lift(R, red)                                  # a fine plan every agent can execute
b = gap_bounds(fp, R, red; fine_solution = fine)  # b.lower <= b.gap <= b.upper

K = gap_kernel(fp, fine.x)                        # the gap of every team structure, in closed form
sel = select_teams(K; k = 8)                      # 8 teams chosen by their gap
gap(K, sel.teams), gap(K, row_teams(sc))

ctrl = MPCController(fl, Teams(sel.teams))        # receding horizon on the reduced program
let x = formation_start(sc)
    for k in 0:29
        r, rf = references(sc, k * sc.h)
        info = step!(ctrl, x, r; terminal = rf)   # info.u, info.gap_upper, info.t_solve, ...
        x = plant_step(fl, x, info.u)             # the nominal plant
    end
end
```

`examples/grid_fleet.jl` runs the paper's grid-fleet scenario end to end
(levels of reduction, certificates, the selector, the closed loop and its
timing); `examples/custom_fleet.jl` builds a fleet from its matrices.

## Concepts

**The program.** Agent `i` has state `x_{i,t}`, input `u_{i,t}` and affine
dynamics `x_{i,t+1} = A_{i,t} x_{i,t} + B_{i,t} u_{i,t} + g_{i,t}`. Its stage
cost tracks references, its inputs lie in a convex set (a ball or a box), its
states in polyhedra. Agents joined by a formation edge prefer
`C_j x_j - C_i x_i = o_ij` with a weight. The time-expanded graph has one
vertex per agent and instant; its vertex holds `(x_{i,t}, u_{i,t})`. A cellular
sheaf (Curry 2014; Hansen and Ghrist 2019) says which variables each coupling
term reads: dynamics edges are hard (they must hold), formation edges are soft
(springs). `FleetProgram(fleet)` is this program (`SheafProgram` in general).

**Pushforward.** Partition the vertices into blocks and contract the edges
inside each block. A block's configurations that satisfy every edge inside it
form an affine set, its fiber, `xbar + range(N)`. Substituting `x = xbar + N y`
gives the reduced program in the coordinates `y`: the fine program with the
contracted edges made hard, nothing else changed. `reduce(program,
resolution)` builds it; `lift(R, y)` maps a reduced plan back.

**Resolutions.** `TimeBlocking` (`partial_condensing(nu)`,
`full_condensing()`) merges consecutive instants of every agent; it contracts
only hard dynamics edges, so it is exact (no loss of optimality), and full
condensing is classical condensed MPC. `Teams(alpha)` merges the agents of each
team at every instant; it contracts soft formation edges, so it has an
optimality gap. `teams ⊠ blocking` does both (the order does not matter),
`Teams(alpha; from = t0)` forms the teams after `t0` instants, and `Mixed` /
`VertexPartition` give any partition. Reducing a reduced program composes
(teams of teams).

**The gap and its certificates.** Making soft edges hard can only raise the
optimal value; the rise is the gap. `gap_bounds` brackets it: from above by
the energy the contracted springs would store under the forces the teams'
internal edges carry in the reduced solution (recovered team by team, no fine
solve needed), from below by the energy they store at the fine optimum. Teams
that are almost equitable with coherent data have zero gap (rows of the grid
fleet with `coherence = :rows`).

**Distributed MPC.** `DistributedMPC(fleet, teams)` solves the fully
condensed pushforward along the teams (singletons by default) by consensus
ADMM (Boyd et al. 2011; Summers and Lygeros 2012): every agent or team solves
its own QP with half of each formation spring and a consensus penalty, and
exchanges with each neighbour the positions its springs read, once per
iteration. Teams cut the messages: rigid rows of the grid exchange one
planar trajectory per pair of rows instead of one per vehicle. Each step
starts from the previous plan and scaled duals moved one instant earlier
(`warm = :shift`), which is what makes a budget of one or a few iterations per
step close to coordinated MPC. Every step ends with a status (`:max_iter`,
`:time_limit`, `:numerical_error` or an infeasible local QP stop it).

**Changing constraints.** State sets can change in place on the pattern the
controller was built with (`Polyhedron(G, h; pattern)`, then
`set_state_set!` or `step!(...; states)`): re-linearized keep-out half-spaces
whose normals rotate every step update the affected coarse matrices and the
solver's values (one numerical refactorization) instead of rebuilding the
controller.

**The gap kernel.** For an equality-constrained QP the gap of hardening any set
of soft edges is `(1/2) s' K^+ s`, with `s` their defects at the fine optimum
and `K` a kernel from one KKT factorization (`gap_kernel`). `gap(K, teams)`
evaluates a team structure without reducing or solving, and `select_teams`
merges teams greedily by the least gap increment (optionally with a beam and a
local search). With inequalities that become active in the reduced program the
formula is a lower bound.

## API

| | |
|---|---|
| modelling | `Agent(A, B; C, Q, R, Cr, g, Cf, Qf, input, state)`, `BallSet`, `BoxSet`, `Polyhedron(G, h; pattern)`, `Fleet(agents, edges; H, offsets, targets, weights, present)`, `FleetProgram(fleet; x0, references, terminal)`, `set_state!`, `set_references!`, `set_targets!`, `set_drift!`, `set_state_bound!`, `set_state_set!`, `set_state_sets!`, `trajectories`, `first_inputs`, `plant_step`, `shift_plan`, `free_response!` |
| the paper's agents | `quadrotor(h)`, `ground_vehicle(h)`, `grid_graph`, `GridScenario`, `fleet`, `references`, `formation_start`, `row_teams`, `strip_teams`, `block_teams` |
| programs | `SheafProgram(nodes, edges)`, `NodeData`, `SheafEdge`, `objective`, `quadratic_form`, `coboundary`, `feasibility`, `harden`, `solve` |
| resolutions | `Fine`, `TimeBlocking`, `partial_condensing`, `full_condensing`, `Teams`, `⊠` / `Product`, `Mixed`, `VertexPartition` |
| reductions | `reduce(program, resolution; basis, reuse)`, `update!(R)`, `update_matrices!(R, verts)`, `lift`, `restrict`, `restrict!`, `reduction_chain`, `composite_partition` |
| certificates | `gap_bounds(fine, R, sol; fine_solution)`, `Certifier`, `gap_kernel(program, xstar)`, `gap(K, teams)`, `team_front`, `select_teams(K; k, budget, beam, refine)` |
| receding horizon | `MPCController(fleet, resolution; certify, settings...)`, `step!(ctrl, x, refs; terminal, targets, drift, states)`, `plan`, `StepInfo` |
| distributed | `DistributedMPC(fleet, teams; rho, eps_abs, eps_rel, maxit, budget, warm, time_limit)`, `step!`, `floats_per_iteration` |

Every exported function has a docstring (`?reduce` in the REPL).

## Performance

The structure of the program, the fibers of a resolution, the reduced QP's
Hessian and constraint matrix, and the solver's factorizations do not change
between the sampling instants of a fleet with fixed matrices. The particular
solution of each fiber is kept as an operator of the internal targets, so the
reduced program's vectors are affine in the data that do change (measured
states, references, formation targets, drifts), and `update!` recomputes them
with a few sparse products, without allocating. On the 8 x 8 grid fleet
(`bench/controller.jl`, H = 10, 30 closed-loop steps, results in
`bench/results/controller.txt`) the construction of a step (data, program,
pushforward, QP vectors) went from 15 to 18 ms with the paper repository's
per-step pipeline (rebuild, pushforward with fiber reuse, `sheaf_qp`) to 0.2
to 0.35 ms with `MPCController`, below the warm solve (0.5 to 1 ms); a step
allocates a constant 48 bytes.

## Tests

    julia --project=. -e 'using Pkg; Pkg.test()'

The reduction tests port the paper repository's structured-basis tests and
check the identities of the paper on small fleets: `J'(y) = J(lift(y))`, the
same value as the fine program with the contracted edges hard, exact time
blocking, commuting legs, teams of teams, zero gap for coherent rows, bounds
that bracket the true gap, the kernel against pushforward and solve, the
selector, in-place updates against rebuilds, and a 30-step closed loop without
allocation growth. When the paper repository is present (`SHEAFMPC_PAPER`,
default `~/Projects/GATAS/mpc-sheaf-pushforward`), the fleet programs and
reductions are also compared with its research module, read only.

## The solver

An operator-splitting conic QP solver for sheaf programs and multi-agent model
predictive control.

    minimize    (1/2) x'Px + q'x + c
    subject to  A x = z,  z in C,

with `C` a product of intervals (equality, one-sided, two-sided rows) and
translated second-order cones (`b_B - A_B x in SOC`, the convention of
Clarabel and of sheaf programs).

### Algorithm

* ADMM of OSQP (Stellato et al. 2020, Algorithm 1) with over-relaxation
  `alpha = 1.6`, per-row penalties (`rho_eq_scale * rho` on equality rows,
  `rho_min` on free rows). The base rho is `1 / sqrt(lmin lmax)` for the
  extreme eigenvalues of the inequality rows' operator on the null space of the
  equality rows, `A_I (P restricted)^{-1} A_I'` (the optimal penalty of
  Ghadimi et al. 2015 for a QP), estimated in `setup` by 25 Lanczos steps with
  the polish system's factorization (`rho_spectral`); adaptive rho with a
  refactorization only when the estimate moves by more than a factor
  `adaptive_rho_tolerance` serves as a safeguard. Optional safeguarded
  type-II Anderson acceleration of the fixed-point map (`anderson`). OSQP's
  unscaled termination criteria, and primal and dual infeasibility
  certificates (extended to second-order cones). Second-order cones are handled
  by projection, as in COSMO.
* Modified Ruiz equilibration (OSQP), uniform within each SOC block.
* One quasi-definite KKT matrix `[P + sigma I, A'; A, -R^{-1}]`, ordered and
  factored once in `setup` (QDLDL, the structured multifrontal BlockLDL, or the
  supernodal multifrontal LDLt of CliqueTrees; `linsys = :auto` picks the
  engine and the order by BlockLDL's cost model, no trial factorizations). The
  polish system shares the symbolic factorization. The iteration allocates
  nothing.
* Polish (active-set refinement). The equality-constrained QP on the guessed
  active set is solved with a matrix of the same sparsity pattern as the ADMM
  KKT matrix (inactive rows get `-1/delta`, active rows `-delta` on the
  diagonal), so a polish costs one numerical factorization and no symbolic
  work, and nothing at all when the active set is the one factored last time;
  iterative refinement against the exact reduced system gives full accuracy.
  The polished point is accepted only if it meets the termination tolerance
  including the signs of the multipliers. Rejected points get up to
  `polish_corrections` primal-dual active-set corrections, as long as each
  halves the KKT merit, and then restart ADMM (Moreau
  decomposition of `A x + y / rho`). Polish attempts are also made during the
  iterations once the active-set guess is stable, with exponential back-off.
* Second-order cone blocks on their boundary are polished by Newton's method
  on the boundary manifold `s = tau (1, u)`, `y = eta (1, -u)`: in the basis
  `(e_s, e_y, U)` of the block its linearization is the row block
  `A_B x - N y = b_B` with `N = (1/delta) e_s e_s' + delta e_y e_y' +
  (tau/eta) U U'`, symmetric positive definite, so the polish system stays
  quasi-definite on the same pattern (the (2,2) block of each SOC block is
  stored dense).
* Dense active-set path for small polyhedral problems (`dual`, src/dual.jl).
  With at most `dual_max_rows` inequality rows and no cones, `setup` also
  factors the KKT matrix of the equality rows alone and forms the Schur
  complement `Z = A_I (K11^{-1})_xx A_I'` of the inequality rows (the operator
  of the spectral rho), built by blocked solves when it fits
  `dual_setup_budget` and column by column on first use otherwise. An active
  set then costs a dense Cholesky update of `Z_AA` (rows enter by a triangular
  solve, leave by a rank-one update) and no sparse factorization, so a solve
  first runs bounded primal-dual active-set iterations on Z: cold from the
  equality-only solution, warm from the shifted guess and the last accepted
  active set, and during ADMM from its guess every `dual_interval`
  iterations. On the small MPC problems of the benchmark harness this
  replaces the 20 to 50 ADMM iterations and the polish factorizations of a
  cold solve by 2 to 6 dense iterations and 3 to 5 sparse solves; problems
  whose active sets are too large for the dense budget (fleets) keep the
  sparse polish.
* Receding horizon: `update!(solver; q, l, u, b)` changes the data without
  refactoring (`update!(solver; P, A)`, new matrix values on the same pattern
  for time-varying MPC, refactors numerically and keeps the ordering), `warm_start!` / `warm_start_shifted!` move the previous plan,
  and a warm-started `solve!` first tries the polish on the active set of the
  warm start (with the cached polish factorization if it is the same).

### Solver API

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

### Solver tests and benchmarks

    julia --project=. -e 'using Pkg; Pkg.test()'

The tests compare with Clarabel on random QPs and SOCPs, box-constrained MPC
problems on the dense active-set path (cold, warm, degenerate), infeasible problems,
the fleet QP of the paper repository's `bench/central`, and fine and pushed
forward sheaf programs of its Resolution module (read only, from
`SHEAFMPC_PAPER`, default `~/Projects/GATAS/mpc-sheaf-pushforward`).

    julia --project=bench -e 'using Pkg; Pkg.develop(path = "."); Pkg.instantiate()'
    julia --project=bench bench/single.jl     # one QP: SheafMPC, OSQP, Clarabel
    julia --project=bench bench/rh.jl         # receding horizon, 30 steps
    julia --project=bench bench/reduced.jl    # fine program vs pushforwards
    julia --project=bench bench/compare.jl    # single solves, solvers interleaved, min/median
    julia --project=bench bench/rh_compare.jl # receding horizon, interleaved per step (BENCH_WARMUP)
    julia --project=bench bench/variants.jl   # settings variants: iterations, factorizations

Results go to `bench/results/`.
