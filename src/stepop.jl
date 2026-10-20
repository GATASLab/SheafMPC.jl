# stepop.jl: the step operator of a chain of reductions.
#
# In receding horizon only a few of the finest program's data change from one
# step to the next (the measured states, the references), and every level of a
# chain of reductions maps its parent's vectors to its own affinely:
#
#   xbar = X b_e,   q' = N'(Q xbar + q),   b_n' = (b_n - A xbar)[rows],
#   b_e' = b_e[cross] - delta xbar,
#
# and the conic QP of the last level reads its vectors off the coarsest
# program (q - L_s b_e, the hard edge targets and the node right-hand sides).
# So the QP vectors are an affine function of the changing entries `a` of the
# finest data, `K a + k`. `update!(reduced)` level by level streams every
# level's operators and full vectors (whose sizes do not shrink much along a
# chain); `StepOperator` composes the levels once, restricted to the declared
# active entries, and a step costs one sparse product of the size of the
# reduced QP and of the data.
#
# Duplicate rows. A pushforward along teams repeats the node rows of every
# member (one input cone per member and instant), and the composed row of
# each copy depends on the data of its whole team, so the stacked rows of K
# grow like (team size)^2. The difference of two copies (two members of the
# same team, the same row of A) depends mostly on the data near them: K
# stores one anchor row per chain of copies and the differences of
# consecutive copies (their negligible tails dropped), and a step sums them
# along the chain.
#
# Accuracy. The map is applied as k + K (a - a0), with k its value at the data
# a0 of the build, so round-off grows with the change of the data since the
# build. Three things keep it at the level of the level by level path's own:
# the composition (and k) is carried out in double-double arithmetic and
# rounded once (see `DDMat`; composed in Float64, the entries that come out of
# cancellations drift by about 1e-13 per unit of data change); the anchors,
# which sum the data of a whole team, and the largest entries of every link
# are summed with compensation; the sums along chains are carried in double
# length.
#
# The constant c of the QP objective (quadratic in the data) is not
# recomputed: it does not move the minimizer. `sync!(op)` runs the level by
# level update (the constant, every level's program and base point, for full
# lifts and checks).

"""
    data_index(P, kind, i) -> UnitRange{Int}

Positions in the flat data vector `[q; b_n; b_e]` of the program `P` (the
layout `StepOperator` declares active entries in): `kind = :q` the cost
vector of vertex `i`, `:bn` its node right-hand side, `:be` the target of edge
`i`.
"""
function data_index(P::SheafProgram, kind::Symbol, i::Integer)
    kind === :q && return vrange(P, i)
    kind === :bn && return c0dim(P) .+ rrange(P, i)
    kind === :be && return (c0dim(P) + noderows(P)) .+ erange(P, i)
    throw(ArgumentError("kind must be :q, :bn or :be"))
end

"""
An affine map whose outputs are anchors or links of chains: `out = c + C (x - x0)`
(`c`: the outputs at `x0`, in chained form), then along every chain `out[i] += out[prev[i]]`
(in `order`). The rows of chains (`crows`, their rows of C in the columns of `Ct`) are
summed with compensation (dot2: products by fma, sums by two-sum, `x - x0` carried to
double length) and accumulated along the chains in double length: a plain sum loses
about eps times the sum of the magnitudes of its terms, an anchor depends on the data of
a whole team, and a copy far down a chain would inherit the losses of every link before
it. `dust[i]` is the absolute sum of the entries dropped from row `i`.
"""
struct ChainedMap
    C::SparseMatrixCSC{Float64}
    Ct::SparseMatrixCSC{Float64}
    Ctlo::SparseMatrixCSC{Float64}        # the rounding errors of the anchors' entries (columns as Ct)
    crows::Vector{Int32}
    c::Vector{Float64}
    x0::Vector{Float64}
    dx::Vector{Float64}
    dxl::Vector{Float64}
    prev::Vector{Int32}
    order::Vector{Int32}
    dust::Vector{Float64}
    hi::Vector{Float64}
    lo::Vector{Float64}
    iscomp::BitVector
    rep::Vector{Int32}            # per input: the first input of its class (0: in none, its whole change); empty: no deviations
    devrows::BitVector            # the rows applied to the deviations (the links)
    dxp::Vector{Float64}
    dxpl::Vector{Float64}
end

SparseArrays.nnz(F::ChainedMap) = nnz(F.C) + nnz(F.Ct)

apply!(out::AbstractVector, F::ChainedMap, x::AbstractVector) = _apply!(out, _differences!(F, x))

"The change of the inputs since `x0`, in double length, and (with classes) its departure from them."
function _differences!(F::ChainedMap, x::AbstractVector)
    dx, dxl, x0 = F.dx, F.dxl, F.x0
    @inbounds for j in eachindex(dx)
        a, b = x[j], -x0[j]
        d = a + b
        bb = d - a
        dx[j] = d
        dxl[j] = (a - (d - bb)) + (b - bb)
    end
    if !isempty(F.rep)
        # the departure of every input's change from that of its class's first input
        dxp, dxpl, rp = F.dxp, F.dxpl, F.rep
        @inbounds for j in eachindex(dx)
            r = rp[j]
            if r == 0
                dxp[j] = dx[j]; dxpl[j] = dxl[j]
            else
                h, l = _dd_add(dx[j], dxl[j], -dx[r], -dxl[r])
                dxp[j] = h; dxpl[j] = l
            end
        end
    end
    return F
end

"The map applied to the differences in `F`'s buffers."
function _apply!(out::AbstractVector, F::ChainedMap)
    dx, dxl = F.dx, F.dxl
    copyto!(out, F.c)
    mul!(out, F.C, dx, 1.0, 1.0)
    isempty(F.crows) && return out
    hi, lo = F.hi, F.lo
    dxp, dxpl = isempty(F.rep) ? (dx, dxl) : (F.dxp, F.dxpl)
    _compensated!(hi, lo, out, F.Ct, F.Ctlo, F.crows, dx, dxl, dxp, dxpl, F.devrows)
    prev = F.prev
    @inbounds for i in F.order
        p = prev[i]
        hi[i], lo[i] = _dd_add(hi[i], lo[i], hi[p], lo[p])
    end
    @inbounds for i in F.crows
        out[i] = hi[i] + lo[i]
    end
    return out
end

"""
Rows `crows` of `c` plus their compensated parts (columns of `Ct`, `Ctlo`) times `dx + dxl`
(the rows `devrows`: times `dxp + dxpl`), by dot2, as `hi + lo`.
"""
function _compensated!(hi, lo, c, Ct::SparseMatrixCSC, Ctlo::SparseMatrixCSC, crows, dx0, dxl0, dxp, dxpl, devrows)
    rv, nz = rowvals(Ct), nonzeros(Ct)
    rl, nl = rowvals(Ctlo), nonzeros(Ctlo)
    @inbounds for (t, i) in enumerate(crows)
        dx, dxl = devrows[i] ? (dxp, dxpl) : (dx0, dxl0)
        e = 0.0
        for k in nzrange(Ctlo, t)
            e += nl[k] * dx[rl[k]]
        end
        # two interleaved sums (the two-sum chains are latency bound), merged at the end
        s1 = c[i]; s2 = 0.0; e2 = 0.0
        r = nzrange(Ct, t)
        k = first(r)
        while k + 1 <= last(r)
            v = nz[k]; j = rv[k]; w = nz[k+1]; l = rv[k+1]
            p = v * dx[j]; q = w * dx[l]
            e += fma(v, dx[j], -p) + v * dxl[j]
            e2 += fma(w, dx[l], -q) + w * dxl[l]
            t1 = s1 + p; b1 = t1 - s1; e += (s1 - (t1 - b1)) + (p - b1); s1 = t1
            t2 = s2 + q; b2 = t2 - s2; e2 += (s2 - (t2 - b2)) + (q - b2); s2 = t2
            k += 2
        end
        if k == last(r)
            v = nz[k]; j = rv[k]
            p = v * dx[j]
            e += fma(v, dx[j], -p) + v * dxl[j]
            t1 = s1 + p; b1 = t1 - s1; e += (s1 - (t1 - b1)) + (p - b1); s1 = t1
        end
        h, l = _dd_add(s1, e, s2, e2)
        hi[i] = h; lo[i] = l
    end
    return hi
end

"""
    StepOperator(reduced, qmap, active; lift_rows = Int[], chains = :auto, lift_chains = :auto,
                 droptol = 1e-15, chunk = :auto, invariant = nothing, link_droptol = droptol)

The QP vectors of the last level of the chain of reductions `reduced` (as
`qmap = QPMap(reduced.program)` computes them: `q` and the right-hand sides of
every row, `bfull`) as one precomposed affine map of the entries `active` of
the finest program's flat data (positions as `data_index` gives them). Every
other entry of the finest data is held at its value when the operator is
built. `update!(op)` reads the active entries from the finest program and
writes `qmap.q`, `qmap.bfull` and `qmap.b`; equal to `update!` of every level
and `refresh!(qmap, reduced.program)` (to round-off), except for the
constant `qmap.c`, which keeps its value (`sync!(op)` recomputes it).

`lift_rows`: coordinates of the finest plan to lift from a solution `y` of the
last level, `lift!(x, op, y)` (the inputs the controller applies, say),
precomposed as well from `y` and the active data.

Chains of duplicate rows (`chains = :auto`: node rows, and second-order cone
blocks, of the last level whose rows of A agree to 1e-9 relative;
`lift_chains = :auto`: lifted coordinates with equal rows of the composite
basis; or the previous row in its chain of every row, 0 for none) store one
anchor and the differences of consecutive copies; `chains = nothing` stores
every row. From every row the smallest entries are dropped while their sum
stays below `droptol` times the row's scale over the chain's length: an
output differs from the exact composition by at most `op.dust` times the
largest change of an active entry since the build, plus round-off. The
composition runs in double-double arithmetic over blocks of `chunk` active
entries (`:auto`: 64 blocks, of at least 2048 entries).

`invariant = W`: directions of the data (one row per active entry, each
column the indicator of a class of entries, a team's data moving as one, say)
along which the differences of chained copies do not change. The links are
then applied to the departure of the data from these directions (every entry's
change minus that of the first entry of its class), which is small when the
data move nearly along them, and lose their entries while these sum to at
most `link_droptol` times the rows' scale over the chain's length. A chained
QP row is off by at most `op.linkbound[i] * dev + op.linkboundW[i] * tau`, plus
round-off, with `dev` the largest departure and `tau` the largest change of a
class's first entry since the build (`linkboundW`, the size of the links along
`W`, is round-off when `W` is right).
"""
mutable struct StepOperator
    chain::Vector{ReducedProgram}
    qmap::QPMap
    root::SheafProgram
    active::Vector{Int}
    kind::Vector{Int8}            # runs of active entries read from one vector: 1 q, 2 b_n, 3 b_e,
    owner::Vector{Int32}          # the vertex or edge,
    local_index::Vector{Int32}    # the first entry in it,
    seglen::Vector{Int32}         # the run's length
    segdest::Vector{Int32}        # and its first position in `a`
    a::Vector{Float64}
    nq::Int
    qb::ChainedMap                # [q; bfull]
    out::Vector{Float64}
    cons::Union{ChainedMap,Nothing}
    cons_tol::Float64
    cbuf::Vector{Float64}
    lift_rows::Vector{Int}
    lift::Union{ChainedMap,Nothing}
    ya::Vector{Float64}
    feasible::Bool
    dust::Float64
    deviation::Bool               # links applied to the data's departure from the invariant directions,
    linkbound::Vector{Float64}    # a chained QP row off by at most linkbound[i] * dev + linkboundW[i] * tau
    linkboundW::Vector{Float64}
    build_seconds::Float64
end

function Base.show(io::IO, op::StepOperator)
    nl = op.lift === nothing ? 0 : nnz(op.lift)
    print(io, "StepOperator($(length(op.chain)) levels, $(length(op.active)) active entries -> $(op.nq) + ",
          "$(length(op.out) - op.nq) QP entries, nnz $(nnz(op.qb)), lift $(length(op.lift_rows)) rows nnz $nl, ",
          @sprintf("built in %.2f s)", op.build_seconds))
end

# The composition in double-double arithmetic. Composing the levels in
# Float64 rounds every intermediate product, and the composed entries that
# come out of cancellations carry errors far above their own round-off; the
# composed map then drifts from the level by level path in proportion to the
# change of the data since the build (about 1e-13 per unit at n = 256). Each
# entry is carried as an unevaluated sum hi + lo (products by fma, sums by
# two-sum) and rounded once at the end, so the composed map is the exact
# composition of the stored operators to about 1e-30, rounded.

"A sparse matrix whose entries are double-double numbers `hi + lo` (`lo` empty: zero)."
struct DDMat
    m::Int
    n::Int
    colptr::Vector{Int}
    rowval::Vector{Int}
    hi::Vector{Float64}
    lo::Vector{Float64}
end

DDMat(A::SparseMatrixCSC) = DDMat(size(A, 1), size(A, 2), Vector{Int}(SparseArrays.getcolptr(A)), Vector{Int}(rowvals(A)),
                                  Vector{Float64}(nonzeros(A)), Float64[])
"The selection matrix `S` with `(S Z)[t] = Z[rows[t]]`."
_selection(rows::AbstractVector{<:Integer}, n::Int) = DDMat(sparse(1:length(rows), rows, 1.0, length(rows), n))

_dims(A::DDMat) = (A.m, A.n)
_dims(A::SparseMatrixCSC) = size(A)
_cp(A::DDMat) = A.colptr
_cp(A::SparseMatrixCSC) = SparseArrays.getcolptr(A)
_rv(A::DDMat) = A.rowval
_rv(A::SparseMatrixCSC) = rowvals(A)
_hi(A::DDMat) = A.hi
_hi(A::SparseMatrixCSC) = nonzeros(A)
_lo(A::DDMat) = A.lo
_lo(A::SparseMatrixCSC) = Float64[]
SparseArrays.nnz(A::DDMat) = length(A.hi)

@inline function _two_prod(a::Float64, b::Float64)
    p = a * b
    return p, fma(a, b, -p)
end
@inline function _dd_add(h1::Float64, l1::Float64, h2::Float64, l2::Float64)
    s = h1 + h2
    bb = s - h1
    e = (h1 - (s - bb)) + (h2 - bb) + (l1 + l2)
    h = s + e
    return h, e - (h - s)
end

"The product `A B` (`A` a sparse matrix or a double-double one), in double-double arithmetic."
function _ddmul(A, B::DDMat)
    m, k = _dims(A)
    k == B.m || throw(DimensionMismatch("inner dimensions $k and $(B.m)"))
    acph, acpl = Vector{Float64}(undef, m), Vector{Float64}(undef, m)       # read only where marked
    mark = zeros(Int, m)
    rows = Int[]
    cpA, rvA, hA, lA = _cp(A), _rv(A), _hi(A), _lo(A)
    hasAl, hasBl = !isempty(lA), !isempty(B.lo)
    colptr = Vector{Int}(undef, B.n + 1)
    colptr[1] = 1
    rv = Int[]; H = Float64[]; L = Float64[]
    @inbounds for j in 1:B.n
        empty!(rows)
        for kb in B.colptr[j]:(B.colptr[j+1]-1)
            kk = B.rowval[kb]
            bh = B.hi[kb]
            bl = hasBl ? B.lo[kb] : 0.0
            for ka in cpA[kk]:(cpA[kk+1]-1)
                i = Int(rvA[ka])
                ah = hA[ka]
                ph, pl = _two_prod(ah, bh)
                pl += ah * bl
                hasAl && (pl += lA[ka] * bh)
                if mark[i] != j
                    mark[i] = j
                    push!(rows, i)
                    acph[i] = ph; acpl[i] = pl
                else
                    acph[i], acpl[i] = _dd_add(acph[i], acpl[i], ph, pl)
                end
            end
        end
        sort!(rows)
        for i in rows
            push!(rv, i); push!(H, acph[i]); push!(L, acpl[i])
        end
        colptr[j+1] = length(rv) + 1
    end
    return DDMat(m, B.n, colptr, rv, H, L)
end

"`A + s B` in double-double arithmetic (`s = ±1`)."
function _ddadd(A::DDMat, B::DDMat, s::Float64 = 1.0)
    (A.m, A.n) == (B.m, B.n) || throw(DimensionMismatch("$(A.m) x $(A.n) and $(B.m) x $(B.n)"))
    colptr = Vector{Int}(undef, A.n + 1)
    colptr[1] = 1
    rv = Int[]; H = Float64[]; L = Float64[]
    sizehint!(rv, nnz(A) + nnz(B)); sizehint!(H, nnz(A) + nnz(B)); sizehint!(L, nnz(A) + nnz(B))
    hasAl, hasBl = !isempty(A.lo), !isempty(B.lo)
    @inbounds for j in 1:A.n
        p, pe = A.colptr[j], A.colptr[j+1] - 1
        q, qe = B.colptr[j], B.colptr[j+1] - 1
        while p <= pe || q <= qe
            ra = p <= pe ? A.rowval[p] : typemax(Int)
            rb = q <= qe ? B.rowval[q] : typemax(Int)
            if ra < rb
                push!(rv, ra); push!(H, A.hi[p]); push!(L, hasAl ? A.lo[p] : 0.0); p += 1
            elseif rb < ra
                push!(rv, rb); push!(H, s * B.hi[q]); push!(L, hasBl ? s * B.lo[q] : 0.0); q += 1
            else
                h, l = _dd_add(A.hi[p], hasAl ? A.lo[p] : 0.0, s * B.hi[q], hasBl ? s * B.lo[q] : 0.0)
                push!(rv, ra); push!(H, h); push!(L, l); p += 1; q += 1
            end
        end
        colptr[j+1] = length(rv) + 1
    end
    return DDMat(A.m, A.n, colptr, rv, H, L)
end

"Rows `r` (a range) of `A`."
function _ddrows(A::DDMat, r::UnitRange{Int})
    colptr = Vector{Int}(undef, A.n + 1)
    colptr[1] = 1
    rv = Int[]; H = Float64[]; L = Float64[]
    hasl = !isempty(A.lo)
    @inbounds for j in 1:A.n
        for k in A.colptr[j]:(A.colptr[j+1]-1)
            i = A.rowval[k]
            if first(r) <= i <= last(r)
                push!(rv, i - first(r) + 1); push!(H, A.hi[k]); push!(L, hasl ? A.lo[k] : 0.0)
            end
        end
        colptr[j+1] = length(rv) + 1
    end
    return DDMat(length(r), A.n, colptr, rv, H, L)
end

"The rows of the blocks stacked."
function _ddvcat(blocks::DDMat...)
    n = blocks[1].n
    colptr = Vector{Int}(undef, n + 1)
    colptr[1] = 1
    tot = sum(nnz, blocks)
    rv = Vector{Int}(undef, tot); H = Vector{Float64}(undef, tot); L = Vector{Float64}(undef, tot)
    t = 0
    @inbounds for j in 1:n
        off = 0
        for A in blocks
            hasl = !isempty(A.lo)
            for k in A.colptr[j]:(A.colptr[j+1]-1)
                t += 1
                rv[t] = A.rowval[k] + off; H[t] = A.hi[k]; L[t] = hasl ? A.lo[k] : 0.0
            end
            off += A.m
        end
        colptr[j+1] = t + 1
    end
    return DDMat(sum(A.m for A in blocks), n, colptr, rv, H, L)
end

"The rounding error of `A` (its entries minus their Float64 roundings), in the rows `rows`."
function _ddresidual(A::DDMat, rows::BitVector)
    hasl = !isempty(A.lo)
    I = Int[]; J = Int[]; V = Float64[]
    hasl || return spzeros(A.m, A.n)
    @inbounds for j in 1:A.n, k in A.colptr[j]:(A.colptr[j+1]-1)
        i = A.rowval[k]
        rows[i] || continue
        h, l = A.hi[k], A.lo[k]
        v = h + l
        r = (h - v) + l
        r == 0 || (push!(I, i); push!(J, j); push!(V, r))
    end
    return sparse(I, J, V, A.m, A.n)
end

"Rounded to a sparse Float64 matrix (exact zeros dropped)."
function _ddround(A::DDMat)
    hasl = !isempty(A.lo)
    I = Int[]; J = Int[]; V = Float64[]
    @inbounds for j in 1:A.n, k in A.colptr[j]:(A.colptr[j+1]-1)
        v = hasl ? A.hi[k] + A.lo[k] : A.hi[k]
        v == 0 && continue
        push!(I, A.rowval[k]); push!(J, j); push!(V, v)
    end
    return sparse(I, J, V, A.m, A.n)
end

"One level of the composition: the parent's data block `Z` (rows `[q; b_n; b_e]`) to the level's, `X b_e`, and `b_e`."
function _compose_level(R::ReducedProgram, Z::DDMat)
    Pf = getfield(R, :fine)
    n0, r0 = c0dim(Pf), noderows(Pf)
    Zq = _ddrows(Z, 1:n0)
    Zb = _ddrows(Z, (n0+1):(n0+r0))
    Ze = _ddrows(Z, (n0+r0+1):Z.m)
    XE = _ddmul(R.X, Ze)
    Zq2 = _ddmul(R.Nt, _ddadd(_ddmul(R.Qn, XE), Zq))
    Zb2 = _ddmul(_selection(R.rowmap, r0), _ddadd(Zb, _ddmul(R.An, XE), -1.0))
    Ze2 = _ddadd(_ddmul(_selection(R.xrows, Ze.m), Ze), _ddmul(R.Dx, XE), -1.0)
    return _ddvcat(Zq2, Zb2, Ze2), XE, Ze
end

"""
The rows of `K` in chained form, rounded, and the rounding errors of the anchors' entries:
a row with `prev[i] > 0` becomes `K[i] - K[prev[i]]` (dropped down to `linktol`, and its
products with the columns of `W`, if any, pushed to `dws`).
From every row the smallest entries are dropped as long as their absolute sum stays below
`droptol` times the row's scale (the largest entry of `K[i]`, or of `K[prev[i]]`) divided
by the length `clen[i]` of its chain, and the sum is added to `dust[i]`: along a chain the
dropped entries sum to at most `droptol` times the rows' scale, and an output moves by at
most that times the largest change of an active entry.
"""
function _chain_rows(Kd::DDMat, prev::Vector{Int32}, droptol::Float64, dust::Vector{Float64},
                     S::SparseMatrixCSC, clen::Vector{Int32}, anchors::BitVector; linktol::Float64 = droptol,
                     W::Union{SparseMatrixCSC,Nothing} = nothing, dws::Vector = [])
    K = _ddround(Kd)
    Klo = _ddresidual(Kd, anchors)
    Dd = nnz(S) == 0 ? Kd : _ddadd(Kd, _ddmul(S, Kd), -1.0)
    D = _ddround(Dd)
    # the links' products with the invariant directions, for their bound
    W === nothing || push!(dws, _ddround(_ddmul(Dd, DDMat(W))))
    m, n = size(K)
    sc = zeros(m)
    rk, nk = rowvals(K), nonzeros(K)
    @inbounds for k in eachindex(nk)
        sc[rk[k]] = max(sc[rk[k]], abs(nk[k]))
    end
    Dt = SparseMatrixCSC{Float64,Int}(sparse(transpose(D)))
    rv, nz = rowvals(Dt), nonzeros(Dt)
    I = Int[]; J = Int[]; V = Float64[]
    sizehint!(I, nnz(D)); sizehint!(J, nnz(D)); sizehint!(V, nnz(D))
    perm = Int[]; mags = Float64[]
    @inbounds for i in 1:m
        r = nzrange(Dt, i)
        isempty(r) && continue
        p = prev[i]
        budget = (p > 0 ? linktol : droptol) * max(sc[i], p > 0 ? sc[p] : 0.0) / clen[i]
        resize!(mags, length(r))
        for (t, k) in enumerate(r)
            mags[t] = abs(nz[k])
        end
        resize!(perm, length(r))
        sortperm!(perm, mags)
        cum = 0.0
        cut = 0
        for t in perm
            mags[t] == 0 && (cut += 1; continue)
            cum + mags[t] <= budget || break
            cum += mags[t]
            cut += 1
        end
        dust[i] += cum
        for t in perm[(cut+1):end]
            k = r[t]
            push!(I, i); push!(J, rv[k]); push!(V, nz[k])
        end
    end
    return sparse(I, J, V, m, n), Klo
end

"The anchors of chains: rows that are no link but have one."
function _anchors(prev::Vector{Int32})
    a = falses(length(prev))
    for i in eachindex(prev)
        prev[i] > 0 && prev[prev[i]] == 0 && (a[prev[i]] = true)
    end
    return a
end

"Every link of a chain must lead back to an anchor (no cycles)."
function _check_chains(prev::Vector{Int32})
    for i in eachindex(prev)
        j, steps = i, 0
        while prev[j] > 0
            j = prev[j]; steps += 1
            steps > length(prev) && throw(ArgumentError("the chains have a cycle"))
        end
    end
end

"The length of the chain of every row (1 for a row in none)."
function _chain_lengths(prev::Vector{Int32})
    head = zeros(Int32, length(prev))
    for i in _chain_order(prev)               # every link after its predecessor
        head[i] = head[prev[i]] == 0 ? prev[i] : head[prev[i]]
    end
    cnt = zeros(Int32, length(prev))
    for i in eachindex(prev)
        h = head[i] == 0 ? i : head[i]
        cnt[h] += 1
    end
    return Int32[cnt[head[i] == 0 ? i : head[i]] for i in eachindex(prev)]
end

"The selection `S` with `(S K)[i] = K[prev[i]]` (zero rows for anchors)."
function _link_matrix(prev::Vector{Int32})
    linked = findall(>(0), prev)
    return sparse(linked, Int.(prev[linked]), 1.0, length(prev), length(prev))
end

"""
Chains of units (a unit is a row or a second-order cone block) whose rows of `At` (the
transpose, columns are rows) have the same patterns and values agreeing to `tol` relative:
the previous row of every row (0 for the first unit of a chain).
"""
function _unit_chains(At::SparseMatrixCSC, units::Vector{Vector{Int}}, nrow::Int; tol::Float64 = 1e-9)
    prev = zeros(Int32, nrow)
    pat(i) = view(rowvals(At), nzrange(At, i))
    vals(i) = view(nonzeros(At), nzrange(At, i))
    function close(u, v)
        for (r, s) in zip(u, v)
            a, b = vals(r), vals(s)
            isempty(a) && continue
            sc = max(1.0, maximum(abs, b))
            for k in eachindex(a)
                abs(a[k] - b[k]) <= tol * sc || return false
            end
        end
        return true
    end
    lasts = Dict{Vector{Vector{Int}},Vector{Int}}()
    for (u, rows) in enumerate(units)
        key = [collect(Int, pat(r)) for r in rows]
        all(isempty, key) && continue
        lst = get!(lasts, key, Int[])
        hit = 0
        for (j, w) in enumerate(lst)
            close(rows, units[w]) && (hit = j; break)
        end
        if hit == 0
            push!(lst, u)
        else
            w = lst[hit]
            for (r, s) in zip(rows, units[w])
                prev[r] = s
            end
            lst[hit] = u
        end
    end
    return prev
end

"The order in which chained outputs are summed (every link after its predecessor)."
function _chain_order(prev::Vector{Int32})
    order = Int32[]
    done = falses(length(prev))
    for i in eachindex(prev)
        done[i] && continue
        stack = Int32[]
        j = Int32(i)
        while j > 0 && !done[j]
            push!(stack, j)
            j = prev[j]
        end
        for k in reverse(stack)
            done[k] = true
            prev[k] > 0 && push!(order, k)
        end
    end
    return order
end

"A chained map from its column blocks (outputs x inputs, and the anchors' rounding errors) and its value `truth` at the inputs `x0` (in chained form)."
function _chained_map(pairs::Vector, prev::Vector{Int32}, dust::Vector{Float64}, truth::Vector{Float64},
                      x0::Vector{Float64}; head::Int = 8, rep::Vector{Int32} = Int32[])
    C = SparseMatrixCSC{Float64,Int}(reduce(hcat, [p[1] for p in pairs]))
    Clo = SparseMatrixCSC{Float64,Int}(reduce(hcat, [p[2] for p in pairs]))
    tv = copy(truth)
    # the rows of chains are summed with compensation: anchors whole, links in their `head` largest
    # entries (whole when they are applied to the deviations)
    anchor = _anchors(prev)
    devrows = isempty(rep) ? falses(length(prev)) : prev .> 0
    inchain = anchor .| (prev .> 0)
    crows = Int32.(findall(inchain))
    Ct = SparseMatrixCSC{Float64,Int}(sparse(transpose(C)))
    rv, nz = rowvals(Ct), nonzeros(Ct)
    comp = falses(nnz(Ct))
    for i in crows
        r = nzrange(Ct, i)
        if anchor[i] || devrows[i] || length(r) <= head
            comp[r] .= true
        else
            p = partialsortperm(abs.(view(nz, r)), 1:head; rev = true)
            comp[r[p]] .= true
        end
    end
    J = [j for j in 1:size(Ct, 2) for _ in nzrange(Ct, j)]                 # the output of every entry
    pos = zeros(Int, length(prev)); pos[crows] .= 1:length(crows)
    c = comp
    Ctc = sparse(rv[c], pos[J[c]], nz[c], size(Ct, 1), length(crows))
    C = _compact(sparse(J[.!c], rv[.!c], nz[.!c], size(C)...))
    Ctlo = _compact(SparseMatrixCSC{Float64,Int}(sparse(transpose(Clo[crows, :]))))
    nx = length(x0)
    return ChainedMap(C, _compact(Ctc), Ctlo, crows, tv, copy(x0), zeros(nx), zeros(nx), prev, _chain_order(prev), dust,
                      zeros(length(prev)), zeros(length(prev)), inchain, rep, devrows, zeros(nx), zeros(nx))
end

function StepOperator(Rtop::ReducedProgram, M::QPMap, active::AbstractVector{<:Integer}; lift_rows = Int[],
                      chains = :auto, lift_chains = :auto, droptol::Real = 1e-15, chunk = :auto,
                      invariant::Union{AbstractMatrix,Nothing} = nothing, link_droptol::Real = droptol)
    t0 = time_ns()
    chain = reduction_chain(Rtop)
    P0 = getfield(chain[1], :fine)
    Pc = getfield(Rtop, :program)
    nz0 = c0dim(P0) + noderows(P0) + c1dim(P0)
    act = collect(Int, active)
    allunique(act) && all(j -> 1 <= j <= nz0, act) || throw(ArgumentError("active entries must be distinct positions in 1:$nz0"))
    Winv = invariant === nothing ? nothing : SparseMatrixCSC{Float64,Int}(sparse(invariant))
    rep = Int32[]
    if Winv !== nothing
        size(Winv, 1) == length(act) || throw(DimensionMismatch("invariant must have one row per active entry"))
        # class indicators: the first entry of every class is the one the others are measured from
        rep = zeros(Int32, length(act))
        cnt = zeros(Int, length(act))
        for c in 1:size(Winv, 2)
            r = rowvals(Winv)[nzrange(Winv, c)]
            isempty(r) && continue
            all(==(1.0), nonzeros(Winv)[nzrange(Winv, c)]) || throw(ArgumentError("invariant must have 0/1 columns"))
            rep[r] .= minimum(r); cnt[r] .+= 1
        end
        all(<=(1), cnt) || throw(ArgumentError("every active entry may be in one class of invariant only"))
    end
    # where every active entry is read from
    n0, r0 = c0dim(P0), noderows(P0)
    kind = Vector{Int8}(undef, length(act)); owner = similar(act, Int32); loc = similar(act, Int32)
    for (j, z) in enumerate(act)
        if z <= n0
            v = searchsortedlast(P0.offsets, z - 1); kind[j] = 1; owner[j] = v; loc[j] = z - P0.offsets[v]
        elseif z <= n0 + r0
            r = z - n0; v = searchsortedlast(P0.row_offsets, r - 1); kind[j] = 2; owner[j] = v; loc[j] = r - P0.row_offsets[v]
        else
            r = z - n0 - r0; e = searchsortedlast(P0.edge_offsets, r - 1); kind[j] = 3; owner[j] = e; loc[j] = r - P0.edge_offsets[e]
        end
    end
    na = length(act)
    a0 = zeros(na)
    # runs of consecutive entries of one vector
    sk = Int8[]; so = Int32[]; sl = Int32[]; sn = Int32[]; sd = Int32[]
    for j in eachindex(act)
        if j > 1 && kind[j] == sk[end] && owner[j] == so[end] && loc[j] == sl[end] + sn[end]
            sn[end] += 1
        else
            push!(sk, kind[j]); push!(so, owner[j]); push!(sl, loc[j]); push!(sn, 1); push!(sd, j)
        end
    end
    kind, owner, loc = sk, so, sl
    _gather!(a0, P0, kind, owner, loc, sn, sd)
    # the level by level path at the current data: the outputs the constants are read from
    for R in chain
        update!(R)
    end
    refresh!(M, Pc)
    nq = length(M.q)
    nb = length(M.bfull)
    nout = nq + nb
    # chains of duplicate rows of the QP
    prev = zeros(Int32, nout)
    if chains === :auto
        full = sheaf_qp(Pc)
        At = SparseMatrixCSC{Float64,Int}(sparse(transpose(full.A)))
        insoc = falses(nb)
        units = Vector{Int}[]
        for B in full.socs
            insoc[B] .= true
            push!(units, collect(B))
        end
        for i in (M.nh+1):nb
            insoc[i] || push!(units, [i])
        end
        p = _unit_chains(At, units, nb)
        @inbounds for i in 1:nb
            p[i] > 0 && (prev[nq+i] = nq + p[i])
        end
    elseif chains isa AbstractVector{<:Integer}
        length(chains) == nb || throw(DimensionMismatch("chains must give the previous row of every one of the $nb rows"))
        @inbounds for i in 1:nb
            chains[i] > 0 && (prev[nq+i] = nq + chains[i])
        end
        _check_chains(prev)
    elseif chains !== nothing
        throw(ArgumentError("chains must be :auto, nothing or the previous row of every row"))
    end
    # the lifted coordinates: the composite basis restricted to them, level by level
    sel = collect(Int, lift_rows)
    Nsel = DDMat[_selection(sel, c0dim(P0))]
    if !isempty(sel)
        for R in chain
            push!(Nsel, _ddmul(Nsel[end], DDMat(R.N)))
        end
    end
    ny = c0dim(Pc)
    lprev = zeros(Int32, length(sel))
    if !isempty(sel) && lift_chains === :auto
        Ly = _ddround(Nsel[end])
        lprev = _unit_chains(SparseMatrixCSC{Float64,Int}(sparse(transpose(Ly))), [[i] for i in eachindex(sel)], length(sel))
    elseif lift_chains isa AbstractVector{<:Integer}
        length(lift_chains) == length(sel) || throw(DimensionMismatch("lift_chains must give the previous row of every lifted row"))
        lprev = Int32.(lift_chains)
        _check_chains(lprev)
    end
    # consistency rows of every level
    crows = [size(R.Cons, 1) for R in chain]
    ncons = sum(crows)
    # compose over blocks of active entries
    qdust = zeros(nout); ldust = zeros(length(sel))
    Sq, Sl = _link_matrix(prev), _link_matrix(lprev)
    cq, cl = _chain_lengths(prev), _chain_lengths(lprev)
    aq, al = _anchors(prev), _anchors(lprev)
    chunk = chunk === :auto ? max(2048, cld(na, 64)) : Int(chunk)
    # the columns Z (data of the finest program) through every level: the QP vectors K, the
    # lifted coordinates' base point L, the consistency rows C
    function compose(Z::DDMat)
        L = isempty(sel) ? nothing : DDMat(length(sel), Z.n, ones(Int, Z.n + 1), Int[], Float64[], Float64[])
        C = SparseMatrixCSC{Float64,Int}[]
        for (k, R) in enumerate(chain)
            Z, XE, Ze = _compose_level(R, Z)
            crows[k] > 0 && push!(C, _ddround(_ddmul(R.Cons, Ze)))
            L === nothing || (L = _ddadd(L, _ddmul(Nsel[k], XE)))
        end
        nqc, rc = c0dim(Pc), noderows(Pc)
        Zq = _ddrows(Z, 1:nqc)
        Zb = _ddrows(Z, (nqc+1):(nqc+rc))
        Ze = _ddrows(Z, (nqc+rc+1):Z.m)
        K = _ddvcat(_ddadd(Zq, _ddmul(M.Ls, Ze), -1.0), _ddmul(_selection(M.hard_rows, Ze.m), Ze), Zb)
        return K, L, C
    end
    qblocks = Any[]; lblocks = Any[]; cblocks = Any[]; dws = SparseMatrixCSC{Float64,Int}[]
    for c0 in 1:chunk:max(na, 1)
        na == 0 && break
        cols = c0:min(na, c0 + chunk - 1)
        nc = length(cols)
        K, L, C = compose(DDMat(nz0, nc, collect(1:(nc+1)), act[cols], ones(nc), Float64[]))   # column t: the unit vector of act[t]
        push!(qblocks, _chain_rows(K, prev, Float64(droptol), qdust, Sq, cq, aq; linktol = Float64(link_droptol),
                                   W = Winv === nothing ? nothing : Winv[cols, :], dws = dws))
        L === nothing || push!(lblocks, _chain_rows(L, lprev, Float64(droptol), ldust, Sl, cl, al))
        isempty(C) || push!(cblocks, reduce(vcat, C))
    end
    # the outputs at the build's data, in the same arithmetic (the whole data vector as one column)
    fd = FlatData(P0)
    z0 = sparse([fd.q; fd.bn; fd.be])
    K0, L0, C0 = compose(DDMat(nz0, 1, [1, nnz(z0) + 1], rowvals(z0), nonzeros(z0), Float64[]))
    chained0(K, S) = vec(Matrix(nnz(S) == 0 ? _ddround(K) : _ddround(_ddadd(K, _ddmul(S, K), -1.0))))
    na == 0 && (push!(qblocks, (spzeros(nout, 0), spzeros(nout, 0))); isempty(sel) || push!(lblocks, (spzeros(length(sel), 0), spzeros(length(sel), 0)));
                ncons > 0 && push!(cblocks, spzeros(ncons, 0)))
    qb = _chained_map(qblocks, prev, qdust, chained0(K0, Sq), a0; rep = rep)
    # links on deviations: bounds of the error of every chained row (cumulated along its chain)
    linkbound = zeros(nout); linkboundW = zeros(nout)
    deviation = Winv !== nothing
    if deviation
        linked = prev .> 0
        linkbound[linked] .= qdust[linked]
        if !isempty(dws)
            DW = reduce(+, dws)
            DWt = SparseMatrixCSC(transpose(DW))
            for i in findall(linked)
                linkboundW[i] = sum(abs, view(nonzeros(DWt), nzrange(DWt, i)); init = 0.0)
            end
        end
        for i in qb.order
            linkbound[i] += linkbound[prev[i]]
            linkboundW[i] += linkboundW[prev[i]]
        end
        qb.dust[linked] .= 0.0
    end
    dust = _chain_dust(qb)
    lmap = nothing
    if !isempty(sel)
        Lyc = _chain_rows(Nsel[end], lprev, Float64(droptol), ldust, Sl, cl, al)
        lmap = _chained_map(Any[Lyc, lblocks...], lprev, ldust, chained0(L0, Sl), [zeros(ny); a0];
                            rep = isempty(rep) ? rep : [zeros(Int32, ny); Int32[r == 0 ? 0 : r + ny for r in rep]])
        dust = max(dust, _chain_dust(lmap))
    end
    cmap = nothing
    if ncons > 0
        cmap = _chained_map([(B, spzeros(size(B)...)) for B in cblocks], zeros(Int32, ncons), zeros(ncons),
                            vec(Matrix(reduce(vcat, C0))), a0)
    end
    tol = minimum(R.consistency_tol for R in chain)
    op = StepOperator(chain, M, P0, act, kind, owner, loc, sn, sd, a0, nq, qb, zeros(nout), cmap, tol, zeros(ncons), sel, lmap,
                      zeros(ny + na), all(R.feasible for R in chain), dust, deviation, linkbound, linkboundW, 0.0)
    op.build_seconds = (time_ns() - t0) / 1e9
    return op
end

"Largest sum of dropped entries along a chain."
function _chain_dust(F::ChainedMap)
    cum = copy(F.dust)
    @inbounds for i in F.order
        cum[i] += cum[F.prev[i]]
    end
    return maximum(cum; init = 0.0)
end

function _gather!(a::Vector{Float64}, P::SheafProgram, kind, owner, loc, len, dest)
    nodes, edges = P.nodes, P.edges
    @inbounds for s in eachindex(kind)
        k = kind[s]; o = owner[s]
        v = k == 1 ? nodes[o].q : (k == 2 ? nodes[o].b : edges[o].b)
        l0 = loc[s] - 1; d0 = dest[s] - 1
        for t in 1:len[s]
            a[d0+t] = v[l0+t]
        end
    end
    return a
end

"""
    update!(op::StepOperator) -> op

The QP vectors of the last level from the current data of the finest program:
reads the active entries, applies the precomposed map, and writes
`qmap.q`, `qmap.bfull` and `qmap.b` (merged rows as `refresh!` merges them).
`qmap.c` is not recomputed, nor are the levels' programs (`sync!`).
`op.feasible`: every affine fiber is nonempty (from the composed consistency
rows; if they exceed the tolerance, decided by `sync!`).
"""
function update!(op::StepOperator)
    _gather!(op.a, op.root, op.kind, op.owner, op.local_index, op.seglen, op.segdest)
    apply!(op.out, op.qb, op.a)
    M = op.qmap
    out, nq = op.out, op.nq
    copyto!(M.q, 1, out, 1, nq)
    copyto!(M.bfull, 1, out, nq + 1, length(M.bfull))
    _collapse_b!(M)
    if op.cons !== nothing
        apply!(op.cbuf, op.cons, op.a)
        if maximum(abs, op.cbuf) <= op.cons_tol
            op.feasible = true
        else
            sync!(op)
        end
    end
    return op
end

"""
    sync!(op::StepOperator) -> op

The level by level update (`update!` of every level of the chain, then
`refresh!` of the QP map): every level's program, base point and feasibility
and the QP's constant from the current data, for full lifts and checks.
"""
function sync!(op::StepOperator)
    for R in op.chain
        update!(R)
    end
    refresh!(op.qmap, getfield(op.chain[end], :program))
    op.feasible = all(R.feasible for R in op.chain)
    return op
end

"""
    lift!(x, op::StepOperator, y) -> x

The coordinates `op.lift_rows` of the finest plan lifted from a solution `y`
of the last level, with the active data of the last `update!(op)` (whose
differences it reuses): equal to `lift(reduced, y)[op.lift_rows]` after
`sync!`.
"""
function lift!(x::AbstractVector, op::StepOperator, y::AbstractVector)
    op.lift === nothing && throw(ArgumentError("the operator lifts no coordinates (keyword lift)"))
    ny = length(op.ya) - length(op.a)
    length(y) == ny || throw(DimensionMismatch("y must have $ny entries"))
    # the data's part of the differences is the one `update!(op)` computed (same reference, same classes)
    L, Q, na = op.lift, op.qb, length(op.a)
    copyto!(L.dx, 1, y, 1, ny); fill!(view(L.dxl, 1:ny), 0.0)
    copyto!(L.dx, ny + 1, Q.dx, 1, na); copyto!(L.dxl, ny + 1, Q.dxl, 1, na)
    if !isempty(L.rep)
        copyto!(L.dxp, 1, y, 1, ny); fill!(view(L.dxpl, 1:ny), 0.0)
        copyto!(L.dxp, ny + 1, isempty(Q.rep) ? Q.dx : Q.dxp, 1, na)
        copyto!(L.dxpl, ny + 1, isempty(Q.rep) ? Q.dxl : Q.dxpl, 1, na)
    end
    return _apply!(x, L)
end
