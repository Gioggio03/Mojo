# SPOT TEST - Execute a SINGLE scalability test with fixed N, T, Size.
# CONFIGURATION: change the 3 constants below, then:
#   mojo build -O3 -I .. spot_test.mojo -o spot_test && ./spot_test
# To change NUM_MESSAGES, edit scalabilityStages.mojo or use:
#   sed -i 's/^comptime NUM_MESSAGES: Int = [0-9]*/comptime NUM_MESSAGES: Int = 500/' scalabilityStages.mojo
# This is useful for investigating anomalies without running full suites.

from benchmark import run, Unit
from MoStream import Pipeline, seq
from scalabilityStages import SleepSource, SleepTransform, SleepSink, NUM_MESSAGES
from time import perf_counter_ns

comptime TEST_N: Int = 10 # number of pipeline stages
comptime TEST_T_NS: Int = 1_000_000 # total compute time per message (in nanoseconds) - to be split evenly across stages
comptime TEST_SIZE: Int = 64 # payload size in bytes (8, 64, 512) - affects communication overhead and cache behavior
comptime USE_PINNING: Bool = True # whether to use CPU pinning (True/False) - can reduce variability in timing by reducing thread migration

# N=2: Source -> Sink
fn run_pipeline_2[Size: Int, T_ns: Int]() raises:
    comptime SleepNs = T_ns // 2
    source = SleepSource[Size, SleepNs]()
    sink = SleepSink[Size, SleepNs]()
    pipeline = Pipeline((seq(source), seq(sink)))
    pipeline.setPinning(USE_PINNING)
    pipeline.run()
    _ = pipeline

# N=3: Source -> T1 -> Sink
fn run_pipeline_3[Size: Int, T_ns: Int]() raises:
    comptime SleepNs = T_ns // 3
    source = SleepSource[Size, SleepNs]()
    t1 = SleepTransform[Size, SleepNs]()
    sink = SleepSink[Size, SleepNs]()
    pipeline = Pipeline((seq(source), seq(t1), seq(sink)))
    pipeline.setPinning(USE_PINNING)
    pipeline.run()
    _ = pipeline

# N=4: Source -> T1..T2 -> Sink
fn run_pipeline_4[Size: Int, T_ns: Int]() raises:
    comptime SleepNs = T_ns // 4
    source = SleepSource[Size, SleepNs]()
    t1 = SleepTransform[Size, SleepNs]()
    t2 = SleepTransform[Size, SleepNs]()
    sink = SleepSink[Size, SleepNs]()
    pipeline = Pipeline((seq(source), seq(t1), seq(t2), seq(sink)))
    pipeline.setPinning(USE_PINNING)
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
    pipeline = Pipeline((seq(source), seq(t1), seq(t2), seq(t3), seq(sink)))
    pipeline.setPinning(USE_PINNING)
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
    pipeline = Pipeline((seq(source), seq(t1), seq(t2), seq(t3), seq(t4), seq(sink)))
    pipeline.setPinning(USE_PINNING)
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
    pipeline = Pipeline((seq(source), seq(t1), seq(t2), seq(t3), seq(t4), seq(t5), seq(sink)))
    pipeline.setPinning(USE_PINNING)
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
    pipeline = Pipeline((seq(source), seq(t1), seq(t2), seq(t3), seq(t4), seq(t5), seq(t6), seq(sink)))
    pipeline.setPinning(USE_PINNING)
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
    pipeline = Pipeline((seq(source), seq(t1), seq(t2), seq(t3), seq(t4), seq(t5), seq(t6), seq(t7), seq(sink)))
    pipeline.setPinning(USE_PINNING)
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
    pipeline = Pipeline((seq(source), seq(t1), seq(t2), seq(t3), seq(t4), seq(t5), seq(t6), seq(t7), seq(t8), seq(sink)))
    pipeline.setPinning(USE_PINNING)
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
    pipeline = Pipeline((seq(source), seq(t1), seq(t2), seq(t3), seq(t4), seq(t5), seq(t6), seq(t7), seq(t8), seq(t9), seq(sink)))
    pipeline.setPinning(USE_PINNING)
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
    pipeline = Pipeline((seq(source), seq(t1), seq(t2), seq(t3), seq(t4), seq(t5), seq(t6), seq(t7), seq(t8), seq(t9), seq(t10), seq(sink)))
    pipeline.setPinning(USE_PINNING)
    pipeline.run()
    _ = pipeline

# Main
def main():
    comptime SleepNs = TEST_T_NS // TEST_N
    comptime T_ms = Float64(TEST_T_NS) / 1_000_000.0
    comptime sleep_ms = Float64(SleepNs) / 1_000_000.0
    comptime actual_T_s = Float64(SleepNs * TEST_N) / 1_000_000_000.0
    print("=" * 70)
    print("  SPOT TEST — Single Configuration")
    print("=" * 70)
    print("  N (stadi):", TEST_N)
    print("  T totale:", T_ms, "ms")
    print("  SleepPerStage:", sleep_ms, "ms")
    print("  Size:", TEST_SIZE, "B")
    print("  NUM_MESSAGES:", NUM_MESSAGES)
    print("  Pinning:", USE_PINNING)
    print("=" * 70)
    # --- Run con benchmark framework (media su più iterazioni) ---
    print("\n--- Benchmark Framework (media su iterazioni) ---")
    @parameter
    if TEST_N == 2:
        report = run[func1 = run_pipeline_2[TEST_SIZE, TEST_T_NS]](max_iters=5, min_runtime_secs=1, max_runtime_secs=30, max_batch_size=1)
    elif TEST_N == 3:
        report = run[func1 = run_pipeline_3[TEST_SIZE, TEST_T_NS]](max_iters=5, min_runtime_secs=1, max_runtime_secs=30, max_batch_size=1)
    elif TEST_N == 4:
        report = run[func1 = run_pipeline_4[TEST_SIZE, TEST_T_NS]](max_iters=5, min_runtime_secs=1, max_runtime_secs=30, max_batch_size=1)
    elif TEST_N == 5:
        report = run[func1 = run_pipeline_5[TEST_SIZE, TEST_T_NS]](max_iters=5, min_runtime_secs=1, max_runtime_secs=30, max_batch_size=1)
    elif TEST_N == 6:
        report = run[func1 = run_pipeline_6[TEST_SIZE, TEST_T_NS]](max_iters=5, min_runtime_secs=1, max_runtime_secs=30, max_batch_size=1)
    elif TEST_N == 7:
        report = run[func1 = run_pipeline_7[TEST_SIZE, TEST_T_NS]](max_iters=5, min_runtime_secs=1, max_runtime_secs=30, max_batch_size=1)
    elif TEST_N == 8:
        report = run[func1 = run_pipeline_8[TEST_SIZE, TEST_T_NS]](max_iters=5, min_runtime_secs=1, max_runtime_secs=30, max_batch_size=1)
    elif TEST_N == 9:
        report = run[func1 = run_pipeline_9[TEST_SIZE, TEST_T_NS]](max_iters=5, min_runtime_secs=1, max_runtime_secs=30, max_batch_size=1)
    elif TEST_N == 10:
        report = run[func1 = run_pipeline_10[TEST_SIZE, TEST_T_NS]](max_iters=5, min_runtime_secs=1, max_runtime_secs=30, max_batch_size=1)
    elif TEST_N == 11:
        report = run[func1 = run_pipeline_11[TEST_SIZE, TEST_T_NS]](max_iters=5, min_runtime_secs=1, max_runtime_secs=30, max_batch_size=1)
    elif TEST_N == 12:
        report = run[func1 = run_pipeline_12[TEST_SIZE, TEST_T_NS]](max_iters=5, min_runtime_secs=1, max_runtime_secs=30, max_batch_size=1)
    else:
        print("  ERROR: N non supportato (deve essere 2..12)")
        return
    mean_s = report.mean(Unit.ms) / 1000.0
    B = Float64(NUM_MESSAGES) / mean_s
    E = (B / Float64(TEST_N)) * actual_T_s
    S = B * actual_T_s
    print("  Iters:", report.iters())
    print("  Mean:", report.mean(Unit.ms), "ms")
    print("  Min:", report.min(Unit.ms), "ms")
    print("  Max:", report.max(Unit.ms), "ms")
    print("")
    print("  B (throughput):", B, "msg/s")
    print("  E(N) (efficiency):", E)
    print("  S(N) (speedup):", S)
    # --- Tempo ideale vs tempo misurato ---
    comptime ideal_time_s = Float64(NUM_MESSAGES) * Float64(SleepNs) / 1_000_000_000.0
    print("\n--- Analisi Overhead ---")
    print("  Tempo ideale (pipeline perfetta):", ideal_time_s * 1000.0, "ms")
    print("  Tempo misurato (media):", report.mean(Unit.ms), "ms")
    print("  Overhead totale:", report.mean(Unit.ms) - ideal_time_s * 1000.0, "ms")
    print("  Overhead per messaggio:", (report.mean(Unit.ms) - ideal_time_s * 1000.0) / Float64(NUM_MESSAGES), "ms")
    print("\n" + "=" * 70)
    print("  Spot test completato!")
    print("=" * 70)
