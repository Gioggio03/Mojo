
from benchmark import run, Unit
from Pipeline import Pipeline
from BenchStages import BenchSource, BenchTransform, BenchSink
from Payload import Payload

# ========================
# Pipeline runner functions
# ========================
# Poiché Pipeline utilizza parametri variadici comptime, abbiamo bisogno di funzioni
# separate per ogni numero di stadi N.


# N=2: Source -> Sink
fn run_pipeline_2[Size: Int]():
    source = BenchSource[Size]()
    sink = BenchSink[Size]()
    pipeline = Pipeline((source, sink))
    pipeline.run()
    _ = pipeline

# N=3: Source -> Transform -> Sink
fn run_pipeline_3[Size: Int]():
    source = BenchSource[Size]()
    t1 = BenchTransform[Size]()
    sink = BenchSink[Size]()
    pipeline = Pipeline((source, t1, sink))
    pipeline.run()
    _ = pipeline

# N=5: Source -> T1 -> T2 -> T3 -> Sink
fn run_pipeline_5[Size: Int]():
    source = BenchSource[Size]()
    t1 = BenchTransform[Size]()
    t2 = BenchTransform[Size]()
    t3 = BenchTransform[Size]()
    sink = BenchSink[Size]()
    pipeline = Pipeline((source, t1, t2, t3, sink))
    pipeline.run()
    _ = pipeline

# N=10: Source -> T1 -> T2 -> ... -> T8 -> Sink
fn run_pipeline_10[Size: Int]():
    source = BenchSource[Size]()
    t1 = BenchTransform[Size]()
    t2 = BenchTransform[Size]()
    t3 = BenchTransform[Size]()
    t4 = BenchTransform[Size]()
    t5 = BenchTransform[Size]()
    t6 = BenchTransform[Size]()
    t7 = BenchTransform[Size]()
    t8 = BenchTransform[Size]()
    sink = BenchSink[Size]()
    pipeline = Pipeline((source, t1, t2, t3, t4, t5, t6, t7, t8, sink))
    pipeline.run()
    _ = pipeline

# ========================
# Benchmark helper
# ========================
fn bench_and_print[Size: Int, N: Int]() raises:
    print("  N=", N, ", Size=", Size, "B", end="")

    @parameter
    if N == 2:
        report = run[func2 = run_pipeline_2[Size]](max_iters=100, min_runtime_secs=2, max_runtime_secs=30, max_batch_size=1)
    elif N == 3:
        report = run[func2 = run_pipeline_3[Size]](max_iters=100, min_runtime_secs=2, max_runtime_secs=30, max_batch_size=1)
    elif N == 5:
        report = run[func2 = run_pipeline_5[Size]](max_iters=100, min_runtime_secs=2, max_runtime_secs=30, max_batch_size=1)
    elif N == 10:
        report = run[func2 = run_pipeline_10[Size]](max_iters=100, min_runtime_secs=2, max_runtime_secs=30, max_batch_size=1)
    else:
        print("  -> ERROR: unsupported N")
        return

    print(
        "  -> media:", report.mean(Unit.ms), "ms",
        " | min:", report.min(Unit.ms), "ms",
        " | max:", report.max(Unit.ms), "ms",
        " | iters:", report.iters()
    )

# ========================
# Benchmark all sizes for a given N
# ========================
fn bench_all_sizes[N: Int]() raises:
    bench_and_print[8, N]()
    bench_and_print[64, N]()
    bench_and_print[512, N]()
    bench_and_print[4096, N]()

# ========================
# Main
# ========================
def main():
    print("=" * 60)
    print("  Pipeline Benchmark")
    print("  Queue: MPMC_padding_optional")
    print("  Messages per run: 1000")
    print("=" * 60)

    print("\n--- N=2 (Source -> Sink) ---")
    bench_all_sizes[2]()

    print("\n--- N=3 (Source -> Transform -> Sink) ---")
    bench_all_sizes[3]()

    print("\n--- N=5 (Source -> 3×Transform -> Sink) ---")
    bench_all_sizes[5]()

    print("\n--- N=10 (Source -> 8×Transform -> Sink) ---")
    bench_all_sizes[10]()

    print("\n" + "=" * 60)
    print("  Benchmark complete!")
    print("=" * 60)
