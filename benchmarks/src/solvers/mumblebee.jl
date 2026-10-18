# mumblebee.jl: Mumblebee (conic interior point on a clique tree) adapter.
#
# Mumblebee's standard form is  min (1/2) p'Qp - f'p  s.t.  B p = g,  p in K,
# K a product of cones over consecutive blocks of p (free, nonnegative,
# second-order). A canonical QP maps to it by an affine substitution
# x_e = T p + h of the extended variables x_e = (x, interval slacks, cone
# slacks), chosen as in the paper's benchmark (bench/central/run_julia.jl):
#
# * a variable bounded by singleton rows, lo <= x_j <= hi, becomes x_j = lo + w
#   with w, v >= 0 and the row w + v = hi - lo (one-sided: x_j = lo + w or
#   hi - w): fewer variables and rows than a slack beside a free x_j;
# * a cone block whose first row has no variables and whose other rows are
#   singletons alpha x_j on distinct variables puts those x_j into the cone
#   directly, x_j = (socb_r - c_r) / alpha, with the row c_1 = socb_1 (the
#   paper's (t, u) in SOC with t = ABAR);
# * any other interval row gets a slack s = a'x bounded as above, any other
#   cone block slacks c = socb - A_B x in the cone;
# * equality rows stay equalities.
#
# For a sequence, T and B do not change; h, f and g are recomputed from the
# new vectors and passed to `reinit!`, which keeps the symbolic analysis.

using Mumblebee.IPM: IPMProblem, IPMSettings, PositiveCone, CofreeCone, SecondOrderCone, AbstractCone
import Mumblebee.IPM as MBI
import Mumblebee
using CliqueTrees: AMF, ND, METISND
import Metis

struct MBRecipe
    n::Int
    ne::Int
    np::Int
    T::SpMat
    Pe::SpMat
    Be::SpMat                     # rows of B_e x_e = g_e
    Bbox::SpMat                   # w + v rows, on p
    Q::SpMat
    B::SpMat
    K::Vector{AbstractCone}
    s::Vector{Int}
    # h recipe: kind 0 none, 1 lower bound, 2 upper bound, 3 cone-direct socb[r]/alpha
    hkind::Vector{Int8}
    hsrc::Vector{Int}             # bound group (kinds 1, 2) or row (kind 3)
    hcoef::Vector{Float64}
    groups::Vector{Vector{Tuple{Int,Float64}}}   # bound group: (row, coefficient); coefficient 0 marks a slack's own row
    boxgroups::Vector{Int}        # the group of every Bbox row
    # g_e recipe: kind 1 l of an equality row, 2 zero, 3 socb of a row
    gkind::Vector{Int8}
    gsrc::Vector{Int}
end

function _group_bounds(p::QP, grp)
    lo = -Inf; hi = Inf
    for (i, a) in grp
        if a == 0.0
            lo = max(lo, p.l[i]); hi = min(hi, p.u[i])
        elseif a > 0
            lo = max(lo, p.l[i] / a); hi = min(hi, p.u[i] / a)
        else
            lo = max(lo, p.u[i] / a); hi = min(hi, p.l[i] / a)
        end
    end
    return lo, hi
end

function mb_recipe(p::QP)
    n = nvars(p); m = ncons(p)
    At = SpMat(p.A')                  # column i = row i of A
    rowvars(i) = (rv = rowvals(At); nz = nonzeros(At); [(rv[k], nz[k]) for k in nzrange(At, i)])
    soc = issocrow(p)
    # 1. direct cone blocks
    claimed = falses(n)
    direct = falses(length(p.socs))
    for (bi, B) in enumerate(p.socs)
        isempty(rowvars(first(B))) || continue
        ok = true; js = Int[]
        for r in B[2:end]
            rv = rowvars(r)
            (length(rv) == 1 && !claimed[rv[1][1]] && !(rv[1][1] in js) && rv[1][2] != 0) || (ok = false; break)
            push!(js, rv[1][1])
        end
        ok || continue
        direct[bi] = true; claimed[js] .= true
    end
    # 2. singleton interval rows -> bound groups of unclaimed variables
    vgroup = zeros(Int, n); groups = Vector{Vector{Tuple{Int,Float64}}}()
    slackrows = Int[]
    for i in 1:m
        (soc[i] || p.l[i] == p.u[i]) && continue
        rv = rowvars(i)
        if length(rv) == 1 && !claimed[rv[1][1]] && rv[1][2] != 0
            j, a = rv[1]
            if vgroup[j] == 0
                push!(groups, Tuple{Int,Float64}[]); vgroup[j] = length(groups)
            end
            push!(groups[vgroup[j]], (i, a))
        else
            push!(slackrows, i)
        end
    end
    # extended variables: x (n), interval slacks, cone slacks (general blocks and direct first rows)
    ns = length(slackrows)
    slackgroup = Int[]
    for i in slackrows
        push!(groups, [(i, 0.0)]); push!(slackgroup, length(groups))
    end
    conevars = Int[]                  # extended index of every cone slack, in block order
    ne = n + ns
    cone_ext = Vector{Vector{Int}}()  # per block: extended indices of its components (direct: x_j for r >= 2)
    cone_c1 = Int[]
    for (bi, B) in enumerate(p.socs)
        if direct[bi]
            ne += 1
            push!(cone_ext, [ne; [rowvars(r)[1][1] for r in B[2:end]]])
        else
            push!(cone_ext, collect((ne + 1):(ne + length(B)))); ne += length(B)
        end
    end
    # 3. p layout: free | nonneg | cones
    pfree = Int[]; pnn = 0
    kindx = zeros(Int8, ne)           # 1 free, 2 lower, 3 upper, 4 two-sided, 5 cone component
    grp_of = zeros(Int, ne)
    for j in 1:n
        claimed[j] && (kindx[j] = 5; continue)
        g = vgroup[j]
        if g == 0
            kindx[j] = 1
        else
            lo, hi = _group_bounds(p, groups[g]); grp_of[j] = g
            kindx[j] = isfinite(lo) && isfinite(hi) ? 4 : isfinite(lo) ? 2 : isfinite(hi) ? 3 : 1
        end
    end
    for (t, i) in enumerate(slackrows)
        j = n + t; g = slackgroup[t]; grp_of[j] = g
        lo, hi = _group_bounds(p, groups[g])
        kindx[j] = isfinite(lo) && isfinite(hi) ? 4 : isfinite(lo) ? 2 : isfinite(hi) ? 3 : 1
    end
    for ce in cone_ext, j in ce
        j > n + ns && (kindx[j] = 5)
    end
    nfree = count(==(1), kindx)
    nnn = count(k -> k == 2 || k == 3, kindx) + 2 * count(==(4), kindx)
    ncone = sum(length, p.socs; init = 0)
    np = nfree + nnn + ncone
    TI = Int[]; TJ = Int[]; TV = Float64[]
    hkind = zeros(Int8, ne); hsrc = zeros(Int, ne); hcoef = zeros(ne)
    BbI = Int[]; BbJ = Int[]; BbV = Float64[]; boxgroups = Int[]
    pf = 0; pn = nfree; pc = nfree + nnn
    for j in 1:ne
        k = kindx[j]
        if k == 1
            pf += 1; push!(TI, j); push!(TJ, pf); push!(TV, 1.0)
        elseif k == 2
            pn += 1; push!(TI, j); push!(TJ, pn); push!(TV, 1.0); hkind[j] = 1; hsrc[j] = grp_of[j]
        elseif k == 3
            pn += 1; push!(TI, j); push!(TJ, pn); push!(TV, -1.0); hkind[j] = 2; hsrc[j] = grp_of[j]
        elseif k == 4
            pn += 1; push!(TI, j); push!(TJ, pn); push!(TV, 1.0); hkind[j] = 1; hsrc[j] = grp_of[j]
            pn += 1                                  # v
            r = length(boxgroups) + 1
            push!(BbI, r); push!(BbJ, pn - 1); push!(BbV, 1.0)
            push!(BbI, r); push!(BbJ, pn); push!(BbV, 1.0)
            push!(boxgroups, grp_of[j])
        end
    end
    @assert pf == nfree && pn == nfree + nnn
    K = AbstractCone[]; s = Int[]
    nfree > 0 && (push!(K, CofreeCone()); push!(s, nfree))
    nnn > 0 && (push!(K, PositiveCone()); push!(s, nnn))
    for (bi, B) in enumerate(p.socs)
        ce = cone_ext[bi]
        for (t, j) in enumerate(ce)
            pc += 1
            if direct[bi] && t >= 2
                r = B[t]; a = rowvars(r)[1][2]
                push!(TI, j); push!(TJ, pc); push!(TV, -1.0 / a); hkind[j] = 3; hsrc[j] = r; hcoef[j] = 1.0 / a
            else
                push!(TI, j); push!(TJ, pc); push!(TV, 1.0)
            end
        end
        push!(K, SecondOrderCone()); push!(s, length(B))
    end
    @assert pc == np
    T = sparse(TI, TJ, TV, ne, np)
    # B_e rows
    BI = Int[]; BJ = Int[]; BV = Float64[]; gkind = Int8[]; gsrc = Int[]; r = 0
    addrow!(i, extra) = begin
        r += 1
        for (j, a) in rowvars(i); push!(BI, r); push!(BJ, j); push!(BV, a); end
        for (j, a) in extra; push!(BI, r); push!(BJ, j); push!(BV, a); end
    end
    for i in 1:m
        (!soc[i] && p.l[i] == p.u[i]) || continue
        addrow!(i, ()); push!(gkind, 1); push!(gsrc, i)
    end
    for (t, i) in enumerate(slackrows)
        addrow!(i, ((n + t, -1.0),)); push!(gkind, 2); push!(gsrc, 0)
    end
    for (bi, B) in enumerate(p.socs)
        ce = cone_ext[bi]
        if direct[bi]
            r += 1; push!(BI, r); push!(BJ, ce[1]); push!(BV, 1.0); push!(gkind, 3); push!(gsrc, first(B))
        else
            for (t, i) in enumerate(B)
                addrow!(i, ((ce[t], 1.0),)); push!(gkind, 3); push!(gsrc, i)
            end
        end
    end
    Be = sparse(BI, BJ, BV, r, ne)
    Bbox = sparse(BbI, BbJ, BbV, length(boxgroups), np)
    Pe = blockdiag(p.P, spzeros(ne - n, ne - n))
    Q = SpMat(T' * Pe * T); Q = SpMat((Q + Q') / 2); droptol!(Q, 0.0)
    Bm = SpMat([Be * T; Bbox])
    return MBRecipe(n, ne, np, T, Pe, Be, Bbox, Q, Bm, K, s, hkind, hsrc, hcoef, groups, boxgroups, gkind, gsrc)
end

"f and g of Mumblebee's form for the vectors of `p` (same structure as the recipe's QP)."
function mb_vectors(R::MBRecipe, p::QP)
    h = zeros(R.ne)
    glo = Dict{Int,Tuple{Float64,Float64}}()
    bnd(g) = get!(() -> _group_bounds(p, R.groups[g]), glo, g)
    for j in 1:R.ne
        k = R.hkind[j]
        k == 1 && (h[j] = bnd(R.hsrc[j])[1])
        k == 2 && (h[j] = bnd(R.hsrc[j])[2])
        k == 3 && (h[j] = p.socb[R.hsrc[j]] * R.hcoef[j])
    end
    qe = [p.q; zeros(R.ne - R.n)]
    f = -(R.T' * (R.Pe * h + qe))
    ge = [R.gkind[t] == 1 ? p.l[R.gsrc[t]] : R.gkind[t] == 3 ? p.socb[R.gsrc[t]] : 0.0 for t in eachindex(R.gkind)]
    gb = [(lh = bnd(g); lh[2] - lh[1]) for g in R.boxgroups]
    g = [ge - R.Be * h; gb]
    return f, g, h
end

mutable struct MBHandle
    R::MBRecipe
    solver::Any
    h::Vector{Float64}
end

const MB_STATUS = Dict("OPTIMAL" => :solved, "NEAR_OPTIMAL" => :almost_solved, "ITERATION_LIMIT" => :max_iter,
                       "STALLED" => :stalled, "NUMERICAL_FAILURE" => :failed)

function mumblebee_spec(; max_iter = 200)
    setup = function (p::QP, eps, v)
        R = mb_recipe(p)
        f, g, h = mb_vectors(R, p)
        alg = v["elim"] == "amf" ? AMF() : ND(AMF(), METISND())
        st = IPMSettings{Float64}(; elim_alg = alg, feas_tol = eps, gap_tol = eps, max_iter = max_iter, verbose = 0)
        prob = IPMProblem(R.Q, R.B, f, g, 0.0, R.K, R.s)
        return MBHandle(R, MBI.init(prob, st), h)
    end
    solve! = function (hd::MBHandle)
        r = MBI.solve!(hd.solver)
        x = (hd.R.T * r.p .+ hd.h)[1:hd.R.n]
        return SolveResult(x, nothing, get(MB_STATUS, string(r.status), :failed), r.niter, NaN)
    end
    update! = function (hd::MBHandle, p::QP)
        f, g, h = mb_vectors(hd.R, p)
        hd.h = h
        MBI.reinit!(hd.solver; f = f, g = g)
        return nothing
    end
    info = () -> Dict{String,Any}("package" => "Mumblebee", "path" => pkgdir(Mumblebee),
                                  "commit" => isdir(joinpath(pkgdir(Mumblebee), ".git")) ?
                                              git_state(pkgdir(Mumblebee); paths = ["src"]) :
                                              "e78d9b9a3a0a2f4c226bf2eb0cf20f662e7d676b (pinned as in the paper's bench/mpc)",
                                  "settings" => "feas_tol = gap_tol = eps, max_iter $max_iter, other IPMSettings defaults; ordering per variant",
                                  "warm_start" => "none (interior point); sequence mode keeps the symbolic analysis through reinit!(f, g), which restarts from Mumblebee's starting point (its iteration count can differ by one from a fresh setup: some internal state survives reinit!)")
    readback = function (hd::MBHandle)
        st = hd.solver.settings
        d = Dict{String,Any}(string(f) => string(getfield(st, f)) for f in fieldnames(typeof(st)))
        d["tols"] = Dict("feas_tol" => st.feas_tol, "gap_tol" => st.gap_tol)
        return d
    end
    return SolverSpec(name = "mumblebee", readback = readback, kind = :ipm, applicable = p -> true,
                      variants = [Dict{String,Any}("elim" => "amf"), Dict{String,Any}("elim" => "nd")],
                      setup = setup, solve! = solve!, update! = update!, warm! = nothing, info = info)
end
