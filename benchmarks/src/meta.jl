# meta.jl: what every result file records about the machine and the software,
# and the load gate that keeps timing runs off a busy machine.

using Dates

function git_state(dir)
    d = isdir(dir) ? dir : dirname(dir)
    run_ok(cmd) = try
        strip(read(cmd, String))
    catch
        ""
    end
    sha = run_ok(`git -C $d rev-parse HEAD`)
    st = run_ok(`git -C $d status --porcelain --untracked-files=no`)
    diff = run_ok(`git -C $d diff HEAD`)
    return Dict{String,Any}("sha" => sha, "dirty" => !isempty(st),
                            "diff_sha1" => isempty(diff) ? "" : bytes2hex(SHA.sha1(diff)),
                            "dirty_files" => isempty(st) ? String[] : split(st, '\n'))
end

"The working-tree diff of the package under test (saved next to the results when dirty)."
package_diff(dir) = try
    read(`git -C $dir diff HEAD`, String)
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
