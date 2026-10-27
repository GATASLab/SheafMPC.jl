# qpmap.jl: a program as a conic QP whose vectors are refreshed in place.
#
# `sheaf_qp(P)` builds min (1/2)x'Hx + g'x + c s.t. b - A x in K with the hard
# edges first and the node rows after. For a fixed program structure H, A and
# the cones are fixed, and
#
#     g = q - delta_s' W_s b_s,   c = sum c_v + (1/2) b_s' W_s b_s,
#     b = (b_hard ; b_nodes),
#
# are linear in the program's flat vectors. `QPMap` stores these maps (and the
# grouping of exact duplicate rows, which a pushforward along rigid teams can
# create) so that a receding-horizon step costs a few sparse products.

"""
    QPMap(P; dedup = true)

The conic QP of the program `P` (`qp`, as `sheaf_qp(P)` with duplicate rows
merged when `dedup`) and the maps from the program's vectors to the QP's
`q`, `b` and constant: `refresh!(map, P)` recomputes them in place.
"""
mutable struct QPMap
    qp::ConicQP
    Ls::SpMat                   # n x C^1: g = q - Ls * be
    Ws::SpMat                   # C^1 x C^1: c = sum c_v + (1/2) be' Ws be
    hard_rows::Vector{Int}      # positions in be of the hard rows, in QP row order
    nh::Int
    dedup::Bool
    keep::Vector{Int}           # rows of the full QP that are kept
    group::Vector{Int}          # kept row of every full row (0 never happens)
    groupsize::Vector{Int}      # copies behind every kept row
    kinds_full::Vector{RowKind}
    socblock::Vector{Int}       # SOC block of every full row (0 otherwise)
    soc_ranges::Vector{UnitRange{Int}}
    q::Vector{Float64}
    c::Float64
    bfull::Vector{Float64}
    b::Vector{Float64}
    fd::FlatData
    tmp::Vector{Float64}
    valid::Bool                 # false when the duplicate rows stopped agreeing
    # in-place node matrices (built on first use): per vertex, the position in nonzeros(qp.A) of every
    # stored entry of its node matrix (0 for a merged row), and the full rows behind every kept row
    apos::Vector{Vector{Int}}
    gmembers::Vector{Vector{Int}}
end

function QPMap(P::SheafProgram; dedup::Bool = true)
    full = sheaf_qp(P)
    S = [e for (e, E) in enumerate(P.edges) if !E.hard && edgedim(E) > 0]
    Ds = coboundary(P, S)
    Wsm = weight_matrix(P, S)
    srows = reduce(vcat, (collect(erange(P, e)) for e in S); init = Int[])
    Sel = sparse(1:length(srows), srows, 1.0, length(srows), c1dim(P))
    Ls = SpMat(Ds' * (Wsm * Sel))
    Ws = SpMat(Sel' * (Wsm * Sel))
    hard_rows = Int[]
    for (e, E) in enumerate(P.edges)
        (E.hard && edgedim(E) > 0) && append!(hard_rows, erange(P, e))
    end
    m = nrows(full)
    socblock = zeros(Int, m)
    for (k, B) in enumerate(full.socs)
        socblock[B] .= k
    end
    keep, group, groupsize, qp = collect(1:m), collect(1:m), ones(Int, m), full
    if dedup
        qp2, keep2 = dedup_rows(full)
        if length(keep2) < m
            keep = keep2
            pos = zeros(Int, m)
            pos[keep] .= 1:length(keep)
            # every dropped row (or SOC block) has a kept twin with the same row of A
            At = SpMat(sparse(transpose(full.A)))
            key(i) = (rowvals(At)[nzrange(At, i)], nonzeros(At)[nzrange(At, i)], full.kinds[i] == ROW_SOC ? -1 : Int(full.kinds[i]))
            first_of = Dict{Any,Int}()
            for i in keep
                socblock[i] == 0 && (first_of[key(i)] = i)
            end
            firstb = Dict{Any,Int}()
            for (k, B) in enumerate(full.socs)
                pos[first(B)] > 0 && (firstb[([key(i) for i in B], full.socb[B])] = k)
            end
            for i in 1:m
                if pos[i] > 0
                    group[i] = pos[i]
                elseif socblock[i] == 0
                    group[i] = pos[first_of[key(i)]]
                else
                    B = full.socs[socblock[i]]
                    Bk = full.socs[firstb[([key(j) for j in B], full.socb[B])]]
                    group[i] = pos[Bk[i-first(B)+1]]
                end
            end
            groupsize = zeros(Int, length(keep))
            for i in 1:m
                groupsize[group[i]] += 1
            end
            qp = qp2
        end
    end
    M = QPMap(qp, Ls, Ws, hard_rows, length(hard_rows), dedup, keep, group, groupsize, copy(full.kinds),
              socblock, copy(full.socs), copy(qp.q), qp.c, zeros(m), zeros(nrows(qp)), FlatData(P),
              zeros(c1dim(P)), true, Vector{Int}[], Vector{Int}[])
    refresh!(M, P)
    return M
end

function _node_positions!(M::QPMap, P::SheafProgram)
    A = M.qp.A
    rv = rowvals(A)
    M.apos = Vector{Vector{Int}}(undef, nvertices(P))
    for v in 1:nvertices(P)
        Av = P.nodes[v].A
        ra = rowvals(Av)
        out = zeros(Int, nnz(Av))
        for j in 1:size(Av, 2), k in nzrange(Av, j)
            full = M.nh + P.row_offsets[v] + ra[k]
            g = M.group[full]
            M.keep[g] == full || continue
            rng = nzrange(A, P.offsets[v] + j)
            p = searchsortedfirst(view(rv, rng), g)
            (p <= length(rng) && rv[rng[p]] == g) || error("the QP does not store the node entries of vertex $v")
            out[k] = rng[p]
        end
        M.apos[v] = out
    end
    M.gmembers = [Int[] for _ in M.keep]
    for i in eachindex(M.group)
        push!(M.gmembers[M.group[i]], i)
    end
    return M
end

"The nonzero entries `(column, value)` of full node row `i` of the QP, read off the node matrices of `P`."
function _full_row_entries(M::QPMap, P::SheafProgram, i::Int)
    r = i - M.nh
    v = searchsortedlast(P.row_offsets, r - 1)
    Av = P.nodes[v].A
    rl = r - P.row_offsets[v]
    out = Tuple{Int,Float64}[]
    for j in 1:size(Av, 2), k in nzrange(Av, j)
        (rowvals(Av)[k] == rl && nonzeros(Av)[k] != 0) && push!(out, (P.offsets[v] + j, nonzeros(Av)[k]))
    end
    return out
end

"""
    refresh_matrices!(map::QPMap, P, verts) -> map

Copy the node constraint matrices of the vertices `verts` of `P` (changed in
place on their patterns) into the QP's constraint matrix. Merged duplicate
rows must stay duplicates; when they stop agreeing `map.valid` becomes false
(then the QP must be rebuilt without merging, as when their right-hand sides
disagree).
"""
function refresh_matrices!(M::QPMap, P::SheafProgram, verts)
    isempty(verts) && return M
    length(M.apos) == nvertices(P) || _node_positions!(M, P)
    nz = nonzeros(M.qp.A)
    merged = length(M.keep) < length(M.group)
    for v in verts
        pos = M.apos[v]
        vals = nonzeros(P.nodes[v].A)
        length(vals) == length(pos) || throw(ArgumentError("the node matrix of vertex $v left its sparsity pattern"))
        @inbounds for k in eachindex(pos)
            pos[k] > 0 && (nz[pos[k]] = vals[k])
        end
        merged || continue
        for r in rrange(P, v)
            g = M.group[M.nh+r]
            mem = M.gmembers[g]
            length(mem) > 1 || continue
            if any(<=(M.nh), mem)
                M.valid = false                      # a node row merged with a hard edge row: rebuild
                continue
            end
            ref = sort!(_full_row_entries(M, P, mem[1]))
            all(i -> sort!(_full_row_entries(M, P, i)) == ref, mem) || (M.valid = false)
        end
    end
    return M
end

"""
    refresh!(map::QPMap, P) -> map

Recompute the QP's `q`, `b` and constant from the program's current vectors
(no allocation). For merged duplicate rows the bound is the tightest copy;
`map.valid` becomes false if duplicate equality rows or cones stop agreeing
(then the QP must be rebuilt without merging).
"""
function refresh!(M::QPMap, P::SheafProgram)
    fd = gather!(M.fd, P)
    q = M.q
    copyto!(q, fd.q)
    mul!(q, M.Ls, fd.be, -1.0, 1.0)
    mul!(M.tmp, M.Ws, fd.be)
    M.c = fd.c + 0.5 * dot(fd.be, M.tmp)
    bf = M.bfull
    @inbounds for k in 1:M.nh
        bf[k] = fd.be[M.hard_rows[k]]
    end
    @inbounds for k in eachindex(fd.bn)
        bf[M.nh+k] = fd.bn[k]
    end
    return _collapse_b!(M)
end

"The kept right-hand sides from `bfull` (tightest copy of a merged half-space row; `valid` false if copies disagree)."
function _collapse_b!(M::QPMap)
    bf = M.bfull
    if length(M.keep) == length(bf)
        copyto!(M.b, bf)
        return M
    end
    b = M.b
    @inbounds for (k, i) in enumerate(M.keep)
        b[k] = bf[i]
    end
    @inbounds for i in eachindex(bf)
        g = M.group[i]
        M.keep[g] == i && continue
        kd = M.kinds_full[i]
        if kd == ROW_LEQ
            b[g] = min(b[g], bf[i])
        elseif abs(b[g] - bf[i]) > 1e-12 * max(1.0, abs(bf[i]))
            M.valid = false
        end
    end
    return M
end

"""
    expand_duals(map, y) -> y_full

The multipliers of the full row set (`sheaf_qp` order) from those of the
merged QP: each kept dual is shared equally by its copies (any split is a
valid multiplier; the even one is canonical).
"""
function expand_duals!(yfull::AbstractVector, M::QPMap, y::AbstractVector)
    @inbounds for i in eachindex(yfull)
        g = M.group[i]
        yfull[i] = y[g] / M.groupsize[g]
    end
    return yfull
end
expand_duals(M::QPMap, y::AbstractVector) = expand_duals!(zeros(length(M.group)), M, y)

"""
    ProgramSolution

The solution of a program by `solve`: `status`, the flat cochain `x`, the
objective `J` (with its constant), `hard_duals` (the multiplier of every hard
edge row, laid out like the edge targets, zero on soft edges: the convention
of the paper's Thm. 2, `J*` moves by `-mu` per unit of target), `node_duals`
(the multipliers of the node rows, in the cone's dual), and the solver's
`info`.
"""
struct ProgramSolution
    status::Symbol
    x::Vector{Float64}
    J::Float64
    hard_duals::Vector{Float64}
    node_duals::Vector{Float64}
    info::Info
end

"""`isoptimal(sol)`: the solve succeeded."""
isoptimal(s::ProgramSolution) = s.status == :solved

"""Split a full-QP dual vector into hard edge duals (flat over C^1) and node duals."""
function _split_duals(P::SheafProgram, M::QPMap, yfull::AbstractVector)
    he = zeros(c1dim(P))
    @inbounds for k in 1:M.nh
        he[M.hard_rows[k]] = yfull[k]
    end
    return he, yfull[(M.nh+1):end]
end

const SOLVE_DEFAULTS = (eps_abs = 1e-8, eps_rel = 1e-8, max_iter = 50_000)

"""
    solve(program; dedup = true, settings...) -> ProgramSolution

Solve a program (a `SheafProgram`, `FleetProgram` or `ReducedProgram`; for a
reduction, the coarse program) with the package's conic QP solver. Keyword
arguments are solver `Settings` (defaults here `eps_abs = eps_rel = 1e-8`).
For a `ReducedProgram`, `lift(reduced, sol)` gives the fine plan.
"""
function solve(P::SheafProgram; dedup::Bool = true, kwargs...)
    M = QPMap(P; dedup = dedup)
    s = setup(M.qp; merge(SOLVE_DEFAULTS, kwargs)...)
    info = solve!(s)
    yfull = expand_duals(M, s.ysol)
    he, nd = _split_duals(P, M, yfull)
    J = info.status == :solved ? objective(P, s.xsol) : (info.status == :primal_infeasible ? Inf : NaN)
    return ProgramSolution(info.status, copy(s.xsol), J, he, nd, deepcopy(info))
end

function solve(R::ReducedProgram; kwargs...)
    R.feasible || return ProgramSolution(:primal_infeasible, zeros(c0dim(R.program)), Inf, zeros(c1dim(R.program)),
                                         zeros(noderows(R.program)), Info(status = :primal_infeasible))
    return solve(R.program; kwargs...)
end

lift(R::ReducedProgram, sol::ProgramSolution; kwargs...) = lift(R, sol.x; kwargs...)
