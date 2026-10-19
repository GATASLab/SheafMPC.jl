# system.jl: the BlockLDL kernel as a `LinearSystem` backend of the solver
# (`Settings(linsys = :blockldl)`).
#
# The ordering is chosen by the cost model of BlockLDL among the generic orders
# and, when `settings.kkt_structure` labels the variables with their agent and
# block (time instant), the structure-given ones. A refactorization reads every
# stored value of K, so any change of values on the pattern (the diagonal for a
# new rho, dense cone blocks in the polish) is handled.

"""
    BlockLDLSystem

Supernodal multifrontal LDLt of the KKT matrix (`BlockLDL.Factor`), with the
order picked by the cost model, optional threads, and a rank-one update path
for a few changed diagonal entries.
"""
mutable struct BlockLDLSystem <: LinearSystem
    K::SpMat
    diag_idx::Vector{Int}
    F::BlockLDL.Factor
    work::Vector{Float64}
    ordering::Symbol
    order_table::Vector{Any}
    # rank-one path (the polish system): the values the factor holds, the
    # updatable entries off the diagonal, path costs, updates since the last
    # full factorization
    lowrank::Bool
    dvals::Vector{Float64}
    offidx::Vector{Int}
    offvals::Vector{Float64}
    pathcost::Vector{Int}
    nupd::Int
    nlowrank::Int                # refactorizations done by rank-one updates (statistics)
end

function _bls(K::SpMat, diag_idx::Vector{Int}, F::BlockLDL.Factor, name::Symbol, table, upd_idx::Vector{Int};
              lowrank::Bool = false)
    nz = nonzeros(K)
    isdiag = falses(length(nz)); isdiag[diag_idx] .= true
    offidx = [k for k in upd_idx if !isdiag[k]]
    pc = lowrank ? BlockLDL.column_path_costs(F.S) : Int[]
    return BlockLDLSystem(K, diag_idx, F, zeros(size(K, 1)), name, table, lowrank, nz[diag_idx], offidx, nz[offidx],
                          pc, 0, 0)
end

"Updates after which the rank-one path refactorizes anyway (rounding drift)."
const LOWRANK_BUDGET = 4096
"Rank-one updates are used while their path entries stay below this fraction of flops + nnz(L)."
const LOWRANK_FRACTION = 0.3

"Labels of every KKT index from labels of the variables (rows: the variables they touch)."
function _kkt_structure(K::SpMat, n::Int, st)
    st === nothing && return nothing
    st isa BlockLDL.KKTStructure && return st
    va = Vector{Int}(st.agent); vb = Vector{Int}(st.block)
    if length(va) == size(K, 1)
        return BlockLDL.KKTStructure(va, vb)
    end
    length(va) == n || throw(DimensionMismatch("kkt_structure labels $(length(va)) variables, the problem has $n"))
    # column n + i of the upper triangle holds row i of A in its entries above n
    N = size(K, 1)
    ag = [va; zeros(Int, N - n)]; bl = [vb; zeros(Int, N - n)]
    rv = rowvals(K)
    for c in (n+1):N
        a = -1; b = 0
        for k in nzrange(K, c)
            j = rv[k]
            j <= n || continue
            a = a == -1 ? va[j] : (a == va[j] ? a : 0)
            b = max(b, vb[j])
        end
        ag[c] = max(a, 0); bl[c] = b
    end
    return BlockLDL.KKTStructure(ag, bl)
end

_kkt_threads(settings) = settings === nothing ? 1 : settings.kkt_threads
_kkt_relax(settings) = settings === nothing ? BlockLDL.LIGHT : (settings.kkt_relax == :exact ? BlockLDL.EXACT :
                       settings.kkt_relax == :light ? BlockLDL.LIGHT : BlockLDL.Relax())

function BlockLDLSystem(K::SpMat, diag_idx::Vector{Int}, n::Int; settings = nothing, perm = nothing,
                        upd_idx::Vector{Int} = diag_idx,
                        name::Symbol = :given, table = Any[], tree = nothing, threads::Int = _kkt_threads(settings))
    if perm === nothing
        ordering = settings === nothing ? :auto : settings.kkt_ordering
        structure = settings === nothing ? nothing : _kkt_structure(K, n, settings.kkt_structure)
        if ordering == :auto
            perm, name, _, table, tree, threads = BlockLDL.choose_system(K; structure = structure,
                                                                         engines = (:multifrontal,),
                                                                         cost = BlockLDL.CostModel(nthreads = threads))
        else
            perm = BlockLDL.make_ordering(K, ordering; structure = structure)
            perm === nothing && throw(ArgumentError("ordering $ordering is not available (structure or Metis missing)"))
            name = ordering
        end
    end
    N = size(K, 1)
    signs = [i <= n ? 1.0 : -1.0 for i in 1:N]
    S = BlockLDL.symbolic(K, perm, signs; relax = _kkt_relax(settings), tree = tree)
    F = BlockLDL.Factor(S; nthreads = threads)
    BlockLDL.factor!(F, K)
    return _bls(K, diag_idx, F, name, table, upd_idx)
end

"""
    model_system(K, diag_idx, n; upd_idx, settings) -> LinearSystem

`linsys = :model`: the engine (simplicial QDLDL or the multifrontal BlockLDL)
and the elimination order of least estimated cost under BlockLDL's cost model
(elimination-tree statistics of every candidate order; no trial
factorizations), factored once.
"""
function model_system(K::SpMat, diag_idx::Vector{Int}, n::Int; upd_idx::Vector{Int} = diag_idx, settings = nothing,
                      logical::Bool = false)
    threads = _kkt_threads(settings)
    structure = settings === nothing ? nothing : _kkt_structure(K, n, settings.kkt_structure)
    perm, name, eng, table, tree, nt = BlockLDL.choose_system(K; structure = structure,
                                                              cost = BlockLDL.CostModel(nthreads = threads))
    eng == :simplicial && return QDLDLSystem(K, diag_idx, upd_idx; perm = perm, logical = logical)
    return BlockLDLSystem(K, diag_idx, n; settings = settings, perm = perm, name = name, table = table, tree = tree,
                          threads = nt, upd_idx = upd_idx)
end

"""
Refactor for the current values of `S.K`. On the polish system (`lowrank`),
when only diagonal entries changed and their elimination-tree paths are short
against a refactorization, the factor is updated by rank-one modifications
instead (the polish solves are refined, which absorbs their rounding).
"""
function refactor!(S::BlockLDLSystem)
    nz = nonzeros(S.K)
    if S.lowrank && S.nupd < LOWRANK_BUDGET
        same = true
        @inbounds for (t, k) in enumerate(S.offidx)
            nz[k] == S.offvals[t] || (same = false; break)
        end
        if same
            F = S.F; ip = F.S.iperm
            cost = 0; nch = 0
            @inbounds for j in eachindex(S.diag_idx)
                if nz[S.diag_idx[j]] != S.dvals[j]
                    cost += S.pathcost[ip[j]]; nch += 1
                end
            end
            if cost <= LOWRANK_FRACTION * (F.S.flops + F.S.nnzL)
                w = S.work
                fill!(w, 0.0)
                @inbounds for j in eachindex(S.diag_idx)
                    v = nz[S.diag_idx[j]]
                    if v != S.dvals[j]
                        BlockLDL.rank1_diagonal!(F, ip[j], v - S.dvals[j], w)
                        S.dvals[j] = v
                    end
                end
                S.nupd += nch
                nch > 0 && (S.nlowrank += 1)
                return S
            end
        end
    end
    BlockLDL.factor!(S.F, S.K)
    @inbounds for j in eachindex(S.diag_idx)
        S.dvals[j] = nz[S.diag_idx[j]]
    end
    @inbounds for (t, k) in enumerate(S.offidx)
        S.offvals[t] = nz[k]
    end
    S.nupd = 0
    return S
end

solve!(S::BlockLDLSystem, b::AbstractVector{Float64}) = BlockLDL.ldiv!(S.F, b, S.work)

factor_nnz(S::BlockLDLSystem) = S.F.S.nnzL

# the polish system shares the symbolic factorization and takes the rank-one path
function _polish_system(S::BlockLDLSystem, K::SpMat, n::Int)
    F = BlockLDL.Factor(S.F.S; nthreads = S.F.nthreads)
    BlockLDL.factor!(F, K)
    upd = [S.diag_idx; S.offidx]
    return _bls(K, S.diag_idx, F, S.ordering, S.order_table, upd; lowrank = POLISH_LOWRANK[])
end

"Whether the polish system of the BlockLDL backend uses rank-one updates."
const POLISH_LOWRANK = Ref(true)

"The backend a system is (for `Info.linsys`)."
system_kind(::QDLDLSystem) = :qdldl
system_kind(::ChordalSystem) = :cliquetrees
system_kind(::BlockLDLSystem) = :blockldl
system_kind(::LinearSystem) = :other
