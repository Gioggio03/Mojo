# This benchmark measures the overhead of the Pipeline framework itself, without any user computation.
# The source produces empty payloads, the transforms do nothing, and the sink just consumes the messages.
# This isolates the framework overhead and lets us see how it scales with the number of stages and message sizes.

from benchmark import run, Unit
from MoStream import Pipeline
from benchStages import BenchSource, BenchTransform, BenchSink, NUM_MESSAGES
from payload import Payload

# N=2: Source -> Sink
fn run_pipeline_2[Size: Int]():
    source = BenchSource[Size]()
    sink = BenchSink[Size]()
    pipeline = Pipeline((source, sink))
    pipeline.run()
    _ = pipeline

# N=3: Source -> T1 -> Sink
fn run_pipeline_3[Size: Int]():
    source = BenchSource[Size]()
    t1 = BenchTransform[Size]()
    sink = BenchSink[Size]()
    pipeline = Pipeline((source, t1, sink))
    pipeline.run()
    _ = pipeline

# N=4: Source -> T1 -> T2 -> Sink
fn run_pipeline_4[Size: Int]():
    source = BenchSource[Size]()
    t1 = BenchTransform[Size]()
    t2 = BenchTransform[Size]()
    sink = BenchSink[Size]()
    pipeline = Pipeline((source, t1, t2, sink))
    pipeline.run()
    _ = pipeline

# N=5: Source -> T1..T3 -> Sink
fn run_pipeline_5[Size: Int]():
    source = BenchSource[Size]()
    t1 = BenchTransform[Size]()
    t2 = BenchTransform[Size]()
    t3 = BenchTransform[Size]()
    sink = BenchSink[Size]()
    pipeline = Pipeline((source, t1, t2, t3, sink))
    pipeline.run()
    _ = pipeline

# N=6: Source -> T1..T4 -> Sink
fn run_pipeline_6[Size: Int]():
    source = BenchSource[Size]()
    t1 = BenchTransform[Size]()
    t2 = BenchTransform[Size]()
    t3 = BenchTransform[Size]()
    t4 = BenchTransform[Size]()
    sink = BenchSink[Size]()
    pipeline = Pipeline((source, t1, t2, t3, t4, sink))
    pipeline.run()
    _ = pipeline

# N=7: Source -> T1..T5 -> Sink
fn run_pipeline_7[Size: Int]():
    source = BenchSource[Size]()
    t1 = BenchTransform[Size]()
    t2 = BenchTransform[Size]()
    t3 = BenchTransform[Size]()
    t4 = BenchTransform[Size]()
    t5 = BenchTransform[Size]()
    sink = BenchSink[Size]()
    pipeline = Pipeline((source, t1, t2, t3, t4, t5, sink))
    pipeline.run()
    _ = pipeline

# N=8: Source -> T1..T6 -> Sink
fn run_pipeline_8[Size: Int]():
    source = BenchSource[Size]()
    t1 = BenchTransform[Size]()
    t2 = BenchTransform[Size]()
    t3 = BenchTransform[Size]()
    t4 = BenchTransform[Size]()
    t5 = BenchTransform[Size]()
    t6 = BenchTransform[Size]()
    sink = BenchSink[Size]()
    pipeline = Pipeline((source, t1, t2, t3, t4, t5, t6, sink))
    pipeline.run()
    _ = pipeline

# N=9: Source -> T1..T7 -> Sink
fn run_pipeline_9[Size: Int]():
    source = BenchSource[Size]()
    t1 = BenchTransform[Size]()
    t2 = BenchTransform[Size]()
    t3 = BenchTransform[Size]()
    t4 = BenchTransform[Size]()
    t5 = BenchTransform[Size]()
    t6 = BenchTransform[Size]()
    t7 = BenchTransform[Size]()
    sink = BenchSink[Size]()
    pipeline = Pipeline((source, t1, t2, t3, t4, t5, t6, t7, sink))
    pipeline.run()
    _ = pipeline

# N=10: Source -> T1..T8 -> Sink
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

# N=11: Source -> T1..T9 -> Sink
fn run_pipeline_11[Size: Int]():
    source = BenchSource[Size]()
    t1 = BenchTransform[Size]()
    t2 = BenchTransform[Size]()
    t3 = BenchTransform[Size]()
    t4 = BenchTransform[Size]()
    t5 = BenchTransform[Size]()
    t6 = BenchTransform[Size]()
    t7 = BenchTransform[Size]()
    t8 = BenchTransform[Size]()
    t9 = BenchTransform[Size]()
    sink = BenchSink[Size]()
    pipeline = Pipeline((source, t1, t2, t3, t4, t5, t6, t7, t8, t9, sink))
    pipeline.run()
    _ = pipeline

# N=12: Source -> T1..T10 -> Sink
fn run_pipeline_12[Size: Int]():
    source = BenchSource[Size]()
    t1 = BenchTransform[Size]()
    t2 = BenchTransform[Size]()
    t3 = BenchTransform[Size]()
    t4 = BenchTransform[Size]()
    t5 = BenchTransform[Size]()
    t6 = BenchTransform[Size]()
    t7 = BenchTransform[Size]()
    t8 = BenchTransform[Size]()
    t9 = BenchTransform[Size]()
    t10 = BenchTransform[Size]()
    sink = BenchSink[Size]()
    pipeline = Pipeline((source, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, sink))
    pipeline.run()
    _ = pipeline

# Function bench_and_print: runs the given pipeline and prints the results in a nice format
fn bench_and_print[Size: Int, N: Int]() raises:
    print("  N=", N, ", Size=", Size, "B", end="")

    @parameter
    if N == 2:
        report = run[func2 = run_pipeline_2[Size]](max_iters=100, min_runtime_secs=2, max_runtime_secs=30, max_batch_size=1)
    elif N == 3:
        report = run[func2 = run_pipeline_3[Size]](max_iters=100, min_runtime_secs=2, max_runtime_secs=30, max_batch_size=1)
    elif N == 4:
        report = run[func2 = run_pipeline_4[Size]](max_iters=100, min_runtime_secs=2, max_runtime_secs=30, max_batch_size=1)
    elif N == 5:
        report = run[func2 = run_pipeline_5[Size]](max_iters=100, min_runtime_secs=2, max_runtime_secs=30, max_batch_size=1)
    elif N == 6:
        report = run[func2 = run_pipeline_6[Size]](max_iters=100, min_runtime_secs=2, max_runtime_secs=30, max_batch_size=1)
    elif N == 7:
        report = run[func2 = run_pipeline_7[Size]](max_iters=100, min_runtime_secs=2, max_runtime_secs=30, max_batch_size=1)
    elif N == 8:
        report = run[func2 = run_pipeline_8[Size]](max_iters=100, min_runtime_secs=2, max_runtime_secs=30, max_batch_size=1)
    elif N == 9:
        report = run[func2 = run_pipeline_9[Size]](max_iters=100, min_runtime_secs=2, max_runtime_secs=30, max_batch_size=1)
    elif N == 10:
        report = run[func2 = run_pipeline_10[Size]](max_iters=100, min_runtime_secs=2, max_runtime_secs=30, max_batch_size=1)
    elif N == 11:
        report = run[func2 = run_pipeline_11[Size]](max_iters=100, min_runtime_secs=2, max_runtime_secs=30, max_batch_size=1)
    elif N == 12:
        report = run[func2 = run_pipeline_12[Size]](max_iters=100, min_runtime_secs=2, max_runtime_secs=30, max_batch_size=1)
    else:
        print("  -> ERROR: unsupported N")
        return

    print(
        "   -> mean:", report.mean(Unit.ms), "ms",
        " | min:", report.min(Unit.ms), "ms",
        " | max:", report.max(Unit.ms), "ms",
        " | iters:", report.iters()
    )

# Function bench_all_sizes: runs benchmarks for all sizes for a given N
fn bench_all_sizes[N: Int]() raises:
    bench_and_print[8, N]()
    bench_and_print[64, N]()
    bench_and_print[512, N]()
    bench_and_print[4096, N]()

# Main
def main():
    print("=" * 70)
    print("  Pipeline Benchmark (Zero Computation)")
    print("  Messages per run:", NUM_MESSAGES)
    print("=" * 70)

    @parameter
    for n in range(2, 13):
        print("\n--- N=" + String(n) + " ---")
        bench_all_sizes[n]()

    print("\n" + "=" * 70)
    print("  Benchmark complete!")
    print("=" * 70)
