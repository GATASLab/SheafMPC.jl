# dense.jl: dense kernels on column-major blocks addressed by (array, offset,
# leading dimension): BLAS-3 through libblastrampoline on pointers (no array
# headers, no allocation), and plain loops for small blocks, where a BLAS call
# costs more than the arithmetic.

using LinearAlgebra: BlasInt
using LinearAlgebra.BLAS: @blasfunc
import LinearAlgebra: libblastrampoline

# C[1:m, 1:n] = alpha * op(A) * op(B) + beta * C
@inline function _gemm!(ta::UInt8, tb::UInt8, m::Int, n::Int, k::Int, alpha::Float64, A::Ptr{Float64}, lda::Int,
                        B::Ptr{Float64}, ldb::Int, beta::Float64, C::Ptr{Float64}, ldc::Int)
    ccall((@blasfunc(dgemm_), libblastrampoline), Cvoid,
          (Ref{UInt8}, Ref{UInt8}, Ref{BlasInt}, Ref{BlasInt}, Ref{BlasInt}, Ref{Float64}, Ptr{Float64},
           Ref{BlasInt}, Ptr{Float64}, Ref{BlasInt}, Ref{Float64}, Ptr{Float64}, Ref{BlasInt}, Clong, Clong),
          ta, tb, m, n, k, alpha, A, lda, B, ldb, beta, C, ldc, 1, 1)
    return nothing
end

# lower triangle of C[1:n, 1:n] = alpha * op(A) * op(B) + beta * C
@inline function _gemmt!(ta::UInt8, tb::UInt8, n::Int, k::Int, alpha::Float64, A::Ptr{Float64}, lda::Int,
                         B::Ptr{Float64}, ldb::Int, beta::Float64, C::Ptr{Float64}, ldc::Int)
    ccall((@blasfunc(dgemmt_), libblastrampoline), Cvoid,
          (Ref{UInt8}, Ref{UInt8}, Ref{UInt8}, Ref{BlasInt}, Ref{BlasInt}, Ref{Float64}, Ptr{Float64},
           Ref{BlasInt}, Ptr{Float64}, Ref{BlasInt}, Ref{Float64}, Ptr{Float64}, Ref{BlasInt}, Clong, Clong, Clong),
          UInt8('L'), ta, tb, n, k, alpha, A, lda, B, ldb, beta, C, ldc, 1, 1, 1)
    return nothing
end

# B[1:m, 1:n] = B * inv(op(A)), A unit lower triangular (n x n)
@inline function _trsm_rlt_unit!(m::Int, n::Int, A::Ptr{Float64}, lda::Int, B::Ptr{Float64}, ldb::Int)
    ccall((@blasfunc(dtrsm_), libblastrampoline), Cvoid,
          (Ref{UInt8}, Ref{UInt8}, Ref{UInt8}, Ref{UInt8}, Ref{BlasInt}, Ref{BlasInt}, Ref{Float64}, Ptr{Float64},
           Ref{BlasInt}, Ptr{Float64}, Ref{BlasInt}, Clong, Clong, Clong, Clong),
          UInt8('R'), UInt8('L'), UInt8('T'), UInt8('U'), m, n, 1.0, A, lda, B, ldb, 1, 1, 1, 1)
    return nothing
end

"Work (multiply-adds) above which a dense update goes to BLAS rather than loops."
const BLAS_THRESHOLD = Ref(6_000)

"""
    _ldlt_front!(Lx, off, h, w, d, f, signs, delta, T) -> number of regularized pivots

LDLt without pivoting of the h x w frontal panel stored at `Lx[off]` (leading
dimension h): on return its first w rows hold the unit lower triangle L11, the
last h - w rows L21, and `d[f:f+w-1]` the pivots. A pivot of the wrong sign or
of magnitude below `delta` is replaced by `signs[j] * delta` (static
regularization; quasi-definite matrices need none in exact arithmetic).
Blocked by panels of `NB` columns; trailing updates by BLAS when large.
"""
function _ldlt_front!(Lx::Vector{Float64}, off::Int, h::Int, w::Int, d::Vector{Float64}, f::Int,
                      signs::Vector{Float64}, delta::Float64, T::Vector{Float64})
    nreg = 0
    NB = 32
    o = off - 1                                   # F[i, j] = Lx[o + (j-1)*h + i]
    kb = 1
    @inbounds while kb <= w
        ke = min(kb + NB - 1, w)
        # unblocked on columns kb:ke, rows kb:h
        for k in kb:ke
            ck = o + (k - 1) * h
            dk = Lx[ck+k]
            sg = signs[f+k-1]
            if !(sg * dk > delta)
                dk = sg * delta; nreg += 1
            end
            d[f+k-1] = dk
            inv = 1.0 / dk
            for j in (k+1):ke
                cj = o + (j - 1) * h
                c = Lx[ck+j] * inv
                c == 0.0 && continue
                @simd for i in j:h
                    Lx[cj+i] = muladd(-Lx[ck+i], c, Lx[cj+i])
                end
            end
            if ke < w
                # keep L * d of this column for the trailing update
                bk = k - kb
                tb = bk * (h - ke)
                @simd for i in (ke+1):h
                    T[tb+i-ke] = Lx[ck+i]
                end
            end
            @simd for i in (k+1):h
                Lx[ck+i] *= inv
            end
        end
        if ke < w
            # F[i, j] -= sum_k T[i, k] * L[j, k] for j in ke+1:w, i in j:h
            bw = ke - kb + 1
            hr = h - ke                           # rows ke+1:h
            wr = w - ke                           # columns ke+1:w
            if hr * wr * bw >= BLAS_THRESHOLD[]
                GC.@preserve Lx T begin
                    pL = pointer(Lx, o + (kb - 1) * h + ke + 1)      # L[ke+1, kb]
                    pC = pointer(Lx, o + ke * h + ke + 1)            # F[ke+1, ke+1]
                    pT = pointer(T)
                    _gemmt!(UInt8('N'), UInt8('T'), wr, bw, -1.0, pT, hr, pL, h, 1.0, pC, h)
                    if hr > wr
                        _gemm!(UInt8('N'), UInt8('T'), hr - wr, wr, bw, -1.0, pT + 8 * wr, hr, pL, h, 1.0,
                               pC + 8 * wr, h)
                    end
                end
            else
                for j in (ke+1):w
                    cj = o + (j - 1) * h
                    for k in kb:ke
                        bk = k - kb
                        c = Lx[o+(k-1)*h+j]
                        c == 0.0 && continue
                        tb = bk * hr - ke
                        @simd for i in j:h
                            Lx[cj+i] = muladd(-T[tb+i], c, Lx[cj+i])
                        end
                    end
                end
            end
        end
        kb = ke + 1
    end
    return nreg
end

"""
    _front_update!(U, uo, r, Lx, off, h, w, d, f, T)

U[1:r, 1:r] (lower triangle, at `U[uo+1]`, leading dimension r) -=
L21 * D * L21', with L21 the last r rows of the panel at `Lx[off]`
(`overwrite`: U = -L21 * D * L21').
"""
function _front_update!(U::Vector{Float64}, uo::Int, r::Int, Lx::Vector{Float64}, off::Int, h::Int, w::Int,
                        d::Vector{Float64}, f::Int, T::Vector{Float64}; overwrite::Bool = false)
    o = off - 1 + w                               # L21[i, k] = Lx[o + (k-1)*h + i]
    @inbounds if r * r * w >= 2 * BLAS_THRESHOLD[]
        for k in 1:w
            dk = d[f+k-1]
            ck = o + (k - 1) * h
            tk = (k - 1) * r
            @simd for i in 1:r
                T[tk+i] = Lx[ck+i] * dk
            end
        end
        GC.@preserve U Lx T begin
            _gemmt!(UInt8('N'), UInt8('T'), r, w, -1.0, pointer(T), r, pointer(Lx, o + 1), h, overwrite ? 0.0 : 1.0,
                    pointer(U, uo + 1), r)
        end
    else
        for j in 1:r
            cj = uo + (j - 1) * r
            if overwrite
                c = Lx[o+j] * d[f]
                @simd for i in j:r
                    U[cj+i] = -Lx[o+i] * c
                end
            end
            for k in (overwrite ? 2 : 1):w
                ck = o + (k - 1) * h
                c = Lx[ck+j] * d[f+k-1]
                c == 0.0 && continue
                @simd for i in j:r
                    U[cj+i] = muladd(-Lx[ck+i], c, U[cj+i])
                end
            end
        end
    end
    return nothing
end
