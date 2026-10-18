# hpipm.jl: HPIPM (Frison and Diehl, 2020) called in-process through ccall.
#
# HPIPM solves the stage-wise OCP QP of `StageOCP` with a Riccati-based
# interior point method, optionally after partial condensing (Axehill 2015;
# Frison et al. 2016) of the N stages into N2 blocks. The adapter uses the
# C API directly (the same create/set pattern as HPIPM's Python wrapper):
#
#   d_ocp_qp_dim_{strsize,memsize,create,set_all}
#   d_ocp_qp_{strsize,memsize,create}, d_ocp_qp_set_{A,B,b,Q,S,R,q,r,
#       idxbx,lbx,ubx,lbx_mask,ubx_mask,idxbu,lbu,ubu,lbu_mask,ubu_mask,
#       C,D,lg,ug,lg_mask,ug_mask}
#   d_ocp_qp_sol_{strsize,memsize,create,get_x,get_u}
#   d_ocp_qp_ipm_arg_{strsize,memsize,create,set_default,set}
#   d_ocp_qp_ipm_ws_{strsize,memsize,create}, d_ocp_qp_ipm_solve,
#   d_ocp_qp_ipm_get_status, d_ocp_qp_ipm_get_iter
#   d_part_cond_qp_{compute_block_size,compute_dim,arg_memsize,arg_create,
#       arg_set_default,ws_memsize,ws_create,cond,cond_rhs,expand_sol}
#
# The fixed initial state is eliminated: stage 0 has nx = 0 in HPIPM,
#   b_0 <- A_0 x0 + b_0,  r_0 <- r_0 + S_0 x0,
#   lg_0 - C_0 x0 <= D_0 u_0 <= ug_0 - C_0 x0,
# and box bounds on x_0 are dropped. Bound indices with both sides infinite
# are dropped at setup; a one-sided bound keeps its index with the infinite
# side masked out (mask 0, value +-1e10, the convention acados uses). A bound
# with |v| >= 1e19 (the generators' +-1e20) counts as infinite.
#
# Library: ENV["HPIPM_LIB_DIR"] if set, else the fastest local build in
# ~/tools/hpipm-avx (see HPIPM_DEFAULT_BUILD), else acados' libhpipm. The
# library is loaded once per process (libblasfeo first, RTLD_GLOBAL), so
# comparing two library builds needs two processes.

const HPIPM_MODES = Dict("SPEED_ABS" => Cint(0), "SPEED" => Cint(1), "BALANCE" => Cint(2), "ROBUST" => Cint(3))
const HPIPM_STATUS = (:solved, :max_iter, :min_step, :nan, :inconsistent_eq)
const HPIPM_INF = 1.0e10
const HPIPM_ITER_MAX = 1000

# Default build: HPIPM TARGET=AVX against BLASFEO X64_INTEL_HASWELL. On the
# Zen 5 laptop (nx = 64, nu = 32, N = 24, SPEED, no condensing) it had the best
# minimum and median-of-minima solve time over six runs against acados'
# GENERIC build and the X64_INTEL_SKYLAKE_X builds (HPIPM AVX and AVX512),
# though the spread between runs on the loaded machine (about 6 to 9 ms for
# every build) was larger than the differences between builds.
const HPIPM_DEFAULT_BUILD = "X64_INTEL_HASWELL"
const HPIPM_AVX_ROOT = joinpath(homedir(), "tools", "hpipm-avx")
const HPIPM_ACADOS_LIB = joinpath(homedir(), "tools", "acados", "lib")

function hpipm_default_dir()
    d = get(ENV, "HPIPM_LIB_DIR", "")
    isempty(d) || return d
    avx = joinpath(HPIPM_AVX_ROOT, HPIPM_DEFAULT_BUILD)
    isfile(joinpath(avx, "libhpipm.so")) && return avx
    return HPIPM_ACADOS_LIB
end

const _HPIPM_FN_NAMES = (
    :d_ocp_qp_dim_strsize, :d_ocp_qp_dim_memsize, :d_ocp_qp_dim_create, :d_ocp_qp_dim_set_all,
    :d_ocp_qp_strsize, :d_ocp_qp_memsize, :d_ocp_qp_create,
    :d_ocp_qp_set_A, :d_ocp_qp_set_B, :d_ocp_qp_set_b, :d_ocp_qp_set_Q, :d_ocp_qp_set_S, :d_ocp_qp_set_R,
    :d_ocp_qp_set_q, :d_ocp_qp_set_r,
    :d_ocp_qp_set_idxbx, :d_ocp_qp_set_lbx, :d_ocp_qp_set_ubx, :d_ocp_qp_set_lbx_mask, :d_ocp_qp_set_ubx_mask,
    :d_ocp_qp_set_idxbu, :d_ocp_qp_set_lbu, :d_ocp_qp_set_ubu, :d_ocp_qp_set_lbu_mask, :d_ocp_qp_set_ubu_mask,
    :d_ocp_qp_set_C, :d_ocp_qp_set_D, :d_ocp_qp_set_lg, :d_ocp_qp_set_ug, :d_ocp_qp_set_lg_mask, :d_ocp_qp_set_ug_mask,
    :d_ocp_qp_sol_strsize, :d_ocp_qp_sol_memsize, :d_ocp_qp_sol_create, :d_ocp_qp_sol_get_x, :d_ocp_qp_sol_get_u,
    :d_ocp_qp_ipm_arg_strsize, :d_ocp_qp_ipm_arg_memsize, :d_ocp_qp_ipm_arg_create,
    :d_ocp_qp_ipm_arg_set_default, :d_ocp_qp_ipm_arg_set,
    :d_ocp_qp_ipm_ws_strsize, :d_ocp_qp_ipm_ws_memsize, :d_ocp_qp_ipm_ws_create,
    :d_ocp_qp_ipm_solve, :d_ocp_qp_ipm_get_status, :d_ocp_qp_ipm_get_iter,
    :d_part_cond_qp_compute_block_size, :d_part_cond_qp_compute_dim,
    :d_part_cond_qp_arg_memsize, :d_part_cond_qp_arg_create, :d_part_cond_qp_arg_set_default,
    :d_part_cond_qp_ws_memsize, :d_part_cond_qp_ws_create,
    :d_part_cond_qp_cond, :d_part_cond_qp_cond_rhs, :d_part_cond_qp_expand_sol,
)

mutable struct _HpipmLib
    dir::String
    blasfeo::Ptr{Cvoid}
    hpipm::Ptr{Cvoid}
    fn::Dict{Symbol,Ptr{Cvoid}}
end

const _HPIPM_LIB = Ref{Union{Nothing,_HpipmLib}}(nothing)

function _hpipm_lib()
    L = _HPIPM_LIB[]
    L === nothing || return L
    dir = hpipm_default_dir()
    flags = Libdl.RTLD_NOW | Libdl.RTLD_GLOBAL
    bf = Libdl.dlopen(joinpath(dir, "libblasfeo.so"), flags)
    hp = Libdl.dlopen(joinpath(dir, "libhpipm.so"), flags)
    fn = Dict{Symbol,Ptr{Cvoid}}(s => Libdl.dlsym(hp, s) for s in _HPIPM_FN_NAMES)
    L = _HpipmLib(dir, bf, hp, fn)
    _HPIPM_LIB[] = L
    return L
end

# Build provenance of a library directory: BUILD_INFO for the local builds,
# the known acados configuration otherwise.
function hpipm_build_info(dir::AbstractString)
    d = Dict{String,Any}("lib_dir" => String(dir))
    bi = joinpath(dir, "BUILD_INFO")
    if isfile(bi)
        for ln in eachline(bi)
            k, v = split(ln, '='; limit = 2)
            d[k] = v
        end
        d["build"] = "HPIPM and BLASFEO Makefiles, shared libraries (sources copied from acados 00947dd external/)"
    else
        d["build"] = "acados 00947dd (cmake)"
        d["hpipm_commit"] = "bad1123"
        d["hpipm_target"] = "GENERIC"
        d["blasfeo_target"] = "X64_AUTOMATIC"
        th = joinpath(dirname(dir), "include", "blasfeo", "include", "blasfeo_target.h")
        if isfile(th)
            m = match(r"#define TARGET_(X64_\w+|GENERIC|ARMV\w+)", read(th, String))
            m === nothing || (d["blasfeo_target"] = "X64_AUTOMATIC (" * m[1] * ")")
        end
    end
    return d
end

# ---------------------------------------------------------------------------
# Handle
# ---------------------------------------------------------------------------

# One HPIPM problem (dims, qp, sol) with its own buffers.
mutable struct _HpipmOCP
    N::Int
    dim_s::Vector{UInt8}; dim_m::Vector{UInt8}
    qp_s::Vector{UInt8};  qp_m::Vector{UInt8}
    sol_s::Vector{UInt8}; sol_m::Vector{UInt8}
end

mutable struct HpipmHandle
    lib::_HpipmLib
    stage::StageOCP
    N::Int
    N2::Int
    mode::String
    # HPIPM dims of the eliminated problem (stage k at index k+1)
    nx::Vector{Cint}; nu::Vector{Cint}; nbx::Vector{Cint}; nbu::Vector{Cint}; ng::Vector{Cint}; ns::Vector{Cint}
    # kept positions into the StageOCP bound / constraint arrays
    kbx::Vector{Vector{Int}}; kbu::Vector{Vector{Int}}; kg::Vector{Vector{Int}}
    # vector buffers handed to the setters
    bvec::Vector{Vector{Float64}}; rvec::Vector{Vector{Float64}}
    lbx::Vector{Vector{Float64}}; ubx::Vector{Vector{Float64}}; mlbx::Vector{Vector{Float64}}; mubx::Vector{Vector{Float64}}
    lbu::Vector{Vector{Float64}}; ubu::Vector{Vector{Float64}}; mlbu::Vector{Vector{Float64}}; mubu::Vector{Vector{Float64}}
    lg::Vector{Vector{Float64}};  ug::Vector{Vector{Float64}};  mlg::Vector{Vector{Float64}};  mug::Vector{Vector{Float64}}
    cx0::Vector{Float64}          # C_0 x0 (all rows)
    full::_HpipmOCP
    cond::Union{Nothing,_HpipmOCP}
    block_size::Vector{Cint}
    pc_arg_s::Vector{UInt8}; pc_arg_m::Vector{UInt8}
    pc_ws_s::Vector{UInt8};  pc_ws_m::Vector{UInt8}
    arg_s::Vector{UInt8}; arg_m::Vector{UInt8}
    ws_s::Vector{UInt8};  ws_m::Vector{UInt8}
    rhs_only::Bool                # set by update!: only vectors changed since the last cond
    xs::Vector{Vector{Float64}}; us::Vector{Vector{Float64}}
    status::Base.RefValue{Cint}; iter::Base.RefValue{Cint}
end

_hp_buf(n) = zeros(UInt8, max(Int(n), 64))

function _hp_new_ocp(L::_HpipmLib, N::Int, set_dims!::Function)
    f = L.fn
    dim_s = _hp_buf(ccall(f[:d_ocp_qp_dim_strsize], Csize_t, ()))
    dim_m = _hp_buf(ccall(f[:d_ocp_qp_dim_memsize], Csize_t, (Cint,), N))
    ccall(f[:d_ocp_qp_dim_create], Cvoid, (Cint, Ptr{Cvoid}, Ptr{Cvoid}), N, dim_s, dim_m)
    set_dims!(pointer(dim_s))
    qp_s = _hp_buf(ccall(f[:d_ocp_qp_strsize], Csize_t, ()))
    qp_m = _hp_buf(ccall(f[:d_ocp_qp_memsize], Csize_t, (Ptr{Cvoid},), dim_s))
    ccall(f[:d_ocp_qp_create], Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}), dim_s, qp_s, qp_m)
    sol_s = _hp_buf(ccall(f[:d_ocp_qp_sol_strsize], Csize_t, ()))
    sol_m = _hp_buf(ccall(f[:d_ocp_qp_sol_memsize], Csize_t, (Ptr{Cvoid},), dim_s))
    ccall(f[:d_ocp_qp_sol_create], Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}), dim_s, sol_s, sol_m)
    return _HpipmOCP(N, dim_s, dim_m, qp_s, qp_m, sol_s, sol_m)
end

# Resolve the variant's N2 ("N", "N/2", "N/4", "N/8", "1", or an integer).
function _hpipm_N2(spec, N::Int)
    if spec isa Integer
        return clamp(Int(spec), 1, N)
    end
    s = String(spec)
    s == "N" && return N
    s == "1" && return 1
    m = match(r"^N/(\d+)$", s)
    m === nothing && throw(ArgumentError("hpipm: bad N2 spec $(repr(spec))"))
    return clamp(round(Int, N / parse(Int, m[1])), 1, N)
end

# The family generators store a missing side of a one-sided bound as +-1e20;
# |v| >= 1e19 counts as infinite (as does Inf).
const HPIPM_BIG = 1.0e19
_hp_isinf(v) = !(abs(v) < HPIPM_BIG)
_hp_bounded(l, u) = !_hp_isinf(l) || !_hp_isinf(u)

function hpipm_setup(qp::QP, eps::Real, variant::AbstractDict)
    st = qp.stage::StageOCP
    L = _hpipm_lib()
    f = L.fn
    N = st.N
    mode = String(get(variant, "mode", "SPEED"))
    N2 = _hpipm_N2(get(variant, "N2", "N"), N)

    nx = Cint[k == 0 ? 0 : st.nx[k+1] for k in 0:N]
    nu = Cint[st.nu[k+1] for k in 0:N]
    kbx = [k == 0 ? Int[] : [j for j in eachindex(st.idxbx[k+1]) if _hp_bounded(st.lbx[k+1][j], st.ubx[k+1][j])] for k in 0:N]
    kbu = [[j for j in eachindex(st.idxbu[k+1]) if _hp_bounded(st.lbu[k+1][j], st.ubu[k+1][j])] for k in 0:N]
    kg = map(0:N) do k
        i = k + 1
        ngk = length(st.lg[i])
        filter(1:ngk) do j
            _hp_bounded(st.lg[i][j], st.ug[i][j]) || return false
            # stage 0 rows without u terms are constants once x0 is fixed
            k == 0 && (nu[1] == 0 || all(iszero, view(st.D[1], j, :))) && return false
            true
        end
    end
    nbx = Cint[length(v) for v in kbx]
    nbu = Cint[length(v) for v in kbu]
    ng = Cint[length(v) for v in kg]
    ns = zeros(Cint, N + 1)

    setdims!(dp) = ccall(f[:d_ocp_qp_dim_set_all], Cvoid,
                         (Ptr{Cint}, Ptr{Cint}, Ptr{Cint}, Ptr{Cint}, Ptr{Cint}, Ptr{Cint}, Ptr{Cvoid}),
                         nx, nu, nbx, nbu, ng, ns, dp)
    full = _hp_new_ocp(L, N, setdims!)

    vz(n) = zeros(Float64, n)
    h = HpipmHandle(L, st, N, N2, mode, nx, nu, nbx, nbu, ng, ns, kbx, kbu, kg,
                    [vz(nx[k+2]) for k in 0:N-1], [vz(nu[k+1]) for k in 0:N],
                    [vz(nbx[k+1]) for k in 0:N], [vz(nbx[k+1]) for k in 0:N], [vz(nbx[k+1]) for k in 0:N], [vz(nbx[k+1]) for k in 0:N],
                    [vz(nbu[k+1]) for k in 0:N], [vz(nbu[k+1]) for k in 0:N], [vz(nbu[k+1]) for k in 0:N], [vz(nbu[k+1]) for k in 0:N],
                    [vz(ng[k+1]) for k in 0:N], [vz(ng[k+1]) for k in 0:N], [vz(ng[k+1]) for k in 0:N], [vz(ng[k+1]) for k in 0:N],
                    vz(length(st.lg[1])),
                    full, nothing, Cint[],
                    UInt8[], UInt8[], UInt8[], UInt8[], UInt8[], UInt8[], UInt8[], UInt8[],
                    false,
                    [k == 0 ? copy(st.x0) : vz(st.nx[k+1]) for k in 0:N], [vz(st.nu[k+1]) for k in 0:N],
                    Ref{Cint}(0), Ref{Cint}(0))

    # matrices and index sets (structure)
    qpp = pointer(full.qp_s)
    setm(sym, k, M) = (Mc = Matrix{Float64}(M); GC.@preserve Mc ccall(f[sym], Cvoid, (Cint, Ptr{Float64}, Ptr{Cvoid}), k, Mc, qpp))
    seti(sym, k, v) = (vi = Cint.(v); GC.@preserve vi ccall(f[sym], Cvoid, (Cint, Ptr{Cint}, Ptr{Cvoid}), k, vi, qpp))
    for k in 0:N
        i = k + 1
        if k < N
            k > 0 && setm(:d_ocp_qp_set_A, k, st.A[i])
            nu[i] > 0 && setm(:d_ocp_qp_set_B, k, st.B[i])
        end
        nx[i] > 0 && setm(:d_ocp_qp_set_Q, k, st.Q[i])
        nu[i] > 0 && setm(:d_ocp_qp_set_R, k, st.R[i])
        (nx[i] > 0 && nu[i] > 0) && setm(:d_ocp_qp_set_S, k, st.S[i])
        nbx[i] > 0 && seti(:d_ocp_qp_set_idxbx, k, st.idxbx[i][kbx[i]] .- 1)
        nbu[i] > 0 && seti(:d_ocp_qp_set_idxbu, k, st.idxbu[i][kbu[i]] .- 1)
        if ng[i] > 0
            nx[i] > 0 && setm(:d_ocp_qp_set_C, k, st.C[i][kg[i], :])
            nu[i] > 0 && setm(:d_ocp_qp_set_D, k, st.D[i][kg[i], :])
        end
    end
    _hpipm_set_vectors!(h, st)

    # partial condensing
    ipm_dim = pointer(full.dim_s)
    if N2 < N
        h.block_size = zeros(Cint, N + 1)
        ccall(f[:d_part_cond_qp_compute_block_size], Cvoid, (Cint, Cint, Ptr{Cint}), N, N2, h.block_size)
        bs = h.block_size
        cdims!(dp) = ccall(f[:d_part_cond_qp_compute_dim], Cvoid, (Ptr{Cvoid}, Ptr{Cint}, Ptr{Cvoid}),
                           full.dim_s, bs, dp)
        h.cond = _hp_new_ocp(L, N2, cdims!)
        h.pc_arg_s = _hp_buf(64)
        h.pc_arg_m = _hp_buf(ccall(f[:d_part_cond_qp_arg_memsize], Csize_t, (Cint,), N2))
        ccall(f[:d_part_cond_qp_arg_create], Cvoid, (Cint, Ptr{Cvoid}, Ptr{Cvoid}), N2, h.pc_arg_s, h.pc_arg_m)
        ccall(f[:d_part_cond_qp_arg_set_default], Cvoid, (Ptr{Cvoid},), h.pc_arg_s)
        h.pc_ws_s = _hp_buf(64)
        h.pc_ws_m = _hp_buf(ccall(f[:d_part_cond_qp_ws_memsize], Csize_t, (Ptr{Cvoid}, Ptr{Cint}, Ptr{Cvoid}, Ptr{Cvoid}),
                               full.dim_s, bs, h.cond.dim_s, h.pc_arg_s))
        ccall(f[:d_part_cond_qp_ws_create], Cvoid, (Ptr{Cvoid}, Ptr{Cint}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}),
              full.dim_s, bs, h.cond.dim_s, h.pc_arg_s, h.pc_ws_s, h.pc_ws_m)
        ipm_dim = pointer(h.cond.dim_s)
    end

    # IPM arg: mode defaults, then tolerances, iteration cap, cold start
    h.arg_s = _hp_buf(ccall(f[:d_ocp_qp_ipm_arg_strsize], Csize_t, ()))
    h.arg_m = _hp_buf(ccall(f[:d_ocp_qp_ipm_arg_memsize], Csize_t, (Ptr{Cvoid},), ipm_dim))
    ccall(f[:d_ocp_qp_ipm_arg_create], Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}), ipm_dim, h.arg_s, h.arg_m)
    ccall(f[:d_ocp_qp_ipm_arg_set_default], Cvoid, (Cint, Ptr{Cvoid}), HPIPM_MODES[mode], h.arg_s)
    setarg(name, v::Float64) = (r = Ref(v); ccall(f[:d_ocp_qp_ipm_arg_set], Cvoid, (Cstring, Ptr{Cvoid}, Ptr{Cvoid}), name, r, h.arg_s))
    setarg(name, v::Integer) = (r = Ref(Cint(v)); ccall(f[:d_ocp_qp_ipm_arg_set], Cvoid, (Cstring, Ptr{Cvoid}, Ptr{Cvoid}), name, r, h.arg_s))
    for t in ("tol_stat", "tol_eq", "tol_ineq", "tol_comp")
        setarg(t, Float64(eps))
    end
    setarg("iter_max", Int(get(variant, "iter_max", HPIPM_ITER_MAX)))
    setarg("warm_start", 0)
    h.ws_s = _hp_buf(ccall(f[:d_ocp_qp_ipm_ws_strsize], Csize_t, ()))
    h.ws_m = _hp_buf(ccall(f[:d_ocp_qp_ipm_ws_memsize], Csize_t, (Ptr{Cvoid}, Ptr{Cvoid}), ipm_dim, h.arg_s))
    ccall(f[:d_ocp_qp_ipm_ws_create], Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}), ipm_dim, h.arg_s, h.ws_s, h.ws_m)
    h.rhs_only = false
    return h
end

# Fill `val`/`mask` for kept bound positions `keep` of (l, u); sgn = -1 for the
# lower side, +1 for the upper side.
@inline function _hp_fill_bound!(val, mask, src, keep, sgn)
    @inbounds for (t, j) in enumerate(keep)
        v = src[j]
        if !_hp_isinf(v)
            val[t] = v; mask[t] = 1.0
        else
            val[t] = sgn * HPIPM_INF; mask[t] = 0.0
        end
    end
end

# Set every vector (b, q, r, bounds, masks, lg/ug) from `st`, eliminating st.x0.
function _hpipm_set_vectors!(h::HpipmHandle, st::StageOCP)
    f = h.lib.fn
    qpp = pointer(h.full.qp_s)
    N = h.N
    x0 = st.x0
    setv(sym, k, v) = ccall(f[sym], Cvoid, (Cint, Ptr{Float64}, Ptr{Cvoid}), k, v, qpp)
    GC.@preserve h begin
        # stage 0 with x0 eliminated
        if N > 0
            b0 = h.bvec[1]
            copyto!(b0, st.b[1]); mul!(b0, st.A[1], x0, 1.0, 1.0)
        end
        r0 = h.rvec[1]
        if h.nu[1] > 0
            copyto!(r0, st.ru[1])
            st.nx[1] > 0 && mul!(r0, st.S[1], x0, 1.0, 1.0)
        end
        if h.ng[1] > 0
            mul!(h.cx0, st.C[1], x0)
        end
        for k in 0:N
            i = k + 1
            if k < N
                k > 0 && (copyto!(h.bvec[i], st.b[i]))
                setv(:d_ocp_qp_set_b, k, h.bvec[i])
            end
            h.nx[i] > 0 && setv(:d_ocp_qp_set_q, k, st.qx[i])
            if h.nu[i] > 0
                k > 0 && copyto!(h.rvec[i], st.ru[i])
                setv(:d_ocp_qp_set_r, k, h.rvec[i])
            end
            if h.nbx[i] > 0
                _hp_fill_bound!(h.lbx[i], h.mlbx[i], st.lbx[i], h.kbx[i], -1.0)
                _hp_fill_bound!(h.ubx[i], h.mubx[i], st.ubx[i], h.kbx[i], 1.0)
                setv(:d_ocp_qp_set_lbx, k, h.lbx[i]); setv(:d_ocp_qp_set_ubx, k, h.ubx[i])
                setv(:d_ocp_qp_set_lbx_mask, k, h.mlbx[i]); setv(:d_ocp_qp_set_ubx_mask, k, h.mubx[i])
            end
            if h.nbu[i] > 0
                _hp_fill_bound!(h.lbu[i], h.mlbu[i], st.lbu[i], h.kbu[i], -1.0)
                _hp_fill_bound!(h.ubu[i], h.mubu[i], st.ubu[i], h.kbu[i], 1.0)
                setv(:d_ocp_qp_set_lbu, k, h.lbu[i]); setv(:d_ocp_qp_set_ubu, k, h.ubu[i])
                setv(:d_ocp_qp_set_lbu_mask, k, h.mlbu[i]); setv(:d_ocp_qp_set_ubu_mask, k, h.mubu[i])
            end
            if h.ng[i] > 0
                _hp_fill_bound!(h.lg[i], h.mlg[i], st.lg[i], h.kg[i], -1.0)
                _hp_fill_bound!(h.ug[i], h.mug[i], st.ug[i], h.kg[i], 1.0)
                if k == 0
                    @inbounds for (t, j) in enumerate(h.kg[1])
                        h.mlg[1][t] != 0.0 && (h.lg[1][t] -= h.cx0[j])
                        h.mug[1][t] != 0.0 && (h.ug[1][t] -= h.cx0[j])
                    end
                end
                setv(:d_ocp_qp_set_lg, k, h.lg[i]); setv(:d_ocp_qp_set_ug, k, h.ug[i])
                setv(:d_ocp_qp_set_lg_mask, k, h.mlg[i]); setv(:d_ocp_qp_set_ug_mask, k, h.mug[i])
            end
        end
    end
    return nothing
end

function hpipm_solve!(h::HpipmHandle)
    f = h.lib.fn
    full = h.full
    GC.@preserve h begin
        if h.cond === nothing
            ccall(f[:d_ocp_qp_ipm_solve], Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}),
                  full.qp_s, full.sol_s, h.arg_s, h.ws_s)
        else
            c = h.cond
            ccall(h.rhs_only ? f[:d_part_cond_qp_cond_rhs] : f[:d_part_cond_qp_cond], Cvoid,
                  (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}), full.qp_s, c.qp_s, h.pc_arg_s, h.pc_ws_s)
            ccall(f[:d_ocp_qp_ipm_solve], Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}),
                  c.qp_s, c.sol_s, h.arg_s, h.ws_s)
            ccall(f[:d_part_cond_qp_expand_sol], Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}),
                  full.qp_s, c.sol_s, full.sol_s, h.pc_arg_s, h.pc_ws_s)
            h.rhs_only = false  # a solve! without update! condenses everything again
        end
        ccall(f[:d_ocp_qp_ipm_get_status], Cvoid, (Ptr{Cvoid}, Ptr{Cint}), h.ws_s, h.status)
        ccall(f[:d_ocp_qp_ipm_get_iter], Cvoid, (Ptr{Cvoid}, Ptr{Cint}), h.ws_s, h.iter)
        for k in 0:h.N
            i = k + 1
            k > 0 && h.nx[i] > 0 && ccall(f[:d_ocp_qp_sol_get_x], Cvoid, (Cint, Ptr{Cvoid}, Ptr{Float64}), k, full.sol_s, h.xs[i])
            h.nu[i] > 0 && ccall(f[:d_ocp_qp_sol_get_u], Cvoid, (Cint, Ptr{Cvoid}, Ptr{Float64}), k, full.sol_s, h.us[i])
        end
    end
    s = Int(h.status[])
    status = 0 <= s < length(HPIPM_STATUS) ? HPIPM_STATUS[s+1] : :failed
    return SolveResult(canonical_from_stages(h.stage, h.xs, h.us), nothing, status, Int(h.iter[]), NaN)
end

function hpipm_update!(h::HpipmHandle, qp::QP)
    st = qp.stage::StageOCP
    _hpipm_check_pattern(h, st)
    _hpipm_set_vectors!(h, st)
    h.stage = st                 # x0 of the new problem for canonical_from_stages
    copyto!(h.xs[1], st.x0)
    h.rhs_only = h.cond !== nothing
    return nothing
end

# The bounded-index pattern is structure: a bound that was dropped at setup
# (both sides infinite) must stay infinite.
function _hpipm_check_pattern(h::HpipmHandle, st::StageOCP)
    for k in 0:h.N
        i = k + 1
        if k > 0 && length(h.kbx[i]) != count(j -> _hp_bounded(st.lbx[i][j], st.ubx[i][j]), eachindex(st.idxbx[i]))
            throw(ArgumentError("hpipm update!: state bound pattern changed at stage $k"))
        end
        if length(h.kbu[i]) != count(j -> _hp_bounded(st.lbu[i][j], st.ubu[i][j]), eachindex(st.idxbu[i]))
            throw(ArgumentError("hpipm update!: input bound pattern changed at stage $k"))
        end
    end
    return nothing
end

hpipm_applicable(qp::QP) = qp.stage !== nothing && isempty(qp.socs)

function hpipm_variants()
    v = Dict{String,Any}[]
    for mode in ("SPEED_ABS", "SPEED", "BALANCE", "ROBUST"), N2 in ("N", "N/2", "N/4", "N/8", "1")
        push!(v, Dict{String,Any}("mode" => mode, "N2" => N2))
    end
    return v
end

function hpipm_info()
    L = _HPIPM_LIB[]
    dir = L === nothing ? hpipm_default_dir() : L.dir
    d = hpipm_build_info(dir)
    d["solver"] = "HPIPM"
    d["iter_max"] = HPIPM_ITER_MAX
    d["warm_start"] = 0
    d["tolerances"] = "tol_stat = tol_eq = tol_ineq = tol_comp = eps"
    d["x0"] = "eliminated (stage 0 has nx = 0)"
    d["infinite_bounds"] = "dropped if both sides infinite, else masked"
    return d
end

hpipm_spec() = SolverSpec(name = "hpipm", kind = :ipm,
                          applicable = hpipm_applicable,
                          variants = hpipm_variants(),
                          setup = hpipm_setup,
                          solve! = hpipm_solve!,
                          update! = hpipm_update!,
                          warm! = nothing,
                          info = hpipm_info)
