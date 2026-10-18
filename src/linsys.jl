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
# Two backends with the same interface:
#   QDLDLSystem    simplicial LDLt (QDLDL, the factorization of OSQP), AMD order
#   ChordalSystem  supernodal multifrontal LDLt (CliqueTrees.Multifrontal)
# `setup` times both on the problem and keeps the faster one (`linsys = :auto`).

abstract type LinearSystem end

"""
    kkt_pattern(P, A) -> (K, diag_idx)

Upper triangle of the KKT matrix with zero values on the diagonal and the
off-diagonal values of `P` and `A`. `diag_idx[j]` is the index in `K.nzval` of
the diagonal entry `(j, j)`.
"""
function kkt_pattern(P::SpMat, A::SpMat)
    n = size(P, 1); m = size(A, 1)
    At = SpMat(sparse(transpose(A)))       # column i of At is row i of A
    N = n + m
    colptr = Vector{Int}(undef, N + 1)
    rowval = Int[]; nzval = Float64[]
    diag_idx = Vector{Int}(undef, N)
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
        push!(rowval, n + i); push!(nzval, 0.0)
        diag_idx[n+i] = length(nzval)
        colptr[n+i+1] = length(nzval) + 1
    end
    return SparseMatrixCSC(N, N, colptr, rowval, nzval), diag_idx
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
    F::QDLDL.QDLDLFactorisation{Float64,Int}
    perm::Vector{Int}
    work::Vector{Float64}
    Ln::Int
    Lp::Vector{Int}
    Li::Vector{Int}
    Lx::Vector{Float64}
    Dinv::Vector{Float64}
end

function QDLDLSystem(K::SpMat, diag_idx::Vector{Int}; perm::Union{Nothing,Vector{Int}} = nothing)
    F = perm === nothing ? QDLDL.qdldl(K) : QDLDL.qdldl(K; perm = perm)
    ws = F.workspace
    p = F.perm === nothing ? collect(1:size(K, 1)) : F.perm
    return QDLDLSystem(K, diag_idx, F, p, zeros(size(K, 1)), ws.Ln, ws.Lp, ws.Li, ws.Lx, ws.Dinv)
end

"Refactor after `K.nzval` changed on the diagonal (same pattern, no symbolic work)."
function refactor!(S::QDLDLSystem)
    QDLDL.update_values!(S.F, S.diag_idx, view(nonzeros(S.K), S.diag_idx))
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
    make_system(kind, K, diag_idx, n; ordering = :amd) -> LinearSystem

`kind` is `:qdldl` or `:cliquetrees`. `K` must already hold its numerical
values. For `:qdldl` the fill-reducing `ordering` is `:amd` (QDLDL's own),
or one of CliqueTrees' `:mmd` (multiple minimum degree), `:amf` (approximate
minimum fill), `:mf` (minimum fill).
"""
function make_system(kind::Symbol, K::SpMat, diag_idx::Vector{Int}, n::Int; ordering::Symbol = :amd)
    if kind == :qdldl
        ordering == :amd && return QDLDLSystem(K, diag_idx)
        return QDLDLSystem(K, diag_idx; perm = fill_ordering(K, ordering))
    end
    kind == :cliquetrees && return ChordalSystem(K, diag_idx, n)
    throw(ArgumentError("unknown linear system backend $kind (use :qdldl or :cliquetrees)"))
end

"A fill-reducing permutation of the symmetric matrix with upper triangle `K`."
function fill_ordering(K::SpMat, ordering::Symbol)
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
