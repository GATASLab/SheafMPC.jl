# dual.jl: the dense active-set path for small polyhedral problems: agreement
# with Clarabel and with the ADMM path, degenerate and infeasible problems,
# bounded iterations, warm receding-horizon solves, the size gate, and no
# allocations in an attempt.

"""
A box-constrained linear MPC QP: `nx` states (a chain of double integrators),
`nu` inputs, horizon `N`, variables `u_0, x_1, u_1, ..., x_N`, dynamics as
equality rows, input and state boxes as interval rows.
"""
function mpc_box_qp(; nx = 4, nu = 2, N = 15, x0 = ones(nx), umax = 0.5, xmax = 5.0, r = zeros(nx))
    h = 0.2
    A = Matrix{Float64}(I, nx, nx); B = zeros(nx, nu)
    for k in 1:2:(nx-1)
        A[k, k+1] = h
        B[k+1, min(cld(k, 2), nu)] = h
    end
    nv = N * (nu + nx)
    uo(k) = k * (nu + nx)                 # offset of u_k (k = 0..N-1)
    xo(k) = (k - 1) * (nu + nx) + nu      # offset of x_k (k = 1..N)
    P = spzeros(nv, nv); q = zeros(nv)
    for k in 0:N-1
        for i in 1:nu
            P[uo(k)+i, uo(k)+i] = 0.1
        end
    end
    for k in 1:N
        for i in 1:nx
            P[xo(k)+i, xo(k)+i] = k == N ? 10.0 : 1.0
            q[xo(k)+i] = -(k == N ? 10.0 : 1.0) * r[i]
        end
    end
    I_ = Int[]; J = Int[]; V = Float64[]; l = Float64[]; u = Float64[]
    row = 0
    for k in 0:N-1                          # x_{k+1} - A x_k - B u_k = 0 (+ A x0 for k = 0)
        for i in 1:nx
            row += 1
            push!(I_, row); push!(J, xo(k + 1) + i); push!(V, 1.0)
            if k > 0
                for j in 1:nx
                    A[i, j] != 0 && (push!(I_, row); push!(J, xo(k) + j); push!(V, -A[i, j]))
                end
            end
            for j in 1:nu
                B[i, j] != 0 && (push!(I_, row); push!(J, uo(k) + j); push!(V, -B[i, j]))
            end
            b = k == 0 ? dot(A[i, :], x0) : 0.0
            push!(l, b); push!(u, b)
        end
    end
    for k in 0:N-1, i in 1:nu
        row += 1
        push!(I_, row); push!(J, uo(k) + i); push!(V, 1.0); push!(l, -umax); push!(u, umax)
    end
    for k in 1:N, i in 1:nx
        row += 1
        push!(I_, row); push!(J, xo(k) + i); push!(V, 1.0); push!(l, -xmax); push!(u, xmax)
    end
    Am = sparse(I_, J, V, row, nv)
    return ConicQP(P, q, Am, l, u)
end

@testset "dense active-set path" begin

    @testset "agreement with Clarabel and with ADMM" begin
        for (x0, umax) in ((ones(4), 0.5), ([2.0, -1.0, 0.5, 1.0], 0.3), ([2.0, -1.0, 0.5, 1.0], 1.0), (zeros(4), 0.5))
            p = mpc_box_qp(; x0 = x0, umax = umax)
            ref, xr, _ = clarabel_ref(p)
            s = setup(p; eps_abs = 1e-9, eps_rel = 1e-9, dual = :on)
            @test s.dual !== nothing
            info = solve!(s)
            @test info.status == :solved
            @test info.polish == :success
            @test relgap(info.obj, ref) <= 1e-8
            @test violation(p, s.xsol) <= 1e-8
            s2 = setup(p; eps_abs = 1e-9, eps_rel = 1e-9, dual = :off)
            @test s2.dual === nothing
            solve!(s2)
            @test norm(s.xsol - s2.xsol, Inf) <= 1e-6 * max(1, norm(s2.xsol, Inf))
        end
        # the dense path solves the box MPC problem cold without ADMM iterations
        p = mpc_box_qp(; x0 = 1.5 * ones(4), umax = 0.3)
        s = setup(p; eps_abs = 1e-6, eps_rel = 1e-6)
        info = solve!(s)
        @test info.iter == 0 && info.polish == :success
        @test s.dual.na > 0
        # random QPs with equality, one-sided, two-sided and free rows
        rng = Xoshiro(41)
        for t in 1:8
            p = random_qp(rng, 30, 45)
            ref, _, st = clarabel_ref(p)
            st == Clarabel.SOLVED || continue
            s = setup(p; eps_abs = 1e-9, eps_rel = 1e-9, dual = :on)
            info = solve!(s)
            @test info.status == :solved
            @test relgap(info.obj, ref) <= 1e-7
        end
    end

    @testset "dependent active rows" begin
        # every input bound row twice: the active rows are linearly dependent
        p0 = mpc_box_qp(; x0 = 1.5 * ones(4), umax = 0.3)
        m = nrows(p0)
        nu_rows = findall(i -> p0.l[i] != p0.u[i], 1:m)[1:30]
        A = [p0.A; p0.A[nu_rows, :]]
        p = ConicQP(p0.P, p0.q, A, [p0.l; p0.l[nu_rows]], [p0.u; p0.u[nu_rows]])
        ref, _, _ = clarabel_ref(p)
        s = setup(p; eps_abs = 1e-8, eps_rel = 1e-8, dual = :on)
        info = solve!(s)
        @test info.status == :solved
        @test relgap(info.obj, ref) <= 1e-6
        @test violation(p, s.xsol) <= 1e-6
    end

    @testset "infeasible problem" begin
        # the dynamics pin x_1 = A x0 outside the state box: no active set is a
        # solution, the attempts stop within their bound and ADMM certifies
        p = mpc_box_qp(; x0 = 10 * ones(4), xmax = 1.0)
        s = setup(p; dual = :on, max_iter = 20000)
        info = solve!(s)
        @test info.status == :primal_infeasible
        @test s.dual.iters <= 4 * s.settings.dual_iter
    end

    @testset "bounded iterations fall back to ADMM" begin
        p = mpc_box_qp(; x0 = 1.5 * ones(4), umax = 0.3)
        ref, _, _ = clarabel_ref(p)
        s = setup(p; eps_abs = 1e-8, eps_rel = 1e-8, dual = :on, dual_iter = 1)
        info = solve!(s)
        @test info.status == :solved
        @test relgap(info.obj, ref) <= 1e-7
        @test info.iter > 0                       # one active-set iteration does not converge here
        s = setup(p; eps_abs = 1e-8, eps_rel = 1e-8, dual = :on, dual_budget = 1e-6)
        info = solve!(s)
        @test info.status == :solved
        @test relgap(info.obj, ref) <= 1e-7
    end

    @testset "warm receding horizon from the last active set" begin
        p = mpc_box_qp(; x0 = 1.5 * ones(4), umax = 0.3)
        s = setup(p; eps_abs = 1e-8, eps_rel = 1e-8)
        solve!(s)
        nwarm = 0
        for k in 1:6
            x0 = 1.5 * ones(4) .* 0.9^k
            pk = mpc_box_qp(; x0 = x0, umax = 0.3)
            update!(s; q = pk.q, l = pk.l, u = pk.u)
            warm_start!(s; x = s.xsol, y = s.ysol)
            info = solve!(s)
            @test info.status == :solved
            @test relgap(info.obj, clarabel_ref(pk)[1]) <= 1e-7
            nwarm += info.iter == 0 && info.polish == :success
        end
        @test nwarm == 6
        # the same problem again: the factor of the active set is reused (no new columns)
        update!(s; q = s.q ./ (s.scl.c .* s.scl.D))
        warm_start!(s; x = s.xsol, y = s.ysol)
        solve!(s)
        @test s.dual.cols == 0
    end

    @testset "row types, size gate, settings" begin
        p = mpc_box_qp()
        @test setup(p; dual_max_rows = 10).dual === nothing
        @test setup(p; dual = :off).dual === nothing
        @test_throws ArgumentError setup(p; dual = :maybe)
        # a lazily built Z (no setup budget) gives the same solution
        ref, _, _ = clarabel_ref(p)
        s = setup(p; eps_abs = 1e-9, eps_rel = 1e-9, dual_setup_budget = 0.0)
        @test !all(s.dual.zok)
        @test relgap(solve!(s).obj, ref) <= 1e-8
        # the blocked build of Z in setup equals the columns built one by one
        s1 = setup(p; dual_setup_budget = 1.0)
        @test all(s1.dual.zok)
        for c in eachindex(s.dual.zok)
            SheafMPC._dual_column!(s.dual, c)
        end
        @test norm(s1.dual.Z - s.dual.Z, Inf) <= 1e-10 * norm(s.dual.Z, Inf)
        # second-order cones: no dense path
        pc = ConicQP(sparse(1.0I, 3, 3), [1.0, 0.0, 0.0], sparse(1.0I, 3, 3), [1.0, 0.0, 0.0], [(:soc, 3)])
        @test setup(pc).dual === nothing
        # an update that turns an interval row into an equality row drops the path
        s = setup(p; eps_abs = 1e-9, eps_rel = 1e-9)
        l = copy(p.l); u = copy(p.u)
        i = findfirst(j -> l[j] != u[j], eachindex(l))
        l[i] = 0.1; u[i] = 0.1
        update!(s; l = l, u = u)
        @test s.dual === nothing
        p2 = ConicQP(p.P, p.q, p.A, l, u)
        @test relgap(solve!(s).obj, clarabel_ref(p2)[1]) <= 1e-7
    end

    @testset "no allocations in an attempt" begin
        p = mpc_box_qp(; x0 = 1.5 * ones(4), umax = 0.3)
        s = setup(p; eps_abs = 1e-8, eps_rel = 1e-8)
        solve!(s)
        SheafMPC._try_dual!(s, :xbar)
        s.dual.xbar_ok = false
        @test (@allocated SheafMPC._try_dual!(s, :xbar)) == 0
        for _ in 1:3
            reset!(s); solve!(s)
        end
        reset!(s)
        @test (@allocated solve!(s)) == 0
    end
end

@testset "new matrix values (time-varying MPC)" begin
    # the same pattern with other dynamics and weights: update! with P and A
    # against a fresh setup, with and without the dense path
    p0 = mpc_box_qp(; x0 = 1.5 * ones(4), umax = 0.3)
    for d in (:auto, :off), linsys in (:qdldl, :blockldl)
        s = setup(p0; eps_abs = 1e-9, eps_rel = 1e-9, dual = d, linsys = linsys)
        solve!(s)
        for k in 1:4
            f = 1 + 0.15 * sin(k)
            A2 = copy(p0.A); nonzeros(A2) .*= [abs(v) == 1.0 ? 1.0 : f for v in nonzeros(A2)]
            P2 = copy(p0.P); nonzeros(P2) .*= (1 + 0.1 * k)
            pk = ConicQP(P2, p0.q, A2, p0.l, p0.u)
            update!(s; P = P2, A = A2)
            warm_start!(s; x = s.xsol, y = s.ysol)
            info = solve!(s)
            ref, _, st = clarabel_ref(pk)
            @test info.status == :solved
            @test relgap(info.obj, ref) <= 1e-7
            d == :auto && @test s.dual !== nothing
        end
    end
    # after a step with new matrices the dense path steps aside for one solve,
    # then refactors K11 and serves the next solve with unchanged matrices
    s = setup(p0; eps_abs = 1e-9, eps_rel = 1e-9)
    solve!(s)
    A2 = copy(p0.A); nonzeros(A2) .*= [abs(v) == 1.0 ? 1.0 : 1.1 for v in nonzeros(A2)]
    p2 = ConicQP(p0.P, p0.q, A2, p0.l, p0.u)
    update!(s; A = A2)
    warm_start!(s; x = s.xsol, y = s.ysol)
    info = solve!(s)
    @test info.status == :solved && !s.dual.accepted
    warm_start!(s; x = s.xsol, y = s.ysol)
    info = solve!(s)                     # the cached polish factorization serves this one
    @test info.status == :solved && s.dual.stale == 0
    reset!(s)
    info = solve!(s)                     # and the refactored K11 a cold solve
    @test info.status == :solved && s.dual.accepted
    @test relgap(info.obj, clarabel_ref(p2)[1]) <= 1e-7
    s = setup(p0)
    @test_throws ArgumentError update!(s; A = sparse(ones(nrows(p0), nvars(p0))))
end
