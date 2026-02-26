# Scalability benchmark for the pipeline with simulated computation (sleep).
#
# For a fixed total computation time T distributed across N stages,
# each stage sleeps T/N ms per payload. Ideal throughput is N/T msg/s.
# Deviations from ideal measure the communication and async task overhead.

from benchmark import run, Unit
from Pipeline import Pipeline
from ScalabilityStages import SleepSource, SleepTransform, SleepSink, NUM_MESSAGES

# ======================================
# Functions that build and run a pipeline
# with a fixed number of stages.
# Needed because Pipeline uses variadic
# comptime tuples, so each configuration
# is a different type at compile time.
# ======================================

# N=2: Source -> Sink
fn run_pipeline_2[Size: Int, T_ms: Int]():
    comptime SleepMs = T_ms // 2
    source = SleepSource[Size, SleepMs]()
    sink = SleepSink[Size, SleepMs]()
    pipeline = Pipeline((source, sink))
    pipeline.run()
    _ = pipeline

# N=3: Source -> T1 -> Sink
fn run_pipeline_3[Size: Int, T_ms: Int]():
    comptime SleepMs = T_ms // 3
    source = SleepSource[Size, SleepMs]()
    t1 = SleepTransform[Size, SleepMs]()
    sink = SleepSink[Size, SleepMs]()
    pipeline = Pipeline((source, t1, sink))
    pipeline.run()
    _ = pipeline

# N=4: Source -> T1 -> T2 -> Sink
fn run_pipeline_4[Size: Int, T_ms: Int]():
    comptime SleepMs = T_ms // 4
    source = SleepSource[Size, SleepMs]()
    t1 = SleepTransform[Size, SleepMs]()
    t2 = SleepTransform[Size, SleepMs]()
    sink = SleepSink[Size, SleepMs]()
    pipeline = Pipeline((source, t1, t2, sink))
    pipeline.run()
    _ = pipeline

# N=5: Source -> T1..T3 -> Sink
fn run_pipeline_5[Size: Int, T_ms: Int]():
    comptime SleepMs = T_ms // 5
    source = SleepSource[Size, SleepMs]()
    t1 = SleepTransform[Size, SleepMs]()
    t2 = SleepTransform[Size, SleepMs]()
    t3 = SleepTransform[Size, SleepMs]()
    sink = SleepSink[Size, SleepMs]()
    pipeline = Pipeline((source, t1, t2, t3, sink))
    pipeline.run()
    _ = pipeline

# N=6: Source -> T1..T4 -> Sink
fn run_pipeline_6[Size: Int, T_ms: Int]():
    comptime SleepMs = T_ms // 6
    source = SleepSource[Size, SleepMs]()
    t1 = SleepTransform[Size, SleepMs]()
    t2 = SleepTransform[Size, SleepMs]()
    t3 = SleepTransform[Size, SleepMs]()
    t4 = SleepTransform[Size, SleepMs]()
    sink = SleepSink[Size, SleepMs]()
    pipeline = Pipeline((source, t1, t2, t3, t4, sink))
    pipeline.run()
    _ = pipeline

# N=7: Source -> T1..T5 -> Sink
fn run_pipeline_7[Size: Int, T_ms: Int]():
    comptime SleepMs = T_ms // 7
    source = SleepSource[Size, SleepMs]()
    t1 = SleepTransform[Size, SleepMs]()
    t2 = SleepTransform[Size, SleepMs]()
    t3 = SleepTransform[Size, SleepMs]()
    t4 = SleepTransform[Size, SleepMs]()
    t5 = SleepTransform[Size, SleepMs]()
    sink = SleepSink[Size, SleepMs]()
    pipeline = Pipeline((source, t1, t2, t3, t4, t5, sink))
    pipeline.run()
    _ = pipeline

# N=8: Source -> T1..T6 -> Sink
fn run_pipeline_8[Size: Int, T_ms: Int]():
    comptime SleepMs = T_ms // 8
    source = SleepSource[Size, SleepMs]()
    t1 = SleepTransform[Size, SleepMs]()
    t2 = SleepTransform[Size, SleepMs]()
    t3 = SleepTransform[Size, SleepMs]()
    t4 = SleepTransform[Size, SleepMs]()
    t5 = SleepTransform[Size, SleepMs]()
    t6 = SleepTransform[Size, SleepMs]()
    sink = SleepSink[Size, SleepMs]()
    pipeline = Pipeline((source, t1, t2, t3, t4, t5, t6, sink))
    pipeline.run()
    _ = pipeline

# N=9: Source -> T1..T7 -> Sink
fn run_pipeline_9[Size: Int, T_ms: Int]():
    comptime SleepMs = T_ms // 9
    source = SleepSource[Size, SleepMs]()
    t1 = SleepTransform[Size, SleepMs]()
    t2 = SleepTransform[Size, SleepMs]()
    t3 = SleepTransform[Size, SleepMs]()
    t4 = SleepTransform[Size, SleepMs]()
    t5 = SleepTransform[Size, SleepMs]()
    t6 = SleepTransform[Size, SleepMs]()
    t7 = SleepTransform[Size, SleepMs]()
    sink = SleepSink[Size, SleepMs]()
    pipeline = Pipeline((source, t1, t2, t3, t4, t5, t6, t7, sink))
    pipeline.run()
    _ = pipeline

# N=10: Source -> T1..T8 -> Sink
fn run_pipeline_10[Size: Int, T_ms: Int]():
    comptime SleepMs = T_ms // 10
    source = SleepSource[Size, SleepMs]()
    t1 = SleepTransform[Size, SleepMs]()
    t2 = SleepTransform[Size, SleepMs]()
    t3 = SleepTransform[Size, SleepMs]()
    t4 = SleepTransform[Size, SleepMs]()
    t5 = SleepTransform[Size, SleepMs]()
    t6 = SleepTransform[Size, SleepMs]()
    t7 = SleepTransform[Size, SleepMs]()
    t8 = SleepTransform[Size, SleepMs]()
    sink = SleepSink[Size, SleepMs]()
    pipeline = Pipeline((source, t1, t2, t3, t4, t5, t6, t7, t8, sink))
    pipeline.run()
    _ = pipeline

# N=11: Source -> T1..T9 -> Sink
fn run_pipeline_11[Size: Int, T_ms: Int]():
    comptime SleepMs = T_ms // 11
    source = SleepSource[Size, SleepMs]()
    t1 = SleepTransform[Size, SleepMs]()
    t2 = SleepTransform[Size, SleepMs]()
    t3 = SleepTransform[Size, SleepMs]()
    t4 = SleepTransform[Size, SleepMs]()
    t5 = SleepTransform[Size, SleepMs]()
    t6 = SleepTransform[Size, SleepMs]()
    t7 = SleepTransform[Size, SleepMs]()
    t8 = SleepTransform[Size, SleepMs]()
    t9 = SleepTransform[Size, SleepMs]()
    sink = SleepSink[Size, SleepMs]()
    pipeline = Pipeline((source, t1, t2, t3, t4, t5, t6, t7, t8, t9, sink))
    pipeline.run()
    _ = pipeline

# N=12: Source -> T1..T10 -> Sink
fn run_pipeline_12[Size: Int, T_ms: Int]():
    comptime SleepMs = T_ms // 12
    source = SleepSource[Size, SleepMs]()
    t1 = SleepTransform[Size, SleepMs]()
    t2 = SleepTransform[Size, SleepMs]()
    t3 = SleepTransform[Size, SleepMs]()
    t4 = SleepTransform[Size, SleepMs]()
    t5 = SleepTransform[Size, SleepMs]()
    t6 = SleepTransform[Size, SleepMs]()
    t7 = SleepTransform[Size, SleepMs]()
    t8 = SleepTransform[Size, SleepMs]()
    t9 = SleepTransform[Size, SleepMs]()
    t10 = SleepTransform[Size, SleepMs]()
    sink = SleepSink[Size, SleepMs]()
    pipeline = Pipeline((source, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, sink))
    pipeline.run()
    _ = pipeline


# ======================================
# Runs a single pipeline configuration
# using the benchmark package for proper
# statistical timing with repetitions.
# ======================================
fn bench_config[Size: Int, N: Int, T_ms: Int]() raises:
    comptime SleepMs = T_ms // N
    comptime num_msgs = NUM_MESSAGES

    # use the benchmark package to run with multiple iterations
    @parameter
    if N == 2:
        report = run[func2 = run_pipeline_2[Size, T_ms]](max_iters=5, min_runtime_secs=1, max_runtime_secs=15, max_batch_size=1)
        
    elif N == 3:
        report = run[func2 = run_pipeline_3[Size, T_ms]](max_iters=5, min_runtime_secs=1, max_runtime_secs=15, max_batch_size=1)
    elif N == 4:
        report = run[func2 = run_pipeline_4[Size, T_ms]](max_iters=5, min_runtime_secs=1, max_runtime_secs=15, max_batch_size=1)
    elif N == 5:
        report = run[func2 = run_pipeline_5[Size, T_ms]](max_iters=5, min_runtime_secs=1, max_runtime_secs=15, max_batch_size=1)
    elif N == 6:
        report = run[func2 = run_pipeline_6[Size, T_ms]](max_iters=5, min_runtime_secs=1, max_runtime_secs=15, max_batch_size=1)
    elif N == 7:
        report = run[func2 = run_pipeline_7[Size, T_ms]](max_iters=5, min_runtime_secs=1, max_runtime_secs=15, max_batch_size=1)
    elif N == 8:
        report = run[func2 = run_pipeline_8[Size, T_ms]](max_iters=5, min_runtime_secs=1, max_runtime_secs=15, max_batch_size=1)
    elif N == 9:
        report = run[func2 = run_pipeline_9[Size, T_ms]](max_iters=5, min_runtime_secs=1, max_runtime_secs=15, max_batch_size=1)
    elif N == 10:
        report = run[func2 = run_pipeline_10[Size, T_ms]](max_iters=5, min_runtime_secs=1, max_runtime_secs=15, max_batch_size=1)
    elif N == 11:
        report = run[func2 = run_pipeline_11[Size, T_ms]](max_iters=5, min_runtime_secs=1, max_runtime_secs=15, max_batch_size=1)
    elif N == 12:
        report = run[func2 = run_pipeline_12[Size, T_ms]](max_iters=5, min_runtime_secs=1, max_runtime_secs=15, max_batch_size=1)
    else:
        print("  -> ERROR: unsupported N")
        return

    # compute B, E(N), S(N) from the benchmark mean time
    mean_s = report.mean(Unit.ms) / 1000.0

    # use actual T = SleepMs * N (not T_ms) to account for integer division rounding
    # e.g. T_ms=100, N=3: SleepMs=33, actual total = 33*3 = 99ms, not 100ms
    comptime actual_T_s = Float64(SleepMs * N) / 1000.0

    # B = measured throughput (messages per second)
    B = Float64(num_msgs) / mean_s

    # E(N) = (B/N) * T  -> efficiency (1.0 = ideal, < 1.0 = overhead)
    E = (B / Float64(N)) * actual_T_s

    # S(N) = B * T -> scalability (how many times faster than sequential)
    S = B * actual_T_s

    print("  N=", N, ", Size=", Size, "B, SleepPerStage=", SleepMs, "ms",
          " -> mean:", report.mean(Unit.ms), "ms",
          " | iters:", report.iters(),
          " | B:", B, "msg/s",
          " | E(N):", E,
          " | S(N):", S)


# ======================================
# Comptime loop that tests all N values
# from 2 to 12 for a given payload size
# ======================================
fn bench_all_N[Size: Int, T_ms: Int]() raises:
    @parameter
    for n in range(2, 13):
        bench_config[Size, n, T_ms]()


# ======================================
# Runs all N for a given Size and T_ms,
# printing a header for easy parsing
# ======================================
fn bench_size_t[Size: Int, T_ms: Int]() raises:
    print("\n--- Size=" + String(Size) + "B, T=" + String(T_ms) + "ms ---")
    bench_all_N[Size, T_ms]()


# ======================================
# Main
# ======================================
def main():
    print("=" * 70)
    print("  Pipeline Scalability Benchmark")
    print("  Queue: MPMC_padding_optional_v2")
    print("  Messages per run:", NUM_MESSAGES)
    print("=" * 70)

    # Size=8B
    bench_size_t[8, 100]()
    bench_size_t[8, 50]()
    bench_size_t[8, 25]()
    bench_size_t[8, 10]()
    bench_size_t[8, 5]()

    # Size=64B
    bench_size_t[64, 100]()
    bench_size_t[64, 50]()
    bench_size_t[64, 25]()
    bench_size_t[64, 10]()
    bench_size_t[64, 5]()

    # Size=512B
    bench_size_t[512, 100]()
    bench_size_t[512, 50]()
    bench_size_t[512, 25]()
    bench_size_t[512, 10]()
    bench_size_t[512, 5]()

    # Size=4096B
    bench_size_t[4096, 100]()
    bench_size_t[4096, 50]()
    bench_size_t[4096, 25]()
    bench_size_t[4096, 10]()
    bench_size_t[4096, 5]()

    print("\n" + "=" * 70)
    print("  Benchmark complete!")
    print("=" * 70)
