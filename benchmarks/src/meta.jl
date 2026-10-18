# meta.jl: what every result file records about the machine and the software,
# and the load gate that keeps timing runs off a busy machine.

using Dates

"""
    git_state(dir; paths) -> Dict

HEAD, and whether the files under `paths` (git pathspecs, relative to the
repository root) differ from it. For the package under test the default is
`["src", "Project.toml"]`, what the solver is built from (the harness and the
package bench results live in the same repository); the harness is `["benchmarks"]`.
"""
function git_state(dir; paths = ["src", "Project.toml"])
    d = isdir(dir) ? dir : dirname(dir)
    run_ok(cmd) = try
        strip(read(cmd, String))
    catch
        ""
    end
    root = run_ok(`git -C $d rev-parse --show-toplevel`)
    if isempty(root)
        # an archived snapshot (hpg/prepare_ref.sh): the ref is recorded in a file next to it
        for (dd, f) in ((d, "PACKAGE_REF"), (dirname(d), "PACKAGE_REF"), (d, "HARNESS_REF"), (dirname(d), "HARNESS_REF"))
            ff = joinpath(dd, f)
            (paths == ["benchmarks"]) == (f == "HARNESS_REF") || continue
            isfile(ff) || continue
            w = split(strip(read(ff, String)))
            return Dict{String,Any}("sha" => w[1], "ref" => length(w) > 1 ? w[2] : "", "dirty" => false, "diff_sha1" => "",
                                    "dirty_files" => String[], "source" => "git archive snapshot ($f)")
        end
        return Dict{String,Any}("sha" => "", "dirty" => false, "diff_sha1" => "", "dirty_files" => String[])
    end
    sha = run_ok(`git -C $root rev-parse HEAD`)
    st = run_ok(`git -C $root status --porcelain --untracked-files=no -- $paths`)
    diff = run_ok(`git -C $root diff HEAD -- $paths`)
    return Dict{String,Any}("sha" => sha, "dirty" => !isempty(st),
                            "diff_sha1" => isempty(diff) ? "" : bytes2hex(SHA.sha1(diff)),
                            "dirty_files" => isempty(st) ? String[] : split(st, '\n'))
end

"The working-tree diff of the package under test (saved next to the results when dirty)."
package_diff(dir) = try
    read(`git -C $dir diff HEAD -- src Project.toml`, String)
catch
    ""
end

loadavg() = (try
    parse.(Float64, split(read("/proc/loadavg", String))[1:3])
catch
    [NaN, NaN, NaN]
end)

readfirst(path) = try
    strip(read(path, String))
catch
    ""
end

function machine_info()
    cpu = Sys.cpu_info()
    gov = readfirst("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor")
    boost = readfirst("/sys/devices/system/cpu/cpufreq/boost")
    aff = try
        strip(read(`taskset -cp $(getpid())`, String))
    catch
        ""
    end
    return Dict{String,Any}("host" => gethostname(), "cpu" => cpu[1].model, "ncpu" => length(cpu),
                            "governor" => gov, "boost" => boost, "affinity" => aff,
                            "julia" => string(VERSION), "julia_threads" => Threads.nthreads(),
                            "blas" => string(BLAS.get_config()), "blas_threads" => BLAS.get_num_threads(),
                            "slurm_job" => get(ENV, "SLURM_JOB_ID", ""), "date" => string(now()))
end

"""
    wait_for_load(; max_load, max_wait, poll) -> Dict

Block until the 1-minute load average is at most `max_load` (default 4), for
at most `max_wait` seconds; returns the load seen and whether the gate was
passed or timed out (recorded with every timed block).
"""
function wait_for_load(; max_load = parse(Float64, get(ENV, "BENCH_MAX_LOAD", "4")),
                       max_wait = parse(Float64, get(ENV, "BENCH_MAX_WAIT", "7200")), poll = 30.0)
    t0 = time(); waited = 0.0
    while true
        l = loadavg()
        if l[1] <= max_load
            return Dict{String,Any}("load" => l, "waited" => waited, "gate" => "passed")
        end
        if time() - t0 > max_wait
            return Dict{String,Any}("load" => l, "waited" => waited, "gate" => "timed_out")
        end
        sleep(poll); waited = time() - t0
    end
end
