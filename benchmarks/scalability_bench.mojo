# Scalability benchmark for the pipeline with simulated computation (busy-wait via perf_counter_ns).
# For a fixed total computation time T distributed across N stages,
# each stage busy-waits T/N ns per payload. Ideal throughput is N/T msg/s.
# Deviations from ideal measure the communication and async task overhead.

from benchmark import run, Unit
from MoStream import Pipeline
from scalabilityStages import SleepSource, SleepTransform, SleepSink, NUM_MESSAGES

# N=2: Source -> Sink
fn run_pipeline_2[Size: Int, T_ns: Int]() raises:
    comptime SleepNs = T_ns // 2
    source = SleepSource[Size, SleepNs]()
    sink = SleepSink[Size, SleepNs]()
    pipeline = Pipeline((source, sink))
    pipeline.setPinning(True)
    pipeline.run()
    _ = pipeline

# N=3: Source -> T1 -> Sink
fn run_pipeline_3[Size: Int, T_ns: Int]() raises:
    comptime SleepNs = T_ns // 3
    source = SleepSource[Size, SleepNs]()
    t1 = SleepTransform[Size, SleepNs]()
    sink = SleepSink[Size, SleepNs]()
    pipeline = Pipeline((source, t1, sink))
    pipeline.setPinning(True)
    pipeline.run()
    _ = pipeline

# N=4: Source -> T1 -> T2 -> Sink
fn run_pipeline_4[Size: Int, T_ns: Int]() raises:
    comptime SleepNs = T_ns // 4
    source = SleepSource[Size, SleepNs]()
    t1 = SleepTransform[Size, SleepNs]()
    t2 = SleepTransform[Size, SleepNs]()
    sink = SleepSink[Size, SleepNs]()
    pipeline = Pipeline((source, t1, t2, sink))
    pipeline.setPinning(True)
    pipeline.run()
    _ = pipeline

# N=5: Source -> T1..T3 -> Sink
fn run_pipeline_5[Size: Int, T_ns: Int]() raises:
    comptime SleepNs = T_ns // 5
    source = SleepSource[Size, SleepNs]()
    t1 = SleepTransform[Size, SleepNs]()
    t2 = SleepTransform[Size, SleepNs]()
    t3 = SleepTransform[Size, SleepNs]()
    sink = SleepSink[Size, SleepNs]()
    pipeline = Pipeline((source, t1, t2, t3, sink))
    pipeline.setPinning(True)
    pipeline.run()
    _ = pipeline

# N=6: Source -> T1..T4 -> Sink
fn run_pipeline_6[Size: Int, T_ns: Int]() raises:
    comptime SleepNs = T_ns // 6
    source = SleepSource[Size, SleepNs]()
    t1 = SleepTransform[Size, SleepNs]()
    t2 = SleepTransform[Size, SleepNs]()
    t3 = SleepTransform[Size, SleepNs]()
    t4 = SleepTransform[Size, SleepNs]()
    sink = SleepSink[Size, SleepNs]()
    pipeline = Pipeline((source, t1, t2, t3, t4, sink))
    pipeline.setPinning(True)
    pipeline.run()
    _ = pipeline

# N=7: Source -> T1..T5 -> Sink
fn run_pipeline_7[Size: Int, T_ns: Int]() raises:
    comptime SleepNs = T_ns // 7
    source = SleepSource[Size, SleepNs]()
    t1 = SleepTransform[Size, SleepNs]()
    t2 = SleepTransform[Size, SleepNs]()
    t3 = SleepTransform[Size, SleepNs]()
    t4 = SleepTransform[Size, SleepNs]()
    t5 = SleepTransform[Size, SleepNs]()
    sink = SleepSink[Size, SleepNs]()
    pipeline = Pipeline((source, t1, t2, t3, t4, t5, sink))
    pipeline.setPinning(True)
    pipeline.run()
    _ = pipeline

# N=8: Source -> T1..T6 -> Sink
fn run_pipeline_8[Size: Int, T_ns: Int]() raises:
    comptime SleepNs = T_ns // 8
    source = SleepSource[Size, SleepNs]()
    t1 = SleepTransform[Size, SleepNs]()
    t2 = SleepTransform[Size, SleepNs]()
    t3 = SleepTransform[Size, SleepNs]()
    t4 = SleepTransform[Size, SleepNs]()
    t5 = SleepTransform[Size, SleepNs]()
    t6 = SleepTransform[Size, SleepNs]()
    sink = SleepSink[Size, SleepNs]()
    pipeline = Pipeline((source, t1, t2, t3, t4, t5, t6, sink))
    pipeline.setPinning(True)
    pipeline.run()
    _ = pipeline

# N=9: Source -> T1..T7 -> Sink
fn run_pipeline_9[Size: Int, T_ns: Int]() raises:
    comptime SleepNs = T_ns // 9
    source = SleepSource[Size, SleepNs]()
    t1 = SleepTransform[Size, SleepNs]()
    t2 = SleepTransform[Size, SleepNs]()
    t3 = SleepTransform[Size, SleepNs]()
    t4 = SleepTransform[Size, SleepNs]()
    t5 = SleepTransform[Size, SleepNs]()
    t6 = SleepTransform[Size, SleepNs]()
    t7 = SleepTransform[Size, SleepNs]()
    sink = SleepSink[Size, SleepNs]()
    pipeline = Pipeline((source, t1, t2, t3, t4, t5, t6, t7, sink))
    pipeline.setPinning(True)
    pipeline.run()
    _ = pipeline

# N=10: Source -> T1..T8 -> Sink
fn run_pipeline_10[Size: Int, T_ns: Int]() raises:
    comptime SleepNs = T_ns // 10
    source = SleepSource[Size, SleepNs]()
    t1 = SleepTransform[Size, SleepNs]()
    t2 = SleepTransform[Size, SleepNs]()
    t3 = SleepTransform[Size, SleepNs]()
    t4 = SleepTransform[Size, SleepNs]()
    t5 = SleepTransform[Size, SleepNs]()
    t6 = SleepTransform[Size, SleepNs]()
    t7 = SleepTransform[Size, SleepNs]()
    t8 = SleepTransform[Size, SleepNs]()
    sink = SleepSink[Size, SleepNs]()
    pipeline = Pipeline((source, t1, t2, t3, t4, t5, t6, t7, t8, sink))
    pipeline.setPinning(True)
    pipeline.run()
    _ = pipeline

# N=11: Source -> T1..T9 -> Sink
fn run_pipeline_11[Size: Int, T_ns: Int]() raises:
    comptime SleepNs = T_ns // 11
    source = SleepSource[Size, SleepNs]()
    t1 = SleepTransform[Size, SleepNs]()
    t2 = SleepTransform[Size, SleepNs]()
    t3 = SleepTransform[Size, SleepNs]()
    t4 = SleepTransform[Size, SleepNs]()
    t5 = SleepTransform[Size, SleepNs]()
    t6 = SleepTransform[Size, SleepNs]()
    t7 = SleepTransform[Size, SleepNs]()
    t8 = SleepTransform[Size, SleepNs]()
    t9 = SleepTransform[Size, SleepNs]()
    sink = SleepSink[Size, SleepNs]()
    pipeline = Pipeline((source, t1, t2, t3, t4, t5, t6, t7, t8, t9, sink))
    pipeline.setPinning(True)
    pipeline.run()
    _ = pipeline

# N=12: Source -> T1..T10 -> Sink
fn run_pipeline_12[Size: Int, T_ns: Int]() raises:
    comptime SleepNs = T_ns // 12
    source = SleepSource[Size, SleepNs]()
    t1 = SleepTransform[Size, SleepNs]()
    t2 = SleepTransform[Size, SleepNs]()
    t3 = SleepTransform[Size, SleepNs]()
    t4 = SleepTransform[Size, SleepNs]()
    t5 = SleepTransform[Size, SleepNs]()
    t6 = SleepTransform[Size, SleepNs]()
    t7 = SleepTransform[Size, SleepNs]()
    t8 = SleepTransform[Size, SleepNs]()
    t9 = SleepTransform[Size, SleepNs]()
    t10 = SleepTransform[Size, SleepNs]()
    sink = SleepSink[Size, SleepNs]()
    pipeline = Pipeline((source, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, sink))
    pipeline.setPinning(True)
    pipeline.run()
    _ = pipeline

# Function bench_config runs the appropriate pipeline configuration based on N, measures the mean time,
fn bench_config[Size: Int, N: Int, T_ns: Int]() raises:
    comptime SleepNs = T_ns // N
    comptime num_msgs = NUM_MESSAGES

    # use the benchmark package to run with multiple iterations
    @parameter
    if N == 2:
        report = run[func1 = run_pipeline_2[Size, T_ns]](max_iters=5, min_runtime_secs=1, max_runtime_secs=15, max_batch_size=1)
    elif N == 3:
        report = run[func1 = run_pipeline_3[Size, T_ns]](max_iters=5, min_runtime_secs=1, max_runtime_secs=15, max_batch_size=1)
    elif N == 4:
        report = run[func1 = run_pipeline_4[Size, T_ns]](max_iters=5, min_runtime_secs=1, max_runtime_secs=15, max_batch_size=1)
    elif N == 5:
        report = run[func1 = run_pipeline_5[Size, T_ns]](max_iters=5, min_runtime_secs=1, max_runtime_secs=15, max_batch_size=1)
    elif N == 6:
        report = run[func1 = run_pipeline_6[Size, T_ns]](max_iters=5, min_runtime_secs=1, max_runtime_secs=15, max_batch_size=1)
    elif N == 7:
        report = run[func1 = run_pipeline_7[Size, T_ns]](max_iters=5, min_runtime_secs=1, max_runtime_secs=15, max_batch_size=1)
    elif N == 8:
        report = run[func1 = run_pipeline_8[Size, T_ns]](max_iters=5, min_runtime_secs=1, max_runtime_secs=15, max_batch_size=1)
    elif N == 9:
        report = run[func1 = run_pipeline_9[Size, T_ns]](max_iters=5, min_runtime_secs=1, max_runtime_secs=15, max_batch_size=1)
    elif N == 10:
        report = run[func1 = run_pipeline_10[Size, T_ns]](max_iters=5, min_runtime_secs=1, max_runtime_secs=15, max_batch_size=1)
    elif N == 11:
        report = run[func1 = run_pipeline_11[Size, T_ns]](max_iters=5, min_runtime_secs=1, max_runtime_secs=15, max_batch_size=1)
    elif N == 12:
        report = run[func1 = run_pipeline_12[Size, T_ns]](max_iters=5, min_runtime_secs=1, max_runtime_secs=15, max_batch_size=1)
    else:
        print("  -> ERROR: unsupported N")
        return

    # compute B, E(N), S(N) from the benchmark mean time
    mean_s = report.mean(Unit.ms) / 1000.0

    # use actual T = SleepNs * N (not T_ns) to account for integer division rounding
    # e.g. T_ns=100_000_000, N=3: SleepNs=33_333_333, actual total = 33_333_333*3 = 99_999_999 ns
    comptime actual_T_s = Float64(SleepNs * N) / 1_000_000_000.0

    # B = measured throughput (messages per second)
    B = Float64(num_msgs) / mean_s

    # E(N) = (B/N) * T  -> efficiency (1.0 = ideal, < 1.0 = overhead)
    E = (B / Float64(N)) * actual_T_s

    # S(N) = B * T -> scalability (how many times faster than sequential)
    S = B * actual_T_s

    # convert SleepNs to ms for display
    comptime sleep_ms = Float64(SleepNs) / 1_000_000.0

    print("  N=", N, ", Size=", Size, "B, SleepPerStage=", sleep_ms, "ms",
          " -> mean:", report.mean(Unit.ms), "ms",
          " | iters:", report.iters(),
          " | B:", B, "msg/s",
          " | E(N):", E,
          " | S(N):", S)

# Function bench_all_N runs all N configurations for a given Size and T_ns
fn bench_all_N[Size: Int, T_ns: Int]() raises:
    @parameter
    for n in range(2, 13):
        bench_config[Size, n, T_ns]()

# Function bench_size_t runs all N configurations for a given Size and T_ns, and prints a header
fn bench_size_t[Size: Int, T_ns: Int]() raises:
    comptime T_ms = Float64(T_ns) / 1_000_000.0
    print("\n--- Size=" + String(Size) + "B, T=" + String(T_ms) + "ms ---")
    bench_all_N[Size, T_ns]()

# Main
def main():
    print("=" * 70)
    print("  Pipeline Scalability Benchmark")
    print("  Queue: MPMC_padding_optional_v2")
    print("  Messages per run:", NUM_MESSAGES)
    print("  Timing: perf_counter_ns busy-wait")
    print("=" * 70)

    # Size=8B
    # Size=8B
    bench_size_t[8, 100_000_000]()
    bench_size_t[8, 50_000_000]()
    bench_size_t[8, 25_000_000]()
    bench_size_t[8, 10_000_000]()
    bench_size_t[8, 5_000_000]()

    # Size=64B
    bench_size_t[64, 100_000_000]()
    bench_size_t[64, 50_000_000]()
    bench_size_t[64, 25_000_000]()
    bench_size_t[64, 10_000_000]()
    bench_size_t[64, 5_000_000]()

    # Size=512B
    bench_size_t[512, 100_000_000]()
    bench_size_t[512, 50_000_000]()
    bench_size_t[512, 25_000_000]()
    bench_size_t[512, 10_000_000]()
    bench_size_t[512, 5_000_000]()

    # Size=4096B
    bench_size_t[4096, 100_000_000]()
    bench_size_t[4096, 50_000_000]()
    bench_size_t[4096, 25_000_000]()
    bench_size_t[4096, 10_000_000]()
    bench_size_t[4096, 5_000_000]()

    print("\n" + "=" * 70)
    print("  Benchmark complete!")
    print("=" * 70)
