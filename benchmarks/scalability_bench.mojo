# Benchmark di scalabilità della pipeline con calcolo simulato (sleep).
#
# L'idea: dato un tempo totale T di calcolo distribuito su N stadi,
# ogni stadio dorme T/N ms per payload. Il throughput ideale è N payload per T.
# Le deviazioni dall'ideale misurano l'overhead di comunicazione e gestione task.

from time import perf_counter_ns
from Pipeline import Pipeline
from ScalabilityStages import SleepSource, SleepTransform, SleepSink, NUM_MESSAGES

# ======================================
# Funzioni che costruiscono e lanciano
# una pipeline con un numero fisso di stadi.
# Servono perché Pipeline usa tuple variadic
# comptime, quindi ogni configurazione è un
# tipo diverso a tempo di compilazione.
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
# Funzione che esegue una singola
# configurazione e ne misura il tempo
# ======================================
fn bench_config[Size: Int, N: Int, T_ms: Int]():
    comptime SleepMs = T_ms // N
    comptime num_msgs = NUM_MESSAGES

    # misuriamo il tempo con perf_counter_ns (nanosecondi)
    start = perf_counter_ns()

    # dispatch comptime: chiama la run_pipeline giusta in base a N
    @parameter
    if N == 2:
        run_pipeline_2[Size, T_ms]()
    elif N == 3:
        run_pipeline_3[Size, T_ms]()
    elif N == 4:
        run_pipeline_4[Size, T_ms]()
    elif N == 5:
        run_pipeline_5[Size, T_ms]()
    elif N == 6:
        run_pipeline_6[Size, T_ms]()
    elif N == 7:
        run_pipeline_7[Size, T_ms]()
    elif N == 8:
        run_pipeline_8[Size, T_ms]()
    elif N == 9:
        run_pipeline_9[Size, T_ms]()
    elif N == 10:
        run_pipeline_10[Size, T_ms]()
    elif N == 11:
        run_pipeline_11[Size, T_ms]()
    elif N == 12:
        run_pipeline_12[Size, T_ms]()

    end = perf_counter_ns()
    elapsed_ms = Float64(end - start) / 1_000_000.0

    # throughput: quanti messaggi al secondo
    throughput = Float64(num_msgs) / (elapsed_ms / 1000.0)

    # tempo ideale: il primo messaggio attraversa tutti gli N stadi (= T_ms),
    # poi ogni messaggio successivo esce dopo SleepMs (il collo di bottiglia è uno stadio)
    ideal_ms = Float64(T_ms) + Float64(num_msgs - 1) * Float64(SleepMs)
    # efficienza: quanto siamo vicini al caso ideale (100% = nessun overhead)
    speedup = ideal_ms / elapsed_ms

    print("  N=", N, ", Size=", Size, "B, SleepPerStage=", SleepMs, "ms",
          " -> elapsed:", Int(elapsed_ms), "ms",
          " | throughput:", throughput, "msg/s",
          " | efficiency:", Int(speedup * 100), "%")


# ======================================
# Loop comptime che testa tutti gli N
# da 2 a 12 per una data dimensione
# di payload
# ======================================
fn bench_all_N[Size: Int, T_ms: Int]():
    @parameter
    for n in range(2, 13):
        bench_config[Size, n, T_ms]()


# ======================================
# Main
# ======================================
def main():
    # T = tempo totale di calcolo simulato per payload (in millisecondi)
    comptime T_ms = 100

    print("=" * 70)
    print("  Pipeline Scalability Benchmark")
    print("  Queue: MPMC_padding_optional_v2")
    print("  Tempo totale di calcolo T =", T_ms, "ms per payload")
    print("  Messaggi per run:", NUM_MESSAGES)
    print("=" * 70)

    print("\n--- Payload Size: 8B ---")
    bench_all_N[8, T_ms]()

    print("\n--- Payload Size: 64B ---")
    bench_all_N[64, T_ms]()

    print("\n--- Payload Size: 512B ---")
    bench_all_N[512, T_ms]()

    print("\n--- Payload Size: 4096B ---")
    bench_all_N[4096, T_ms]()

    print("\n" + "=" * 70)
    print("  Benchmark completato!")
    print("=" * 70)
