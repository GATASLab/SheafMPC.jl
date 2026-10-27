# linsys.jl: the quasi-definite KKT system and its sparse LDLt factorizations.
#
#     K = [ P + sigma I     A'      ]
#         [ A           -diag(dinv) ]
#
# is assembled once as an upper triangular CSC matrix with every diagonal entry
# stored, so that later changes (a new rho in the ADMM system, a new active set
# in the polish system) only rewrite diagonal values and refactor numerically:
# the ordering and the symbolic factorization are computed once, in `setup`.
# K is quasi-definite (positive definite (1,1) block, negative definite (2,2)
# block), so it has an LDLt factorization with D of known signs for every
# symmetric permutation (Vanderbei 1995); no pivoting is needed.
#
# Interface (what the solver uses; a new backend implements exactly this):
#   * the KKT matrix `K` (upper triangle, CSC, pattern from `kkt_pattern`, every
#     diagonal entry and every SOC (2,2) block stored) is owned by the system as
#     the field `S.K`, with `S.diag_idx` its diagonal indices; the solver writes
#     new values into `nonzeros(S.K)` (only at `diag_idx` and SOC block entries,
#     i.e. at `upd_idx`) and then calls
#   * `refactor!(S)`: numerical refactorization of the current `S.K` values
#     (same pattern; no symbolic work), and
#   * `solve!(S, b)`: solve `K v = b` in place, allocation free;
#   * `factor_nnz(S)`: nonzeros of the factor (reporting only).
# Construction goes through `make_system(kind, K, diag_idx, n; ordering,
# upd_idx)` (the ADMM system) and `_polish_system(S, K, n)` in solver.jl (a
# second system with the same pattern, sharing the ordering and, when the
# backend can, the symbolic factorization).
#
# Three backends with the same interface:
#   QDLDLSystem    simplicial LDLt (QDLDL, the factorization of OSQP), AMD order
#   ChordalSystem  supernodal multifrontal LDLt (CliqueTrees.Multifrontal)
#   BlockLDLSystem the structured multifrontal kernel of src/kkt (BlockLDL);
#                  a refactorization reads every stored value of K, so all
#                  `upd_idx` changes are picked up
# `linsys = :auto` picks QDLDL or BlockLDL and the order by BlockLDL's cost
# model (no trial factorizations); `:timed` times QDLDL and CliqueTrees in
# `setup` and keeps the faster one.

abstract type LinearSystem end

"""
    kkt_pattern(P, A, socs = []) -> (K, diag_idx, soc_idx, upd_idx)

Upper triangle of the KKT matrix with zero values on the diagonal and the
off-diagonal values of `P` and `A`. `diag_idx[j]` is the index in `K.nzval` of
the diagonal entry `(j, j)`. The (2,2) block of every second-order cone block
`B in socs` is stored dense (explicit zeros for ADMM), so that the polish can
write a full block there; `soc_idx[k][a, b]` is the index of entry
`(n + B[a], n + B[b])` of block `k` (symmetric). `upd_idx` lists every entry a
refactorization may change (diagonal and SOC blocks).
"""
function kkt_pattern(P::SpMat, A::SpMat, socs::Vector{UnitRange{Int}} = UnitRange{Int}[])
    n = size(P, 1); m = size(A, 1)
    At = SpMat(sparse(transpose(A)))       # column i of At is row i of A
    N = n + m
    blk = zeros(Int, m)
    for (k, B) in enumerate(socs), i in B
        blk[i] = k
    end
    colptr = Vector{Int}(undef, N + 1)
    rowval = Int[]; nzval = Float64[]
    diag_idx = Vector{Int}(undef, N)
    soc_idx = [zeros(Int, length(B), length(B)) for B in socs]
    sizehint!(rowval, nnz(P) ÷ 2 + n + nnz(A) + m)
    sizehint!(nzval, nnz(P) ÷ 2 + n + nnz(A) + m)
    colptr[1] = 1
    Prow = rowvals(P); Pval = nonzeros(P)
    for j in 1:n
        for k in nzrange(P, j)
            i = Prow[k]
            i < j || continue
            push!(rowval, i); push!(nzval, Pval[k])
        end
        push!(rowval, j); push!(nzval, 0.0)
        diag_idx[j] = length(nzval)
        colptr[j+1] = length(nzval) + 1
    end
    Arow = rowvals(At); Aval = nonzeros(At)
    for i in 1:m
        for k in nzrange(At, i)
            push!(rowval, Arow[k]); push!(nzval, Aval[k])
        end
        b = blk[i]
        if b > 0
            B = socs[b]
            for i2 in first(B):(i-1)
                push!(rowval, n + i2); push!(nzval, 0.0)
                a1, a2 = i2 - first(B) + 1, i - first(B) + 1
                soc_idx[b][a1, a2] = length(nzval); soc_idx[b][a2, a1] = length(nzval)
            end
        end
        push!(rowval, n + i); push!(nzval, 0.0)
        diag_idx[n+i] = length(nzval)
        b > 0 && (a = i - first(socs[b]) + 1; soc_idx[b][a, a] = length(nzval))
        colptr[n+i+1] = length(nzval) + 1
    end
    upd = copy(diag_idx)
    for (k, B) in enumerate(socs), a2 in 1:length(B), a1 in 1:(a2-1)
        push!(upd, soc_idx[k][a1, a2])
    end
    return SparseMatrixCSC(N, N, colptr, rowval, nzval), diag_idx, soc_idx, upd
end

"Write the diagonal: `xdiag` on the first `n` entries, `-dinv` on the last `m`."
function set_diagonal!(K::SpMat, diag_idx::Vector{Int}, xdiag::AbstractVector, dinv::AbstractVector)
    n = length(xdiag)
    nz = nonzeros(K)
    @inbounds for j in 1:n
        nz[diag_idx[j]] = xdiag[j]
    end
    @inbounds for i in eachindex(dinv)
        nz[diag_idx[n+i]] = -dinv[i]
    end
    return K
end

# ---------------------------------------------------------------------------
# QDLDL
# ---------------------------------------------------------------------------

mutable struct QDLDLSystem <: LinearSystem
    K::SpMat
    diag_idx::Vector{Int}
    upd_idx::Vector{Int}
    F::QDLDL.QDLDLFactorisation{Float64,Int}
    perm::Vector{Int}
    work::Vector{Float64}
    Ln::Int
    Lp::Vector{Int}
    Li::Vector{Int}
    Lx::Vector{Float64}
    Dinv::Vector{Float64}
end

function QDLDLSystem(K::SpMat, diag_idx::Vector{Int}, upd_idx::Vector{Int} = diag_idx;
                     perm::Union{Nothing,Vector{Int}} = nothing, logical::Bool = false)
    # logical = true: symbolic factorization only (refactor! before the first solve)
    F = perm === nothing ? QDLDL.qdldl(K; logical = logical) : QDLDL.qdldl(K; perm = perm, logical = logical)
    ws = F.workspace
    p = F.perm === nothing ? collect(1:size(K, 1)) : F.perm
    return QDLDLSystem(K, diag_idx, upd_idx, F, p, zeros(size(K, 1)), ws.Ln, ws.Lp, ws.Li, ws.Lx, ws.Dinv)
end

"Refactor after `K.nzval` changed on the diagonal or SOC blocks (same pattern, no symbolic work)."
function refactor!(S::QDLDLSystem)
    QDLDL.update_values!(S.F, S.upd_idx, view(nonzeros(S.K), S.upd_idx))
    QDLDL.refactor!(S.F)
    return S
end

"Solve `K v = b` in place (`b` is overwritten by `v`)."
function solve!(S::QDLDLSystem, b::AbstractVector{Float64})
    w = S.work; p = S.perm
    @inbounds for i in eachindex(p)
        w[i] = b[p[i]]
    end
    _ldl_solve!(S.Ln, S.Lp, S.Li, S.Lx, S.Dinv, w)
    @inbounds for i in eachindex(p)
        b[p[i]] = w[i]
    end
    return b
end

function _ldl_solve!(n::Int, Lp::Vector{Int}, Li::Vector{Int}, Lx::Vector{Float64}, Dinv::Vector{Float64},
                     x::Vector{Float64})
    @inbounds for i in 1:n
        xi = x[i]
        for j in Lp[i]:(Lp[i+1]-1)
            x[Li[j]] -= Lx[j] * xi
        end
    end
    @inbounds for i in 1:n
        x[i] *= Dinv[i]
    end
    @inbounds for i in n:-1:1
        s = x[i]
        for j in Lp[i]:(Lp[i+1]-1)
            s -= Lx[j] * x[Li[j]]
        end
        x[i] = s
    end
    return x
end

factor_nnz(S::QDLDLSystem) = length(S.Lx)

# ---------------------------------------------------------------------------
# CliqueTrees.Multifrontal (supernodal)
# ---------------------------------------------------------------------------

mutable struct ChordalSystem{F,L,LT,FW,DW} <: LinearSystem
    K::SpMat
    diag_idx::Vector{Int}
    F::F
    L::L
    Lt::LT
    d::Vector{Float64}
    FWs::FW
    DWs::DW
    signs::Vector{Float64}
    perm::Vector{Int}
    work::Vector{Float64}
end

function ChordalSystem(K::SpMat, diag_idx::Vector{Int}, n::Int; alg = nothing)
    H = Hermitian(K, :U)
    F = alg === nothing ? Multifrontal.ChordalLDLt(H) : Multifrontal.ChordalLDLt(H; alg = alg)
    N = size(K, 1)
    signs = [i <= n ? 1.0 : -1.0 for i in 1:N]
    FWs = Multifrontal.FactorizationWorkspace(F)
    DWs = Multifrontal.DivisionWorkspace{Float64}(Multifrontal.symbolic(F), 1)
    perm = Vector{Int}(F.perm)
    S = ChordalSystem(K, diag_idx, F, F.L, F.L', zeros(N), FWs, DWs, signs, perm, zeros(N))
    _factor!(S)
    return S
end

function _factor!(S::ChordalSystem)
    copyto!(S.F, Hermitian(S.K, :U))
    ldlt!(S.FWs, S.F; signs = S.signs)
    S.L = S.F.L
    S.Lt = S.L'
    copyto!(S.d, S.F.d)
    return S
end

refactor!(S::ChordalSystem) = _factor!(S)

function solve!(S::ChordalSystem, b::AbstractVector{Float64})
    w = S.work; p = S.perm; d = S.d
    @inbounds for i in eachindex(p)
        w[i] = b[p[i]]
    end
    ldiv!(S.DWs, S.L, w)
    @inbounds for i in eachindex(w)
        w[i] /= d[i]
    end
    ldiv!(S.DWs, S.Lt, w)
    @inbounds for i in eachindex(p)
        b[p[i]] = w[i]
    end
    return b
end

factor_nnz(S::ChordalSystem) = nnz(S.F)

# ---------------------------------------------------------------------------

"""
    make_system(kind, K, diag_idx, n; ordering = :amd, perm = nothing, logical = false) -> LinearSystem

`kind` is `:qdldl` or `:cliquetrees`. With `logical = true` QDLDL stops after
the symbolic factorization (call `refactor!` before solving). `K` must already hold its numerical
values. For `:qdldl` the fill-reducing `ordering` is `:amd` (QDLDL's own),
or one of CliqueTrees' `:mmd` (multiple minimum degree), `:amf` (approximate
minimum fill), `:mf` (minimum fill).
"""
function make_system(kind::Symbol, K::SpMat, diag_idx::Vector{Int}, n::Int; ordering::Symbol = :amd,
                     upd_idx::Vector{Int} = diag_idx, settings = nothing,
                     perm::Union{Nothing,Vector{Int}} = nothing, logical::Bool = false)
    kind == :blockldl && return BlockLDLSystem(K, diag_idx, n; settings = settings, upd_idx = upd_idx)
    kind == :model && return model_system(K, diag_idx, n; upd_idx = upd_idx, settings = settings, logical = logical)
    if kind == :qdldl
        perm === nothing || return QDLDLSystem(K, diag_idx, upd_idx; perm = perm, logical = logical)
        ordering == :amd && return QDLDLSystem(K, diag_idx, upd_idx; logical = logical)
        return QDLDLSystem(K, diag_idx, upd_idx; perm = fill_ordering(K, ordering), logical = logical)
    end
    kind == :cliquetrees && return ChordalSystem(K, diag_idx, n)
    throw(ArgumentError("unknown linear system backend $kind (use :qdldl, :cliquetrees or :blockldl)"))
end

"A fill-reducing permutation of the symmetric matrix with upper triangle `K`."
function fill_ordering(K::SpMat, ordering::Symbol)
    ordering == :amd && return Vector{Int}(QDLDL.AMD.amd(K))     # QDLDL's default (AMD of K + K')
    Kf = K + transpose(K)
    alg = ordering == :mmd ? CliqueTrees.MMD() : ordering == :amf ? CliqueTrees.AMF() :
          ordering == :mf ? CliqueTrees.MF() : throw(ArgumentError("unknown ordering $ordering"))
    return Vector{Int}(CliqueTrees.permutation(Kf; alg = alg)[1])
end

"Minimum time of `reps` solves with `S` (after one warm-up), for backend selection."
function time_solves(S::LinearSystem, reps::Int)
    b = randn(size(S.K, 1))
    w = copy(b)
    solve!(S, w)
    ts = Vector{Float64}(undef, reps)
    for r in 1:reps
        copyto!(w, b)
        ts[r] = @elapsed solve!(S, w)
    end
    return minimum(ts)
end
