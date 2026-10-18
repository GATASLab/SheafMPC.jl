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
end

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

function BlockLDLSystem(K::SpMat, diag_idx::Vector{Int}, n::Int; settings = nothing)
    ordering = settings === nothing ? :auto : settings.kkt_ordering
    threads = settings === nothing ? 1 : settings.kkt_threads
    relax = settings === nothing ? BlockLDL.EXACT : (settings.kkt_relax == :exact ? BlockLDL.EXACT :
            settings.kkt_relax == :light ? BlockLDL.LIGHT : BlockLDL.Relax())
    structure = settings === nothing ? nothing : _kkt_structure(K, n, settings.kkt_structure)
    N = size(K, 1)
    signs = [i <= n ? 1.0 : -1.0 for i in 1:N]
    cm = BlockLDL.CostModel(nthreads = threads)
    if ordering == :auto
        perm, name, table = BlockLDL.choose_ordering(K; structure = structure, cost = cm)
    else
        perm = BlockLDL.make_ordering(K, ordering; structure = structure)
        perm === nothing && throw(ArgumentError("ordering $ordering is not available (structure or Metis missing)"))
        name = ordering; table = Any[]
    end
    S = BlockLDL.symbolic(K, perm, signs; relax = relax)
    F = BlockLDL.Factor(S; nthreads = threads)
    BlockLDL.factor!(F, K)
    return BlockLDLSystem(K, diag_idx, F, zeros(N), name, table)
end

refactor!(S::BlockLDLSystem) = (BlockLDL.factor!(S.F, S.K); S)

solve!(S::BlockLDLSystem, b::AbstractVector{Float64}) = BlockLDL.ldiv!(S.F, b, S.work)

factor_nnz(S::BlockLDLSystem) = S.F.S.nnzL

# the polish system shares the symbolic factorization
function _polish_system(S::BlockLDLSystem, K::SpMat, n::Int)
    F = BlockLDL.Factor(S.F.S; nthreads = S.F.nthreads)
    BlockLDL.factor!(F, K)
    return BlockLDLSystem(K, S.diag_idx, F, zeros(size(K, 1)), S.ordering, S.order_table)
end
