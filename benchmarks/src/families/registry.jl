# registry.jl: instances (a closed-loop sequence of QPs plus references) of
# every family, from deterministic generators with seeds.
#
# A closed loop is run once, by the reference solver: QP k is built from the
# measured state, solved to high accuracy (reference.jl), its first input is
# applied to the plant with a seeded disturbance, and the next QP is built from
# the new state. The recorded sequence is then fed open loop to every solver
# (Kouzoupis et al. 2015), so all solvers see identical QPs.

using Random

function closed_loop(build, firstinput, plant, x0, L, seed)
    rng = Xoshiro(seed)
    seq = QP[]; refs = Reference[]
    x = x0
    for k in 0:L-1
        p = build(x, k)
        r = reference(p)
        push!(seq, p); push!(refs, r)
        startswith(r.status, "SOLVED") || r.source == "clarabel+polish" || @warn "reference of $(p.name) step $k: $(r.status)"
        k == L - 1 && break
        x = plant(x, firstinput(p, r.x), rng)
    end
    return seq, refs
end

function fleet_instance(; n, graph = :ring, cone = :box, b = 1, N = 24, L = 10, seed = 1, sigma = 0.01)
    t = @elapsed begin
        build = (x, k) -> fleet_qp(n = n, N = N, b = b, graph = graph, cone = cone, t0 = 0.4 + k * FL_H, x0 = x)
        fi = (p, x) -> [x[r] for r in fleet_first_inputs(p)]
        plant = (x, u, rng) -> [FL_Ad * x[i] + FL_Bd * u[i] + [0, 0, sigma * randn(rng), sigma * randn(rng)] for i in eachindex(x)]
        seq, refs = closed_loop(build, fi, plant, [zeros(4) for _ in 1:n], L, seed)
    end
    sm = fleet_shift_maps(seq[1])
    prm = Dict{String,Any}("n" => n, "graph" => string(graph), "cone" => string(cone), "b" => b, "N" => N, "L" => L,
                           "seed" => seed, "sigma" => sigma, "size" => n)
    return Instance("fleet_$(graph)_$(cone)" * (b == 1 ? "" : "_b$(b)"), seq[1].name, prm, seq, refs, sm, t)
end

"Shift maps of a banded stage QP extended with input balls (one cone of nu+1 rows per stage)."
function balls_shift_maps(p0::QP, pb::QP)
    xmap, ymap = stage_shift_maps(p0)
    nu = p0.stage.nu[1]; N = p0.stage.N; m0 = ncons(p0)
    ext = Int[]
    for k in 0:N-1, r in 1:nu+1
        push!(ext, m0 + min(k + 1, N - 1) * (nu + 1) + r)
    end
    return xmap, [ymap; ext]
end

function single_instance(; model = :di, N = 20, cone = :box, L = 10, seed = 1, sigma = 0.01)
    t = @elapsed begin
        if model == :di
            nx = 6
            mk = (x, k) -> (o = di_ocp(N = N, x0 = x, cone = cone);
                            p = stage_canonical("di_$(cone)_N$(N)", o; meta = Dict{String,Any}("family" => "single", "model" => "di", "N" => N, "cone" => string(cone)));
                            cone == :soc ? add_input_balls(p) : p)
            Ad = di_ocp(N = 1, x0 = zeros(6)).A[1]; Bd = di_ocp(N = 1, x0 = zeros(6)).B[1]
        else
            nx = 12
            mk = (x, k) -> stage_canonical("quad_N$(N)", quad_ocp(N = N, x0 = x); meta = Dict{String,Any}("family" => "single", "model" => "quad", "N" => N, "cone" => "box"))
            Ad = QUAD_Ad; Bd = QUAD_Bd
        end
        nu = size(Bd, 2)
        fi = (p, x) -> x[1:nu]
        plant = (x, u, rng) -> Ad * x + Bd * u + sigma * randn(rng, nx)
        seq, refs = closed_loop(mk, fi, plant, zeros(nx), L, seed)
    end
    sm = if model == :di && cone == :soc
        p0 = stage_canonical("tmp", di_ocp(N = N, x0 = zeros(6), cone = :soc))
        balls_shift_maps(p0, seq[1])
    else
        stage_shift_maps(seq[1])
    end
    prm = Dict{String,Any}("model" => string(model), "N" => N, "cone" => string(cone), "L" => L, "seed" => seed,
                           "sigma" => sigma, "size" => N)
    fam = model == :di ? "single_di_$(cone)" : "single_quad"
    return Instance(fam, seq[1].name, prm, seq, refs, sm, t)
end

function chain_instance(; M, N = 20, L = 10, seed = 1, wmax = 0.1)
    t = @elapsed begin
        A, B = chain_dynamics(M)
        mk = (x, k) -> stage_canonical("chain_M$(M)_N$(N)", chain_ocp(M = M, N = N, x0 = x);
                                       meta = Dict{String,Any}("family" => "chain", "M" => M, "N" => N))
        fi = (p, x) -> x[1:M-1]
        plant = (x, u, rng) -> A * x + B * u + [zeros(M); wmax .* (2 .* rand(rng, M) .- 1)]
        seq, refs = closed_loop(mk, fi, plant, chain_x0(M), L, seed)
    end
    prm = Dict{String,Any}("M" => M, "N" => N, "L" => L, "seed" => seed, "wmax" => wmax, "size" => M)
    return Instance("chain", seq[1].name, prm, seq, refs, stage_shift_maps(seq[1]), t)
end

const OSQPRAND_DIR = Ref(joinpath(@__DIR__, "..", "..", "data", "osqprand"))

function osqprand_instance(; nx, seed = 1, L = 10, sigma = 0.01)
    t = @elapsed begin
        m = read_osqprand(joinpath(OSQPRAND_DIR[], "osqprand_n$(nx)_s$(seed).json"))
        mk = (x, k) -> osqprand_qp(m, x)
        fi = osqprand_first_input
        # the plant keeps the measured state inside half the state box, where control.py draws x0
        plant = (x, u, rng) -> clamp.(m.A * x + m.B * u + sigma * randn(rng, m.nx), 0.5 .* m.xmin, 0.5 .* m.xmax)
        seq, refs = closed_loop(mk, fi, plant, m.x0, L, seed)
    end
    prm = Dict{String,Any}("nx" => nx, "nu" => m.nu, "T" => m.T, "seed" => seed, "L" => L, "sigma" => sigma, "size" => nx,
                           "numpy" => m.numpy, "scipy" => m.scipy)
    return Instance("osqprand", seq[1].name, prm, seq, refs, osqprand_shift_maps(seq[1]), t)
end

const REDUCED_DIR = Ref(joinpath(@__DIR__, "..", "..", "data", "reduced"))

"A level of the exported reduced fleet (gen/reduced_export.jl); the sequence is the files step000.qp, ..."
function reduced_instance(; rows = 8, cols = 8, H = 10, k, L = 10)
    t = @elapsed begin
        dir = joinpath(REDUCED_DIR[], "grid$(rows)x$(cols)_H$(H)_k$(k)")
        files = sort(filter(f -> endswith(f, ".qp"), readdir(dir)))[1:min(L, end)]
        seq = [read_qp(joinpath(dir, f)) for f in files]
        refs = [reference(p) for p in seq]
    end
    prm = Dict{String,Any}("rows" => rows, "cols" => cols, "n" => rows * cols, "H" => H, "k" => k, "L" => length(seq),
                           "teams" => seq[1].meta["teams"], "size" => seq[1].meta["teams"],
                           "t_pushforward_med" => median([Float64(p.meta["t_pushforward"]) for p in seq]))
    return Instance("reduced", seq[1].name, prm, seq, refs, nothing, t)
end
