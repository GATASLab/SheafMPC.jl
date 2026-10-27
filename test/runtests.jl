using SheafMPC
using Test, LinearAlgebra, SparseArrays, Random, Printf
import Clarabel

const PAPER = get(ENV, "SHEAFMPC_PAPER", joinpath(homedir(), "Projects", "GATAS", "mpc-sheaf-pushforward"))

relgap(a, b) = abs(a - b) / max(1.0, abs(b))

include("fixtures.jl")

"Clarabel on a ConicQP at tolerance `tol`: (objective, x, status)."
function clarabel_ref(p::ConicQP; tol = 1e-10)
    m = nrows(p)
    rows = Int[]; b = Float64[]; sgn = Float64[]; cones = Clarabel.SupportedCone[]
    soc = falses(m)
    for B in p.socs
        soc[B] .= true
    end
    eq = [i for i in 1:m if !soc[i] && p.l[i] == p.u[i]]
    if !isempty(eq)
        append!(rows, eq); append!(b, p.u[eq]); append!(sgn, ones(length(eq)))
        push!(cones, Clarabel.ZeroConeT(length(eq)))
    end
    ub = [i for i in 1:m if !soc[i] && p.l[i] != p.u[i] && p.u[i] < Inf]
    lb = [i for i in 1:m if !soc[i] && p.l[i] != p.u[i] && p.l[i] > -Inf]
    if !isempty(ub) || !isempty(lb)
        append!(rows, ub); append!(b, p.u[ub]); append!(sgn, ones(length(ub)))
        append!(rows, lb); append!(b, -p.l[lb]); append!(sgn, -ones(length(lb)))
        push!(cones, Clarabel.NonnegativeConeT(length(ub) + length(lb)))
    end
    for B in p.socs
        append!(rows, B); append!(b, p.socb[B]); append!(sgn, ones(length(B)))
        push!(cones, Clarabel.SecondOrderConeT(length(B)))
    end
    A = SparseMatrixCSC(Diagonal(sgn) * p.A[rows, :])
    st = Clarabel.Settings(verbose = false, tol_gap_abs = tol, tol_gap_rel = tol, tol_feas = tol,
                           tol_ktratio = 1e-8, presolve_enable = false, max_iter = 500)
    s = Clarabel.Solver()
    Clarabel.setup!(s, SparseMatrixCSC(triu(p.P)), p.q, A, b, cones, st)
    r = Clarabel.solve!(s)
    return SheafMPC.objective(p, r.x), r.x, r.status
end

"A random feasible convex QP with equality, two-sided, one-sided and free rows."
function random_qp(rng, n, m; rankdef = false)
    M = sprandn(rng, n, rankdef ? n ÷ 2 : n, 0.3)
    P = M * M' + (rankdef ? 0.0 : 0.05) * I
    A = sprandn(rng, m, n, 0.25)
    x0 = randn(rng, n)
    Ax = A * x0
    l = Ax .- rand(rng, m); u = Ax .+ rand(rng, m)
    ne = m ÷ 5
    l[1:ne] .= Ax[1:ne]; u[1:ne] .= Ax[1:ne]                  # equality rows
    l[ne+1:2ne] .= -Inf                                        # one-sided
    u[2ne+1:3ne] .= Inf
    l[end] = -Inf; u[end] = Inf                                # a free row
    q = rankdef ? P * randn(rng, n) : randn(rng, n) * 3       # bounded: q in the range of P
    return ConicQP(P, q, A, l, u; c = 0.7)
end

"A random feasible SOCP: equality rows and second-order cones, b - A x in K."
function random_socp(rng, n, nsoc, d)
    M = sprandn(rng, n, n, 0.3)
    P = M * M' + 0.05 * I
    q = randn(rng, n)
    ne = 3
    Ae = sprandn(rng, ne, n, 0.5)
    x0 = randn(rng, n) * 0.3
    blocks = SparseMatrixCSC{Float64,Int}[]; bs = Vector{Float64}[]
    for _ in 1:nsoc
        Ab = sprandn(rng, d, n, 0.5)
        s = [1.0 + rand(rng); 0.3 * randn(rng, d - 1)]          # strictly inside the cone
        push!(blocks, Ab); push!(bs, s + Ab * x0)
    end
    A = [Ae; reduce(vcat, blocks)]
    b = [Ae * x0; reduce(vcat, bs)]
    cones = [(:zero, ne); [(:soc, d) for _ in 1:nsoc]]
    return ConicQP(P, q, A, b, cones)
end

@testset "SheafMPC" begin

    @testset "cones" begin
        v = [1.0, 3.0, 4.0]                   # ||s|| = 5 > t = 1
        SheafMPC.project_soc!(v, 1:3)
        @test v ≈ [3.0, 1.8, 2.4]
        w = [-6.0, 3.0, 4.0]                  # inside the polar cone
        SheafMPC.project_soc!(w, 1:3)
        @test w == zeros(3)
        u = [5.0, 3.0, 4.0]
        SheafMPC.project_soc!(u, 1:3)
        @test u == [5.0, 3.0, 4.0]
    end

    @testset "random QPs vs Clarabel" begin
        rng = Xoshiro(11)
        npolished = 0
        for trial in 1:12
            n, m = rand(rng, 10:40), rand(rng, 10:30)
            p = random_qp(rng, n, m; rankdef = isodd(trial))
            ref, _, st = clarabel_ref(p)
            @test st == Clarabel.SOLVED
            # no polish: objective to 1e-6
            s = setup(p; eps_abs = 1e-7, eps_rel = 1e-7, polish = false)
            info = solve!(s)
            @test info.status == :solved
            @test relgap(info.obj, ref) <= 1e-6
            # polished: objective to 1e-8
            s = setup(p; eps_abs = 1e-6, eps_rel = 1e-6)
            info = solve!(s)
            @test info.status == :solved
            npolished += info.polish == :success
            @test relgap(info.obj, ref) <= 1e-8
            # exact when polished; within the tolerance otherwise (the polish
            # may fail on a rank-deficient P, see the count below)
            @test violation(p, s.xsol) <= (info.polish == :success ? 1e-8 : 1e-6)
            # both linear system backends agree
            for ls in (:qdldl, :cliquetrees)
                s2 = setup(p; eps_abs = 1e-6, eps_rel = 1e-6, linsys = ls)
                @test relgap(solve!(s2).obj, ref) <= 1e-8
            end
        end
        @test npolished >= 10        # (a rank-deficient P can make the polish system singular)
    end

    @testset "random SOCPs vs Clarabel" begin
        rng = Xoshiro(5)
        for trial in 1:8
            p = random_socp(rng, rand(rng, 8:20), rand(rng, 1:4), rand(rng, 2:4))
            ref, _, st = clarabel_ref(p)
            @test st == Clarabel.SOLVED
            s = setup(p; eps_abs = 1e-8, eps_rel = 1e-8, max_iter = 20_000)
            info = solve!(s)
            @test info.status == :solved
            @test relgap(info.obj, ref) <= 1e-6
            @test violation(p, s.xsol) <= 1e-6
        end
    end

    @testset "infeasibility" begin
        # primal infeasible: x1 >= 1 and x1 + x2 <= 0 with x2 >= 0
        P = sparse([1.0 0; 0 1])
        A = sparse([1.0 0; 1 1; 0 1])
        p = ConicQP(P, [1.0, 1.0], A, [1.0, -Inf, 0.0], [Inf, 0.0, Inf])
        @test solve!(setup(p)).status == :primal_infeasible
        # dual infeasible (unbounded): min -x1 subject to x1 >= 0
        p = ConicQP(spzeros(2, 2), [-1.0, 0.0], sparse([1.0 0; 0 1]), [0.0, -1.0], [Inf, 1.0])
        @test solve!(setup(p)).status == :dual_infeasible
        # infeasible with a second-order cone: ||(x1, x2)|| <= 1 and x1 >= 2
        # (b - A x in K: s = (1, x1, x2) in the SOC, and -2 + x1 >= 0)
        A = sparse([0.0 0; -1 0; 0 -1; -1 0])
        p = ConicQP(sparse(1.0I, 2, 2), [0.0, 0.0], A, [1.0, 0.0, 0.0, -2.0], [(:soc, 3), (:nonneg, 1)])
        @test solve!(setup(p)).status == :primal_infeasible
    end

    @testset "duplicate rows" begin
        rng = Xoshiro(21)
        p = random_qp(rng, 15, 12)
        A2 = [p.A; p.A[3:4, :]]
        p2 = ConicQP(p.P, p.q, A2, [p.l; p.l[3:4] .- 1], [p.u; p.u[3:4] .+ 1]; c = p.c)
        p3, keep = dedup_rows(p2)
        @test nrows(p3) == nrows(p) && keep == collect(1:nrows(p))
        @test relgap(solve!(setup(p3; eps_abs = 1e-7, eps_rel = 1e-7)).obj, clarabel_ref(p)[1]) <= 1e-8
    end

    @testset "allocations" begin
        rng = Xoshiro(3)
        p = random_qp(rng, 30, 25)
        s = setup(p)
        solve!(s)
        SheafMPC.admm_step!(s)
        @test (@allocated SheafMPC.admm_step!(s)) == 0
        resid(s) = (SheafMPC._residuals!(s, s.x, s.z, s.y, s.Ax, s.Px, s.Aty); nothing)
        resid(s)
        @test (@allocated resid(s)) == 0
        p = random_socp(rng, 15, 3, 3)
        s = setup(p)
        solve!(s)
        SheafMPC.admm_step!(s)
        @test (@allocated SheafMPC.admm_step!(s)) == 0
        s = setup(random_qp(rng, 30, 25); linsys = :cliquetrees)
        solve!(s)
        SheafMPC.admm_step!(s)
        @test (@allocated SheafMPC.admm_step!(s)) == 0
    end

    @testset "spectral rho" begin
        # the Lanczos estimates against the dense spectrum of A_I Z (Z'PZ)^{-1} Z' A_I'
        rng = Xoshiro(17)
        p = random_qp(rng, 30, 24)
        s = setup(p; rho_spectral_iter = 60)
        P = Matrix(s.P) + s.settings.polish_delta * I
        A = Matrix(s.A)
        eq = findall(==(SheafMPC.ROWT_EQ), s.rowtype)
        iq = findall(==(SheafMPC.ROWT_INEQ), s.rowtype)
        Z = nullspace(A[eq, :])
        M = A[iq, :] * Z * ((Z' * P * Z) \ (Z' * A[iq, :]'))
        ev = eigvals(Symmetric((M + M') / 2))
        ev = ev[ev .> 1e-9 * maximum(ev)]
        @test s.lam_max ≈ maximum(ev) rtol = 1e-3
        @test s.lam_min ≈ minimum(ev) rtol = 0.5
        @test s.rho0 ≈ clamp(1 / sqrt(s.lam_min * s.lam_max), 1e-4, 10.0)
        @test s.rho == s.rho0
        # the spectral rho is the base rho of reset! and of a cold solve
        info = solve!(s)
        @test info.status == :solved
        reset!(s)
        @test s.rho == s.rho0
        # without inequality rows the setting is kept
        pe = ConicQP(sparse(1.0I, 3, 3), ones(3), sparse([1.0 1 1]), [1.0], [1.0])
        @test setup(pe).rho0 == Settings().rho
        @test setup(p; rho_spectral = false).rho0 == Settings().rho
    end

    @testset "Anderson acceleration and the polish trigger" begin
        rng = Xoshiro(23)
        for trial in 1:6
            p = isodd(trial) ? random_qp(rng, rand(rng, 15:35), rand(rng, 12:28)) :
                random_socp(rng, rand(rng, 8:16), rand(rng, 1:3), 3)
            ref, _, _ = clarabel_ref(p)
            for kw in ((anderson = 5,), (anderson = 10, polish = false), (polish_settle = 0.01,))
                s = setup(p; eps_abs = 1e-8, eps_rel = 1e-8, max_iter = 20_000, kw...)
                info = solve!(s)
                @test info.status == :solved
                @test relgap(info.obj, ref) <= 1e-6
                @test violation(p, s.xsol) <= 1e-6
            end
        end
        # without the polish the accelerated iteration still converges, with
        # accepted extrapolations, and allocates nothing per iteration
        p = random_qp(rng, 30, 25)
        s = setup(p; anderson = 8, polish = false, eps_abs = 1e-9, eps_rel = 1e-9, max_iter = 20_000)
        info = solve!(s)
        @test info.status == :solved && s.aa.accepted > 0
        SheafMPC._aa_load_point!(s.aa.w, s)
        SheafMPC.admm_step!(s)
        SheafMPC._aa_update!(s.aa, s)
        step(s) = (SheafMPC._aa_load_point!(s.aa.w, s); SheafMPC.admm_step!(s); SheafMPC._aa_update!(s.aa, s); nothing)
        step(s)
        @test (@allocated step(s)) == 0
    end

    @testset "update and warm start" begin
        rng = Xoshiro(9)
        p = random_qp(rng, 25, 20)
        s = setup(p; eps_abs = 1e-7, eps_rel = 1e-7)
        solve!(s)
        q2 = p.q + 0.3 * randn(rng, length(p.q))
        p2 = ConicQP(p.P, q2, p.A, p.l, p.u; c = p.c)
        ref, _, _ = clarabel_ref(p2)
        update!(s; q = q2)
        info = solve!(s)                     # warm from the previous solution
        @test info.status == :solved && relgap(info.obj, ref) <= 1e-8
        warm_start!(s; x = s.xsol, y = s.ysol)
        info = solve!(s)                     # warm start at the solution: polished at iteration 0
        @test info.iter == 0 && info.polish == :success
        @test relgap(info.obj, ref) <= 1e-8
        reset!(s)
        @test relgap(solve!(s).obj, ref) <= 1e-8
        # a sequence of perturbed QPs warm started from the previous solution:
        # every solve is accurate, and the warm polish (with its active-set
        # corrections) accepts some of them before any iteration
        s = setup(p; eps_abs = 1e-7, eps_rel = 1e-7, polish_warm_retry = 1)
        solve!(s)
        nwarm = 0
        for k in 1:8
            qk = p.q + 0.05 * k * randn(rng, length(p.q))
            pk = ConicQP(p.P, qk, p.A, p.l, p.u; c = p.c)
            update!(s; q = qk)
            warm_start!(s; x = s.xsol, y = s.ysol)
            info = solve!(s)
            nwarm += info.polish == :success && info.polish_iter == 0
            @test info.status == :solved
            @test relgap(info.obj, clarabel_ref(pk)[1]) <= 1e-8
        end
        @test nwarm >= 2
    end

    include("structured_basis.jl")
    include("reductions.jl")
    include("stepop.jl")
    include("certificates.jl")
    include("controller.jl")
    include("distributed.jl")
    include("conic.jl")
    include("dual.jl")
    include(joinpath(@__DIR__, "kkt.jl"))

    if isdir(PAPER)
        include(joinpath(@__DIR__, "paper.jl"))
    else
        @info "paper repository not found at $PAPER: skipping the fleet QP and sheaf program tests"
    end
end
