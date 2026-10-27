# The receding-horizon controller.

@testset "controller" begin

sc = GridScenario(rows = 4, cols = 4, H = 8, coherence = :agents, seed = 5)
fl = fleet(sc)

@testset "a step solves the reduced program of the current data" begin
    for res in (Fine(), Teams(row_teams(sc)), Teams(strip_teams(sc, 2)) ⊠ partial_condensing(4), full_condensing())
        ctrl = MPCController(fl, res; eps_abs = 1e-8, eps_rel = 1e-8)
        x = formation_start(sc)
        local info
        for k in 0:2
            refs, term = references(sc, k * sc.h)
            info = step!(ctrl, x, refs; terminal = term)
            @test info.status == :solved
            # offline: the same reduction of the same data
            fp = FleetProgram(fl; x0 = x, references = refs, terminal = term)
            off = res isa Fine ? test_solve(fp) : test_solve(reduce(fp, res))
            @test srelerr(info.J, off.J) < 1e-6
            u_off = first_inputs(fp, res isa Fine ? off.x : lift(reduce(fp, res), off))
            @test maximum(norm(info.u[i] - u_off[i]) for i in eachindex(u_off)) < 1e-4
            @test all(norm(info.u[i]) <= fl.agents[i].input.radius + 1e-6 for i in eachindex(info.u))
            x = plant_step(fl, x, info.u)
        end
        if res isa Teams
            @test isfinite(info.gap_upper) && info.gap_upper >= 0
        end
    end
end

@testset "warm starts: shifted, previous and cold give the same plans" begin
    scb = GridScenario(rows = 3, cols = 3, H = 8, coherence = :agents, umax_scale = 0.3, seed = 2)
    flb = fleet(scb)
    for res in (Fine(), Teams(row_teams(scb)), Teams(row_teams(scb)) ⊠ partial_condensing(2))
        ctrls = [MPCController(flb, res; warm = w, certify = false, eps_abs = 1e-8, eps_rel = 1e-8) for w in (:shift, :previous, :cold)]
        @test !isempty(ctrls[1].xmap) == !(res isa Product)
        x = formation_start(scb)
        for k in 0:5
            refs, term = references(scb, k * scb.h)
            infos = [step!(c, x, refs; terminal = term) for c in ctrls]
            @test all(i -> i.status == :solved, infos)
            @test srelerr(infos[1].J, infos[3].J) < 1e-6 && srelerr(infos[2].J, infos[3].J) < 1e-6
            x = plant_step(flb, x, infos[3].u)
        end
    end
end

@testset "teams of teams" begin
    ctrl = MPCController(fl, [Teams(row_teams(sc)), Teams([1, 1, 2, 2])])
    refs, term = references(sc)
    info = step!(ctrl, formation_start(sc), refs; terminal = term)
    fp = FleetProgram(fl; x0 = formation_start(sc), references = refs, terminal = term)
    @test info.status == :solved
    @test srelerr(info.J, test_solve(reduce(fp, Teams(strip_teams(sc, 2)))).J) < 1e-5
    @test feasibility(fp.program, plan(ctrl)).hard < 1e-8
end

@testset "30 steps without allocation growth" begin
    ctrl = MPCController(fl, Teams(row_teams(sc)))
    x = formation_start(sc)
    allocs = Int[]
    for k in 0:29
        refs, term = references(sc, k * sc.h)
        a = @allocated (info = step!(ctrl, x, refs; terminal = term))
        push!(allocs, a)
        @test info.status == :solved
        x = plant_step(fl, x, info.u)
    end
    @test maximum(allocs[3:end]) <= 1024              # a few bytes of keyword handling, constant
    @test maximum(allocs[21:30]) <= maximum(allocs[3:12])
    @test ctrl.steps == 30
    @test ctrl.info.t_total > 0 && ctrl.info.t_construct > 0
end

@testset "state sets changed in place match a rebuild" begin
    scs = GridScenario(rows = 3, cols = 3, H = 6, coherence = :agents, seed = 2)
    fl0 = fleet(scs)
    withst(st) = Fleet([Agent(ag.A, ag.B; g = ag.g, C = ag.C, Cr = ag.Cr, Q = ag.Q, R = ag.R, Cf = ag.Cf, Qf = ag.Qf,
                              input = ag.input, state = st[i], kind = ag.kind) for (i, ag) in enumerate(fl0.agents)],
                       fl0.edges; H = fl0.H, targets = fl0.targets, weights = fl0.weights)
    # a keep-out disc on the ground vehicles' lane, linearized at planned positions: one half-space per instant
    cdisc = [1.4, 0.45]; rad = 0.3
    function keepout(pos; c = cdisc)
        [ag.kind == :ground_vehicle ?
         [(n = normalize(pos[i][:, t+1] - c); Polyhedron(-(n' * ag.C), [-(rad + dot(n, c))]; pattern = repeat(ag.C[1:1, :] .!= 0 .|| ag.C[2:2, :] .!= 0, 1)))
          for t in 1:fl0.H] : nothing for (i, ag) in enumerate(fl0.agents)]
    end
    # first a far disc, the same normal for every vehicle (merged duplicate rows in a team), then the near one
    pos_far = [repeat([0.0, 0.0], 1, fl0.H + 1) for _ in 1:9]
    far = keepout(pos_far; c = [0.0, -10.0])
    for res in (Fine(), Teams(row_teams(scs)), Teams(row_teams(scs)) ⊠ partial_condensing(3))
        st = far
        ctrl = MPCController(withst(st), res; eps_abs = 1e-9, eps_rel = 1e-9)
        x = formation_start(scs)
        active = false
        local s0
        for k in 0:5
            r, rf = references(scs, k * scs.h)
            k > 0 && (st = keepout([X[1:2, :] for X in trajectories(ctrl.fp, shift_plan(ctrl.fp, plan(ctrl), x))[1]]))
            info = step!(ctrl, x, r; terminal = rf, states = k == 0 ? nothing : st)
            @test info.status == :solved && isempty(ctrl.fp.changed)
            k == 2 && (s0 = ctrl.solver)
            k > 2 && @test ctrl.solver === s0               # no rebuild once the merged rows were split
            # the rebuild: a new controller on the fleet with the new state sets
            C2 = MPCController(withst(st), res; eps_abs = 1e-9, eps_rel = 1e-9)
            i2 = step!(C2, x, r; terminal = rf)
            if ctrl.dedup == C2.dedup
                @test norm(ctrl.qmap.qp.A - C2.qmap.qp.A, Inf) <= 1e-13
            end
            @test srelerr(info.J, i2.J) < 1e-8
            @test norm(plan(ctrl) - plan(C2), Inf) < 1e-6
            if info.gap_upper isa Float64 && isfinite(i2.gap_upper)
                @test abs(info.gap_upper - i2.gap_upper) <= 1e-6 * max(1.0, i2.gap_upper)
            end
            Pf = ctrl.fp.program
            active |= feasibility(Pf, plan(ctrl)).cone < 1e-6 &&
                      any(minimum(Pf.nodes[v].b - Pf.nodes[v].A * plan(ctrl)[vrange(Pf, v)]) < 1e-5
                          for i in 1:9 if fl0.agents[i].kind == :ground_vehicle for v in ctrl.fp.vid[i, 2:end])
            x = plant_step(fl0, x, info.u)
        end
        @test active                                        # the keep-out binds
        res isa Teams && @test !ctrl.dedup                 # the merged rows stopped agreeing: rebuilt once without merging
    end
    # distributed MPC: the local QPs' matrices change in place
    st = far
    D = DistributedMPC(withst(st); rho = 0.3, eps_abs = 1e-9, eps_rel = 1e-9)
    x = formation_start(scs)
    for k in 0:3
        r, rf = references(scs, k * scs.h)
        k > 0 && (st = keepout([X[1:2, :] for X in trajectories(D.fp, shift_plan(D.fp, plan(D), x))[1]]))
        info = step!(D, x, r; terminal = rf, states = st)
        D2 = DistributedMPC(withst(st); rho = 0.3, eps_abs = 1e-9, eps_rel = 1e-9)
        i2 = step!(D2, x, r; terminal = rf)
        @test info.status == :solved && i2.status == :solved
        @test maximum(norm(N1.A - N2.A, Inf) for (N1, N2) in zip(D.R.program.nodes, D2.R.program.nodes)) <= 1e-13
        @test norm(plan(D) - plan(D2), Inf) < 1e-5
        x = plant_step(fl0, x, info.u)
    end
    # the rows and the pattern are fixed
    ag = fl0.agents[4]
    @test_throws ArgumentError set_state_set!(D.fp, 4, 1, [0.0 0.0 1.0 0.0], [1.0])         # outside the pattern
    @test_throws ArgumentError set_state_set!(D.fp, 4, 1, zeros(2, 4), [1.0, 1.0])          # two rows, not one
    @test_throws ArgumentError set_state_set!(D.fp, 1, 1, zeros(1, 6), [1.0])               # agent 1 has no state set
    @test_throws ArgumentError Polyhedron([1.0 1.0], [1.0]; pattern = Bool[1 0])
end

end
