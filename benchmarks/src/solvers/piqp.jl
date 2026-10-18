# piqp.jl: PIQP (Schwan, Jiang, Kuhn and Jones, 2023), a proximal interior
# point method for QPs, called in-process through its C interface (libpiqpc).
#
# PIQP's sparse form is
#
#     minimize    (1/2) x'Px + c'x
#     subject to  A x = b,  h_l <= G x <= h_u,  x_l <= x <= x_u
#
# with P given by its upper triangle (CSC, 0-based int32 indices). The
# canonical QP is split once at setup:
#
#   * rows with l == u go to (A, b);
#   * the other rows with exactly one nonzero coefficient a on a variable j
#     become variable bounds, l/a <= x_j <= u/a (swapped when a < 0), the
#     tightest bound winning when several rows bound the same variable;
#   * every other row with a finite side goes to (G, h_l, h_u); rows with
#     both sides infinite are dropped (multiplier 0).
#
# Multipliers: PIQP's stationarity is
#     P x + c + A'y + G'(z_u - z_l) + (z_bu - z_bl) = 0,  z >= 0,
# so the canonical y (P x + q + A'y = 0) is y_eq on equality rows,
# z_u - z_l on G rows, and on a bound row k of variable j with coefficient a,
# z_bu[j]/a if row k gives the active upper bound of x_j and -z_bl[j]/a if
# it gives the lower bound (both, summed, if it gives both).
#
# C API used: piqp_set_default_settings_sparse, piqp_setup_sparse,
# piqp_update_sparse (vectors only, NULL matrices), piqp_solve,
# piqp_cleanup; results are read from workspace->result (x, y, z_l, z_u,
# z_bl, z_bu and info.iter). The struct layouts below mirror piqp_typedef.h
# of v0.6.4 and are checked against the sizes of that header at include time.
#
# Library: ENV["PIQP_LIB"] if set, else the local build PIQP_DEFAULT_LIB
# (see PIQP_BUILD for how it was built). The C library links Eigen and
# BLASFEO statically with BLASFEO's symbols hidden, so it can share the
# process with HPIPM's libblasfeo.

const PIQP_DEFAULT_LIB = joinpath(homedir(), "tools", "piqp-install", "lib", "libpiqpc.so")
piqp_libpath() = get(ENV, "PIQP_LIB", PIQP_DEFAULT_LIB)

# Provenance of PIQP_DEFAULT_LIB.
const PIQP_BUILD = Dict{String,Any}(
    "version" => "0.6.4",
    "commit" => "5d849590a18bc7f0b449057e5f2041713a85003c",
    "repo" => "https://github.com/PREDICT-EPFL/piqp (tag v0.6.4)",
    "compile_flags" => "CMAKE_BUILD_TYPE=Release, CMAKE_CXX_FLAGS_RELEASE='-O3 -march=native -DNDEBUG', " *
                       "BUILD_C_INTERFACE=ON, BUILD_SHARED_LIBS=ON, BUILD_WITH_TEMPLATE_INSTANTIATION=OFF, " *
                       "BUILD_WITH_BLASFEO=ON, link '-Wl,--exclude-libs,ALL'",
    "compiler" => "GCC 13.3.0",
    "eigen" => "3.4.0",
    "blasfeo" => "giaf/blasfeo 0a3df8683c6bf9d98168d616e0c5d05938c9d51c (0.1.4.3-91), TARGET=X64_INTEL_HASWELL, static",
    "python_wheels" => "piqp 0.6.4, osqp 1.1.3 (~/tools/bench-venv)",
)

const PIQP_KKT = Dict("dense_cholesky" => Cint(0), "sparse_ldlt" => Cint(1), "sparse_ldlt_eq_cond" => Cint(2),
                      "sparse_ldlt_ineq_cond" => Cint(3), "sparse_ldlt_cond" => Cint(4),
                      "sparse_multistage" => Cint(5))
const PIQP_MAX_ITER = 500

# ---------------------------------------------------------------------------
# C structs (piqp_typedef.h, double precision, int32 indices)
# ---------------------------------------------------------------------------

mutable struct PiqpSettings
    rho_init::Cdouble
    delta_init::Cdouble
    eps_abs::Cdouble
    eps_rel::Cdouble
    check_duality_gap::Cint
    eps_duality_gap_abs::Cdouble
    eps_duality_gap_rel::Cdouble
    infeasibility_threshold::Cdouble
    reg_lower_limit::Cdouble
    reg_finetune_lower_limit::Cdouble
    reg_finetune_primal_update_threshold::Cint
    reg_finetune_dual_update_threshold::Cint
    max_iter::Cint
    max_factor_retires::Cint
    preconditioner_scale_cost::Cint
    preconditioner_reuse_on_update::Cint
    preconditioner_iter::Cint
    tau::Cdouble
    kkt_solver::Cint
    iterative_refinement_always_enabled::Cint
    iterative_refinement_eps_abs::Cdouble
    iterative_refinement_eps_rel::Cdouble
    iterative_refinement_max_iter::Cint
    iterative_refinement_min_improvement_rate::Cdouble
    iterative_refinement_static_regularization_eps::Cdouble
    iterative_refinement_static_regularization_rel::Cdouble
    verbose::Cint
    compute_timings::Cint
    PiqpSettings() = new()
end

struct PiqpCsc
    m::Cint
    n::Cint
    nnz::Cint
    p::Ptr{Cint}
    i::Ptr{Cint}
    x::Ptr{Cdouble}
end

struct PiqpDataSparse
    n::Cint
    p::Cint
    m::Cint
    P::Ptr{PiqpCsc}
    c::Ptr{Cdouble}
    A::Ptr{PiqpCsc}
    b::Ptr{Cdouble}
    G::Ptr{PiqpCsc}
    h_l::Ptr{Cdouble}
    h_u::Ptr{Cdouble}
    x_l::Ptr{Cdouble}
    x_u::Ptr{Cdouble}
end

@assert sizeof(PiqpSettings) == 184 && fieldoffset(PiqpSettings, 19) == 120 && fieldoffset(PiqpSettings, 28) == 180
@assert sizeof(PiqpCsc) == 40 && sizeof(PiqpDataSparse) == 88

# Byte offsets into piqp_workspace / piqp_result / piqp_info.
const _PIQP_WS_RESULT = 24                      # workspace->result
const _PIQP_RES_X, _PIQP_RES_Y, _PIQP_RES_ZL, _PIQP_RES_ZU, _PIQP_RES_ZBL, _PIQP_RES_ZBU = 0, 8, 16, 24, 32, 40
const _PIQP_RES_INFO = 80                       # result->info
const _PIQP_INFO_ITER = 4

# ---------------------------------------------------------------------------
# Library
# ---------------------------------------------------------------------------

struct _PiqpLib
    path::String
    lib::Ptr{Cvoid}
    defaults::Ptr{Cvoid}
    setup::Ptr{Cvoid}
    update::Ptr{Cvoid}
    solve::Ptr{Cvoid}
    cleanup::Ptr{Cvoid}
end

const _PIQP_LIBS = Dict{String,_PiqpLib}()

function _piqp_lib()
    path = piqp_libpath()
    L = get(_PIQP_LIBS, path, nothing)
    L === nothing || return L
    h = Libdl.dlopen(path, Libdl.RTLD_NOW | Libdl.RTLD_LOCAL)
    L = _PiqpLib(path, h, Libdl.dlsym(h, :piqp_set_default_settings_sparse), Libdl.dlsym(h, :piqp_setup_sparse),
                 Libdl.dlsym(h, :piqp_update_sparse), Libdl.dlsym(h, :piqp_solve), Libdl.dlsym(h, :piqp_cleanup))
    _PIQP_LIBS[path] = L
    return L
end

# ---------------------------------------------------------------------------
# Handle
# ---------------------------------------------------------------------------

# 0-based int32 CSC copy of a sparse matrix, kept alive by the handle.
struct _PiqpMat
    colptr::Vector{Cint}
    rowval::Vector{Cint}
    nzval::Vector{Cdouble}
    csc::Base.RefValue{PiqpCsc}
end

function _PiqpMat(M::SparseMatrixCSC)
    cp = Cint.(M.colptr .- 1); rv = Cint.(M.rowval .- 1); nz = Vector{Cdouble}(M.nzval)
    csc = Ref(PiqpCsc(Cint(size(M, 1)), Cint(size(M, 2)), Cint(length(nz)), pointer(cp), pointer(rv), pointer(nz)))
    return _PiqpMat(cp, rv, nz, csc)
end

_ptr(M::_PiqpMat) = Base.unsafe_convert(Ptr{PiqpCsc}, M.csc)
_ptr(::Nothing) = Ptr{PiqpCsc}(C_NULL)
_vptr(v::Vector{Cdouble}) = isempty(v) ? Ptr{Cdouble}(C_NULL) : pointer(v)

mutable struct PiqpHandle
    lib::_PiqpLib
    ws::Ptr{Cvoid}
    n::Int
    m::Int                         # canonical rows
    # canonical row of every PIQP equality row, G row, bound row
    eq_rows::Vector{Int}
    g_rows::Vector{Int}
    bnd_rows::Vector{Int}
    bnd_var::Vector{Int}
    bnd_coef::Vector{Float64}
    # bound row (index into bnd_rows) giving the active lower / upper bound of each variable, 0 if none
    rl::Vector{Int}
    ru::Vector{Int}
    # data handed to PIQP
    P::_PiqpMat
    A::Union{Nothing,_PiqpMat}
    G::Union{Nothing,_PiqpMat}
    c::Vector{Cdouble}
    b::Vector{Cdouble}
    hl::Vector{Cdouble}
    hu::Vector{Cdouble}
    xl::Vector{Cdouble}
    xu::Vector{Cdouble}
    settings::PiqpSettings
end

function _piqp_free!(h::PiqpHandle)
    if h.ws != C_NULL
        ccall(h.lib.cleanup, Cvoid, (Ptr{Cvoid},), h.ws)
        h.ws = C_NULL
    end
    return nothing
end

# Vector data of PIQP's form from the canonical vectors, through the maps.
function _piqp_vectors!(h::PiqpHandle, p::QP)
    copyto!(h.c, p.q)
    for (k, i) in enumerate(h.eq_rows); h.b[k] = p.u[i]; end
    for (k, i) in enumerate(h.g_rows); h.hl[k] = p.l[i]; h.hu[k] = p.u[i]; end
    fill!(h.xl, -Inf); fill!(h.xu, Inf); fill!(h.rl, 0); fill!(h.ru, 0)
    for k in eachindex(h.bnd_rows)
        i = h.bnd_rows[k]; j = h.bnd_var[k]; a = h.bnd_coef[k]
        lo, hi = a > 0 ? (p.l[i] / a, p.u[i] / a) : (p.u[i] / a, p.l[i] / a)
        if lo > h.xl[j]; h.xl[j] = lo; h.rl[j] = k; end
        if hi < h.xu[j]; h.xu[j] = hi; h.ru[j] = k; end
    end
    return h
end

function piqp_setup(p::QP, eps, variant)
    @assert !has_soc(p) "PIQP does not handle second-order cones"
    L = _piqp_lib()
    n = nvars(p); m = ncons(p)
    # nonzero count and the single nonzero of every row (from the CSC of A)
    cnt = zeros(Int, m); var = zeros(Int, m); coef = zeros(m)
    A = p.A
    for j in 1:n, t in nzrange(A, j)
        v = A.nzval[t]
        v == 0 && continue
        i = A.rowval[t]
        cnt[i] += 1; var[i] = j; coef[i] = v
    end
    eq_rows = Int[]; g_rows = Int[]; bnd_rows = Int[]
    for i in 1:m
        if p.l[i] == p.u[i]
            push!(eq_rows, i)
        elseif !isfinite(p.l[i]) && !isfinite(p.u[i])
            continue                                  # free row
        elseif cnt[i] == 1
            push!(bnd_rows, i)
        else
            push!(g_rows, i)
        end
    end
    Pm = _PiqpMat(SpMat(triu(p.P)))
    Am = isempty(eq_rows) ? nothing : _PiqpMat(SpMat(A[eq_rows, :]))
    Gm = isempty(g_rows) ? nothing : _PiqpMat(SpMat(A[g_rows, :]))

    s = PiqpSettings()
    ccall(L.defaults, Cvoid, (Ref{PiqpSettings},), s)
    s.eps_abs = eps; s.eps_rel = 0.0
    s.eps_duality_gap_abs = eps; s.eps_duality_gap_rel = 0.0
    s.max_iter = PIQP_MAX_ITER
    s.verbose = 0; s.compute_timings = 0
    s.kkt_solver = PIQP_KKT[String(variant["kkt_solver"])]

    h = PiqpHandle(L, C_NULL, n, m, eq_rows, g_rows, bnd_rows, var[bnd_rows], coef[bnd_rows],
                   zeros(Int, n), zeros(Int, n), Pm, Am, Gm,
                   zeros(n), zeros(length(eq_rows)), zeros(length(g_rows)), zeros(length(g_rows)),
                   zeros(n), zeros(n), s)
    _piqp_vectors!(h, p)
    ws = Ref{Ptr{Cvoid}}(C_NULL)
    GC.@preserve h begin
        data = Ref(PiqpDataSparse(Cint(n), Cint(length(eq_rows)), Cint(length(g_rows)),
                                  _ptr(h.P), pointer(h.c), _ptr(h.A), _vptr(h.b), _ptr(h.G),
                                  _vptr(h.hl), _vptr(h.hu), pointer(h.xl), pointer(h.xu)))
        ccall(L.setup, Cvoid, (Ref{Ptr{Cvoid}}, Ref{PiqpDataSparse}, Ref{PiqpSettings}), ws, data, h.settings)
    end
    h.ws = ws[]
    h.ws == C_NULL && error("piqp_setup_sparse returned no workspace")
    finalizer(_piqp_free!, h)
    return h
end

const _PIQP_STATUS = Dict{Cint,Symbol}(1 => :solved, -1 => :max_iter, -2 => :infeasible, -3 => :infeasible)

function piqp_solve!(h::PiqpHandle)
    st = ccall(h.lib.solve, Cint, (Ptr{Cvoid},), h.ws)
    res = unsafe_load(Ptr{Ptr{Cvoid}}(h.ws + _PIQP_WS_RESULT))
    rp(off) = unsafe_load(Ptr{Ptr{Cdouble}}(res + off))
    iters = Int(unsafe_load(Ptr{Cint}(res + _PIQP_RES_INFO + _PIQP_INFO_ITER)))
    x = copy(unsafe_wrap(Array, rp(_PIQP_RES_X), h.n))
    # canonical multipliers, read in place from PIQP's result arrays
    y = zeros(h.m)
    py = rp(_PIQP_RES_Y)
    for (k, i) in enumerate(h.eq_rows); y[i] = unsafe_load(py, k); end
    pzl = rp(_PIQP_RES_ZL); pzu = rp(_PIQP_RES_ZU)
    for (k, i) in enumerate(h.g_rows); y[i] = unsafe_load(pzu, k) - unsafe_load(pzl, k); end
    if !isempty(h.bnd_rows)
        pbl = rp(_PIQP_RES_ZBL); pbu = rp(_PIQP_RES_ZBU)
        for j in 1:h.n
            k = h.ru[j]; k == 0 || (y[h.bnd_rows[k]] += unsafe_load(pbu, j) / h.bnd_coef[k])
            k = h.rl[j]; k == 0 || (y[h.bnd_rows[k]] -= unsafe_load(pbl, j) / h.bnd_coef[k])
        end
    end
    return SolveResult(x, y, get(_PIQP_STATUS, st, :failed), iters, NaN)
end

function piqp_update!(h::PiqpHandle, p::QP)
    _piqp_vectors!(h, p)
    GC.@preserve h begin
        ccall(h.lib.update, Cvoid,
              (Ptr{Cvoid}, Ptr{PiqpCsc}, Ptr{Cdouble}, Ptr{PiqpCsc}, Ptr{Cdouble}, Ptr{PiqpCsc},
               Ptr{Cdouble}, Ptr{Cdouble}, Ptr{Cdouble}, Ptr{Cdouble}),
              h.ws, C_NULL, pointer(h.c), C_NULL, _vptr(h.b), C_NULL, _vptr(h.hl), _vptr(h.hu),
              pointer(h.xl), pointer(h.xu))
    end
    return nothing
end

function piqp_info()
    d = Dict{String,Any}("package" => "PIQP (C interface, in-process ccall)", "library" => piqp_libpath())
    piqp_libpath() == PIQP_DEFAULT_LIB || (d["note"] = "PIQP_LIB overrides the default; build fields describe the default library")
    bi = joinpath(dirname(dirname(piqp_libpath())), "BUILD_INFO")      # written by hpg/build.sbatch
    isfile(bi) && (d["build_info"] = read(bi, String))
    merge!(d, PIQP_BUILD)
    d["settings"] = "defaults of piqp_set_default_settings_sparse, then eps_abs = eps_duality_gap_abs = eps, " *
                    "eps_rel = eps_duality_gap_rel = 0, max_iter = $(PIQP_MAX_ITER), verbose off, compute_timings off"
    d["mapping"] = "l == u rows -> A x = b; single-nonzero rows -> variable bounds (tightest wins); other rows -> h_l <= G x <= h_u; free rows dropped"
    d["warm_start"] = "none (interior point); sequence mode uses piqp_update_sparse with vectors only"
    return d
end

function piqp_spec()
    variants = [Dict{String,Any}("kkt_solver" => k)
                for k in ("sparse_ldlt", "sparse_ldlt_eq_cond", "sparse_ldlt_ineq_cond", "sparse_ldlt_cond", "sparse_multistage")]
    return SolverSpec(name = "piqp", kind = :ipm, applicable = p -> !has_soc(p), variants = variants,
                      setup = piqp_setup, solve! = piqp_solve!, update! = piqp_update!, warm! = nothing,
                      info = piqp_info)
end
