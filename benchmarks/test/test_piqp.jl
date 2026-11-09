# test_piqp.jl: the PIQP adapter against Clarabel on small random QPs.
#
#   julia --project=benchmarks benchmarks/test/test_piqp.jl
#
# Every QP mixes the row kinds the adapter splits apart: equality rows,
# two-sided and one-sided general rows, box rows on single variables (several
# rows on the same variable, some with negative coefficients, so the bounds
# are intersected), one-sided single-variable rows and a free row. Each is
# solved with every KKT variant and checked against a tight Clarabel solve
# (objective, primal and dual residuals), then update! with a new q and new
# bounds is checked against a fresh Clarabel solve.

module PiqpTest

using LinearAlgebra, SparseArrays, Libdl, Random, Test, Printf
import Clarabel

include(joinpath(@__DIR__, "..", "src", "qp.jl"))
include(joinpath(@__DIR__, "..", "src", "solvers", "interface.jl"))
include(joinpath(@__DIR__, "..", "src", "solvers", "piqp.jl"))

"""
Random QP around the feasible point x0: rows of each kind, bounds placed at
A x0 -+ random slack, and q pulling the minimizer away from x0 so that many
rows are active.
"""
function random_qp(rng, n; x0 = randn(rng, n), xt = 4 .* randn(rng, n), name = "rand")
    rows = Vector{Pair{Vector{Int},Vector{Float64}}}()   # (vars, coefs)
    kind = Symbol[]
    addrow!(vars, coefs, k) = (push!(rows, vars => coefs); push!(kind, k))
    for _ in 1:2                                   # equalities
        v = randperm(rng, n)[1:3]; addrow!(v, randn(rng, 3), :eq)
    end
    for _ in 1:3                                   # two-sided general rows
        v = randperm(rng, n)[1:4]; addrow!(v, randn(rng, 4), :box)
    end
    for _ in 1:2                                   # one-sided general rows
        v = randperm(rng, n)[1:3]; addrow!(v, randn(rng, 3), :up)
        v = randperm(rng, n)[1:2]; addrow!(v, randn(rng, 2), :lo)
    end
    for j in 1:n                                   # box rows on every variable
        addrow!([j], [rand(rng) < 0.5 ? -(0.5 + rand(rng)) : 0.5 + rand(rng)], :box)
    end
    for j in 1:3                                   # a second, tighter row on a few variables
        addrow!([j], [-(1 + rand(rng))], :box)
    end
    addrow!([n], [2.0], :up)                       # one-sided singleton rows
    addrow!([n - 1], [-3.0], :lo)
    addrow!([1, 2], [1.0, 1.0], :free)             # free row
    m = length(rows)
    Ir = Int[]; Jc = Int[]; V = Float64[]
    for (i, (vs, cs)) in enumerate(rows)
        append!(Ir, fill(i, length(vs))); append!(Jc, vs); append!(V, cs)
    end
    A = sparse(Ir, Jc, V, m, n)
    M = sprandn(rng, n, n, 0.3)
    P = M' * M + 0.1I
    return qp_from(name, P, A, kind, x0, xt, rng), kind
end

function qp_from(name, P, A, kind, x0, xt, rng)
    Ax = A * x0
    m = size(A, 1)
    l = fill(-Inf, m); u = fill(Inf, m)
    for i in 1:m
        s1 = 0.05 + 0.5 * rand(rng); s2 = 0.05 + 0.5 * rand(rng)
        if kind[i] == :eq;  l[i] = u[i] = Ax[i]
        elseif kind[i] == :box; l[i] = Ax[i] - s1; u[i] = Ax[i] + s2
        elseif kind[i] == :up;  u[i] = Ax[i] + s2
        elseif kind[i] == :lo;  l[i] = Ax[i] - s1
        end
    end
    q = -P * xt
    return QP(name, P, q, A, l, u)
end

"Reference solution of b - A x in K with Clarabel at tight tolerance."
function clarabel_ref(p::QP)
    m = ncons(p)
    eq = [i for i in 1:m if p.l[i] == p.u[i]]
    ub = [i for i in 1:m if p.l[i] != p.u[i] && isfinite(p.u[i])]
    lb = [i for i in 1:m if p.l[i] != p.u[i] && isfinite(p.l[i])]
    rows = [eq; ub; lb]
    sgn = [ones(length(eq) + length(ub)); -ones(length(lb))]
    A = sparse(Diagonal(sgn) * p.A[rows, :])
    b = [p.u[eq]; p.u[ub]; -p.l[lb]]
    cones = Clarabel.SupportedCone[Clarabel.ZeroConeT(length(eq)), Clarabel.NonnegativeConeT(length(ub) + length(lb))]
    s = Clarabel.Settings(verbose = false, tol_gap_abs = 1e-12, tol_gap_rel = 1e-12, tol_feas = 1e-12,
                          tol_ktratio = 1e-10, max_iter = 500, presolve_enable = false)
    solver = Clarabel.Solver()
    Clarabel.setup!(solver, sparse(triu(p.P)), p.q, A, b, cones, s)
    r = Clarabel.solve!(solver)
    @assert string(r.status) == "SOLVED" "Clarabel reference: $(r.status)"
    y = zeros(m)
    for (k, i) in enumerate(rows); y[i] += sgn[k] * r.z[k]; end
    return r.x, y, objective0(p, r.x)
end

const TOL = 1e-7

function check_against_ref(p::QP, res::SolveResult, label)
    xr, yr, f0 = clarabel_ref(p)
    cr = check(p, xr, yr, f0)
    c = check(p, res.x, res.y, f0)
    @printf("  %-34s %-8s it %3d  obj_err %.1e  prim_rel %.1e  dual_rel %.1e  |x-x*| %.1e  (ref dual_rel %.1e)\n",
            label, res.status, res.iters, c.obj_err, c.prim_rel, c.dual_rel, norm(res.x - xr, Inf), cr.dual_rel)
    @test res.status == :solved
    @test c.obj_err < TOL
    @test c.prim_rel < TOL
    @test c.dual_rel < TOL
    return c
end

spec = piqp_spec()
println("PIQP library: ", piqp_libpath())
println("variants: ", join([v["kkt_solver"] for v in spec.variants], ", "))

@testset "PIQP adapter" begin
    rng = MersenneTwister(20261018)
    for (t, n) in enumerate((8, 15, 30))
        p, kind = random_qp(rng, n; name = "rand$t")
        @test spec.applicable(p)
        println("QP $(p.name): n = $(nvars(p)), m = $(ncons(p))")
        for v in spec.variants
            h = spec.setup(p, 1e-9, v)
            @test length(h.eq_rows) == 2 && length(h.bnd_rows) == n + 5 && length(h.g_rows) == 7
            check_against_ref(p, spec.solve!(h), "cold " * v["kkt_solver"])
            # sequence step: same structure, new q and bounds around a new feasible point
            p2 = qp_from(p.name * "'", p.P, p.A, kind, randn(rng, n), 4 .* randn(rng, n), rng)
            @test same_structure(p, p2)
            spec.update!(h, p2)
            check_against_ref(p2, spec.solve!(h), "update " * v["kkt_solver"])
            spec.update!(h, p)
            check_against_ref(p, spec.solve!(h), "update back " * v["kkt_solver"])
        end
    end
    # no equality rows and no general rows: PIQP gets NULL A and G
    p = QP("boxonly", sparse(Diagonal(1.0 .+ rand(rng, 5))), randn(rng, 5), sparse(Diagonal([1.0, -2.0, 3.0, 1.0, -1.0])),
           fill(-0.3, 5), fill(0.4, 5))
    h = spec.setup(p, 1e-9, spec.variants[1])
    check_against_ref(p, spec.solve!(h), "box-only sparse_ldlt")
    @test spec.applicable(QP("soc", sparse(1.0I, 3, 3), zeros(3), sparse(1.0I, 3, 3), zeros(3), zeros(3);
                             socs = [1:3])) == false
    @test haskey(spec.info(), "commit")
end

end
