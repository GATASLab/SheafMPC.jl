# test_hpipm.jl: the HPIPM adapter against Clarabel on a hand-built StageOCP.
#
#   julia --project=benchmarks benchmarks/test/test_hpipm.jl
#
# A double integrator (N = 10) with active input boxes, a one-sided and a free
# state bound, general constraints on every stage (one of them touching u_0
# and x0), a terminal equality, nonzero S, b and x0. The canonical QP orders
# the variables u_0, x_1, u_1, x_2, ..., x_N. Every mode and several N2 are
# checked, then update! with a new x0 and q against a fresh Clarabel solve.
# A second part runs the adapter as BenchHarness includes it on real family
# problems (fleet, quadrotor with one-sided state bounds stored as +-1e20,
# osqprand) against BenchHarness.reference; set HPIPM_TEST_HARNESS=0 to skip.

module HpipmTest

using LinearAlgebra, SparseArrays, Libdl, Test, Printf
import Clarabel

include(joinpath(@__DIR__, "..", "src", "qp.jl"))
include(joinpath(@__DIR__, "..", "src", "solvers", "interface.jl"))
include(joinpath(@__DIR__, "..", "src", "solvers", "hpipm.jl"))

function double_integrator(; N = 10, x0 = [3.0, -1.0], qshift = 0.0)
    dt = 0.2
    nxs, nus = 2, 1
    nx = fill(nxs, N + 1); nu = [fill(nus, N); 0]
    A = [[1.0 dt; 0.0 1.0] for _ in 1:N]
    B = [reshape([0.5dt^2, dt], 2, 1) for _ in 1:N]
    b = [[0.001 * k, -0.002 * k] for k in 0:N-1]
    Q = [k == N ? [10.0 1.0; 1.0 5.0] : [1.0 0.1; 0.1 0.5] for k in 0:N]
    S = [k == N ? zeros(0, nxs) : [0.05 -0.02] for k in 0:N]
    R = [k == N ? zeros(0, 0) : fill(0.1, 1, 1) for k in 0:N]
    qx = [[0.1 + qshift, -0.05 * k] for k in 0:N]
    ru = [k == N ? Float64[] : [0.01 * k] for k in 0:N]
    # x[2] >= -1.2 (one-sided), x[1] free (both infinite: dropped by the adapter)
    idxbx = [[2, 1] for _ in 0:N]
    lbx = [[-1.2, -Inf] for _ in 0:N]
    ubx = [[Inf, Inf] for _ in 0:N]
    idxbu = [k == N ? Int[] : [1] for k in 0:N]
    lbu = [k == N ? Float64[] : [-0.6] for k in 0:N]
    ubu = [k == N ? Float64[] : [0.6] for k in 0:N]
    # x1 + 0.3 u <= 3.05 on stages 0..N-1, a row that depends on x0 only at
    # stage 0 (dropped), and the terminal equality x_N[2] = 0
    C = [k == N ? [0.0 1.0] : [1.0 0.0; 0.0 1.0] for k in 0:N]
    D = [k == N ? zeros(1, 0) : reshape([0.3, 0.0], 2, 1) for k in 0:N]
    lg = [k == N ? [0.0] : [-Inf, -50.0] for k in 0:N]
    ug = [k == N ? [0.0] : [3.05, 50.0] for k in 0:N]

    # canonical variable layout: u_0, x_1, u_1, ..., u_{N-1}, x_N
    cmap = NTuple{3,Int}[]
    xoff = zeros(Int, N + 1); uoff = zeros(Int, N + 1)
    for k in 0:N
        if k > 0
            xoff[k+1] = length(cmap)
            for i in 1:nx[k+1]; push!(cmap, (k, 1, i)); end
        end
        if nu[k+1] > 0
            uoff[k+1] = length(cmap)
            for i in 1:nu[k+1]; push!(cmap, (k, 2, i)); end
        end
    end
    st = StageOCP(N, nx, nu, A, B, b, Q, S, R, qx, ru, idxbx, lbx, ubx, idxbu, lbu, ubu,
                  C, D, lg, ug, x0, cmap)
    return st, canonical(st, xoff, uoff)
end

# The canonical QP of a StageOCP with x0 substituted.
function canonical(st::StageOCP, xoff, uoff)
    N = st.N; n = length(st.cmap)
    I = Int[]; J = Int[]; V = Float64[]
    q = zeros(n); c = 0.0
    xs(k) = xoff[k+1] .+ (1:st.nx[k+1]); us(k) = uoff[k+1] .+ (1:st.nu[k+1])
    addblk!(rows, cols, M) = for (a, r) in enumerate(rows), (bb, s) in enumerate(cols)
        M[a, bb] != 0 && (push!(I, r); push!(J, s); push!(V, M[a, bb]))
    end
    x0 = st.x0
    for k in 0:N
        i = k + 1
        if k == 0
            c += 0.5 * dot(x0, st.Q[1] * x0) + dot(st.qx[1], x0)
            if st.nu[1] > 0
                addblk!(us(0), us(0), st.R[1])
                q[us(0)] .+= st.ru[1] .+ st.S[1] * x0
            end
        else
            addblk!(xs(k), xs(k), st.Q[i]); q[xs(k)] .+= st.qx[i]
            if st.nu[i] > 0
                addblk!(us(k), us(k), st.R[i]); q[us(k)] .+= st.ru[i]
                addblk!(us(k), xs(k), st.S[i]); addblk!(xs(k), us(k), Matrix(st.S[i]'))
            end
        end
    end
    P = sparse(I, J, V, n, n)
    Ai = Int[]; Aj = Int[]; Av = Float64[]; l = Float64[]; u = Float64[]
    row = Ref(0)
    function addrow!(entries, lo, hi)
        row[] += 1
        for (j, v) in entries
            v != 0 && (push!(Ai, row[]); push!(Aj, j); push!(Av, v))
        end
        push!(l, lo); push!(u, hi)
    end
    for k in 0:N-1
        i = k + 1
        for r in 1:st.nx[i+1]
            e = Pair{Int,Float64}[xs(k + 1)[r] => 1.0]
            for s in 1:st.nu[i]; push!(e, us(k)[s] => -st.B[i][r, s]); end
            rhs = st.b[i][r]
            if k == 0
                rhs += dot(st.A[1][r, :], x0)
            else
                for s in 1:st.nx[i]; push!(e, xs(k)[s] => -st.A[i][r, s]); end
            end
            addrow!(e, rhs, rhs)
        end
    end
    for k in 0:N
        i = k + 1
        if k > 0
            for (t, j) in enumerate(st.idxbx[i])
                (isfinite(st.lbx[i][t]) || isfinite(st.ubx[i][t])) &&
                    addrow!([xs(k)[j] => 1.0], st.lbx[i][t], st.ubx[i][t])
            end
        end
        for (t, j) in enumerate(st.idxbu[i])
            addrow!([us(k)[j] => 1.0], st.lbu[i][t], st.ubu[i][t])
        end
        for r in eachindex(st.lg[i])
            e = Pair{Int,Float64}[]
            for s in 1:st.nu[i]; push!(e, us(k)[s] => st.D[i][r, s]); end
            off = 0.0
            if k == 0
                off = dot(st.C[1][r, :], x0)
            else
                for s in 1:st.nx[i]; push!(e, xs(k)[s] => st.C[i][r, s]); end
            end
            isempty(e) || all(p -> p.second == 0, e) || addrow!(e, st.lg[i][r] - off, st.ug[i][r] - off)
        end
    end
    A = sparse(Ai, Aj, Av, row[], n)
    return QP("double_integrator", P, q, A, l, u; c = c, stage = st)
end

# Clarabel on l <= Ax <= u at tight tolerance; returns the objective without c.
function clarabel_ref(p::QP)
    m, n = size(p.A)
    eq = [i for i in 1:m if p.l[i] == p.u[i]]
    up = [i for i in 1:m if p.l[i] != p.u[i] && isfinite(p.u[i])]
    lo = [i for i in 1:m if p.l[i] != p.u[i] && isfinite(p.l[i])]
    Ac = [p.A[eq, :]; p.A[up, :]; -p.A[lo, :]]
    bc = [p.u[eq]; p.u[up]; -p.l[lo]]
    cones = Clarabel.SupportedCone[Clarabel.ZeroConeT(length(eq)), Clarabel.NonnegativeConeT(length(up) + length(lo))]
    set = Clarabel.Settings(verbose = false, tol_gap_abs = 1e-12, tol_gap_rel = 1e-12, tol_feas = 1e-12,
                            tol_ktratio = 1e-10, max_iter = 500)
    s = Clarabel.Solver()
    Clarabel.setup!(s, sparse(triu(p.P)), p.q, sparse(Ac), bc, cones, set)
    r = Clarabel.solve!(s)
    @assert r.status == Clarabel.SOLVED "Clarabel: $(r.status)"
    return r.x, objective0(p, r.x)
end

const EPS = 1e-9

function run()
    st, qp = double_integrator()
    xref, f0 = clarabel_ref(qp)
    # the reference has active input bounds (the test is not vacuous)
    nact = count(j -> st.cmap[j][2] == 2 && abs(abs(xref[j]) - 0.6) < 1e-7, eachindex(xref))
    @test nact >= 2
    spec = hpipm_spec()
    @test spec.name == "hpipm"
    @test spec.applicable(qp)
    println("library: ", hpipm_default_dir())
    @testset "mode=$mode N2=$N2" for mode in ("SPEED_ABS", "SPEED", "BALANCE", "ROBUST"), N2 in ("N", "N/2", "N/4", "N/8", "1", 3)
        h = spec.setup(qp, EPS, Dict{String,Any}("mode" => mode, "N2" => N2))
        r = spec.solve!(h)
        chk = check(qp, r.x, nothing, f0)
        @printf("  %-9s N2=%-4s (%2d) %-9s iters %3d  obj_err %.1e  prim_rel %.1e\n",
                mode, string(N2), h.N2, r.status, r.iters, chk.obj_err, chk.prim_rel)
        @test r.status == :solved
        @test chk.obj_err < 1e-7
        @test chk.prim_rel < 1e-7
        # a second cold solve on the same handle gives the same answer
        r2 = spec.solve!(h)
        @test maximum(abs, r2.x .- r.x) < 1e-12

        # sequence step: new x0 and q, same structure
        st2, qp2 = double_integrator(x0 = [-2.0, 0.9], qshift = 0.7)
        @test same_structure(qp, qp2)
        xref2, f02 = clarabel_ref(qp2)
        spec.update!(h, qp2)
        r3 = spec.solve!(h)
        chk2 = check(qp2, r3.x, nothing, f02)
        @test r3.status == :solved
        @test chk2.obj_err < 1e-7
        @test chk2.prim_rel < 1e-7
        # and back to the first problem
        spec.update!(h, qp)
        r4 = spec.solve!(h)
        @test check(qp, r4.x, nothing, f0).obj_err < 1e-7
    end
    println(spec.info())
end

run()

end

module HpipmHarnessTest

using Test, Printf, LinearAlgebra
const ENABLED = get(ENV, "HPIPM_TEST_HARNESS", "1") != "0"
ENABLED && include(joinpath(@__DIR__, "..", "src", "BenchHarness.jl"))

const HEPS = parse(Float64, get(ENV, "HPIPM_TEST_EPS", "1e-10"))

function run()
    BH = BenchHarness
    BH.REF_DIR[] = mktempdir()
    spec = BH.hpipm_spec()
    m = BH.read_osqprand(joinpath(BH.OSQPRAND_DIR[], "osqprand_n10_s1.json"))
    x0q = zeros(12); x0q[1] = 0.3; x0q[4] = -0.5; x0q[6] = -0.8
    probs = [
        ("fleet n4 N24", BH.fleet_qp(n = 4, N = 24, b = 1),
         BH.fleet_qp(n = 4, N = 24, b = 1, x0 = [[0.1i, -0.2, 0.05, 0.1] for i in 1:4])),
        ("quad N12", BH.stage_canonical("quad", BH.quad_ocp(N = 12, x0 = zeros(12))),
         BH.stage_canonical("quad", BH.quad_ocp(N = 12, x0 = x0q))),
        ("osqprand n10", BH.osqprand_qp(m, m.x0), BH.osqprand_qp(m, 0.5 .* m.x0)),
    ]
    @testset "harness problems" for (name, p, p2) in probs
        @test spec.applicable(p)
        @test BH.same_structure(p, p2)
        ref = BH.reference(p); ref2 = BH.reference(p2)
        @testset "$name mode=$mode N2=$N2" for mode in ("SPEED_ABS", "SPEED", "BALANCE", "ROBUST"), N2 in ("N", "N/4", "1")
            h = spec.setup(p, HEPS, Dict{String,Any}("mode" => mode, "N2" => N2))
            r = spec.solve!(h)
            c = BH.check(p, r.x, nothing, ref.obj0)
            spec.update!(h, p2)
            r2 = spec.solve!(h)
            c2 = BH.check(p2, r2.x, nothing, ref2.obj0)
            @printf("  %-13s %-9s N2=%-3s (%2d) %-8s it %3d obj_err %.1e prim_rel %.1e | update %-8s it %3d obj_err %.1e prim_rel %.1e\n",
                    name, mode, N2, h.N2, r.status, r.iters, c.obj_err, c.prim_rel, r2.status, r2.iters, c2.obj_err, c2.prim_rel)
            @test r.status == :solved && r2.status == :solved
            @test c.obj_err < 1e-7 && c.prim_rel < 1e-7
            @test c2.obj_err < 1e-7 && c2.prim_rel < 1e-7
        end
    end
end

ENABLED && run()

end
