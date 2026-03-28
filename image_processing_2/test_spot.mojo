# Source-Rate Benchmark (Time-Based Source)
#
# Goal: find how much parallelism is needed in Gray/Blur/Sharp to match
#       the raw throughput of the Source stage (the theoretical ceiling).
#
# KEY DIFFERENCE from image_processing:
#   The source generates images for 60 seconds (time-based) instead of a
#   fixed number of images. This removes the dependency on NUM_IMAGES.
#
# Hardware: 24 physical cores (48 logical with HT — not used).
# Thread budget: source(1) + sink(1) = 2 fixed → max 22 transform threads.
#
# Structure:
#   Phase 0: Source baseline  — Source -> PassThrough -> Sink  (count-based, large N for stable measurement)
#   Phase 1: Sequential       — TimedSource -> Gray(1) -> Blur(1) -> Sharp(1) -> Sink  (60s)
#   Phase 2: Uniform sweep    — P=2,3,4,5,6,7  (max total: 7*3+2=23 threads)
#   Phase 3: Smart configs    — proportional to stage cost, up to G2 B14 S6
#                               (max total: 2+14+6+2=24 threads)
#
# Pipeline: Source -> Grayscale -> GaussianBlur -> Sharpen -> Sink

from memory import UnsafePointer
from MoStream import Pipeline, seq, parallel
#from image_stages import TimedImageSource, ImageSource, Grayscale, GaussianBlur, Sharpen, PassThrough, ImageSink
from image_stages_2 import TimedImageSource, ImageSource, Grayscale, GaussianBlur, Sharpen, PassThrough, ImageSink
from time import perf_counter_ns

comptime W: Int = 512
comptime H: Int = 512
comptime DURATION: Int = 60   # seconds
comptime BASELINE_N: Int = 5000  # large count for stable source baseline

# ============================================================================
# Helpers
# ============================================================================

fn elapsed_ms(t0: UInt) -> Float64:
    return Float64(Int(perf_counter_ns() - t0)) / 1_000_000.0

fn throughput(n: Int, ms: Float64) -> Float64:
    if ms <= 0.0:
        return 0.0
    return Float64(n) / (ms / 1000.0)

fn print_row(config: String, threads: Int, n: Int, ms: Float64, tput: Float64, source_tput: Float64):
    var eff = tput / source_tput * 100.0
    print("  " + config + " | threads=" + String(threads) + " | n=" + String(n) + " | " + String(ms) + " ms | " + String(tput) + " img/s | " + String(eff) + "%")

# ============================================================================
# Phase 0: Source baseline (target throughput)
# Source(1) -> PassThrough(1) -> Sink(1)
# Uses count-based source with large N for stable measurement.
# Total threads: 2
# ============================================================================
fn run_source_baseline() raises -> Float64:
    var source = ImageSource[W, H, BASELINE_N]()
    var pt = PassThrough()
    var sink = ImageSink()
    var count_ptr = sink.count_ptr
    var pipeline = Pipeline((seq(source), seq(pt), seq(sink)))
    pipeline.setPinning(True)
    var t0 = perf_counter_ns()
    pipeline.run()
    var ms = elapsed_ms(t0)
    _ = pipeline
    return ms

# ============================================================================
# Phase 1–3: Time-based pipeline runs
# Each function returns (count, elapsed_ms)
# ============================================================================

# Phase 1: Full sequential baseline
# TimedSource(60s) -> Gray(1) -> Blur(1) -> Sharp(1) -> Sink
# Total threads: 5
fn run_seq() raises -> Tuple[Int, Float64]:
    var source = TimedImageSource[W, H, DURATION]()
    var gray = Grayscale()
    var blur = GaussianBlur()
    var sharp = Sharpen()
    var sink = ImageSink()
    var count_ptr = sink.count_ptr
    var pipeline = Pipeline((seq(source), seq(gray), seq(blur), seq(sharp), seq(sink)))
    pipeline.setPinning(True)
    var t0 = perf_counter_ns()
    pipeline.run()
    var ms = elapsed_ms(t0)
    var n = count_ptr[]
    count_ptr.free()
    _ = pipeline
    return (n, ms)

# ============================================================================
# Phase 2: Uniform sweep — all transforms at the same P
# Max P=7: 7*3 + 2(src+sink) = 23 threads <= 24 physical cores
# ============================================================================

# P=2: 2*3+2=8 total threads
fn run_uniform_p2() raises -> Tuple[Int, Float64]:
    var source = TimedImageSource[W, H, DURATION]()
    var gray = Grayscale()
    var blur = GaussianBlur()
    var sharp = Sharpen()
    var sink = ImageSink()
    var count_ptr = sink.count_ptr
    var pipeline = Pipeline((seq(source), parallel(gray, 2), parallel(blur, 2), parallel(sharp, 2), seq(sink)))
    pipeline.setPinning(True)
    var t0 = perf_counter_ns()
    pipeline.run()
    var ms = elapsed_ms(t0)
    var n = count_ptr[]
    count_ptr.free()
    _ = pipeline
    return (n, ms)

# P=3: 3*3+2=11 total threads
fn run_uniform_p3() raises -> Tuple[Int, Float64]:
    var source = TimedImageSource[W, H, DURATION]()
    var gray = Grayscale()
    var blur = GaussianBlur()
    var sharp = Sharpen()
    var sink = ImageSink()
    var count_ptr = sink.count_ptr
    var pipeline = Pipeline((seq(source), parallel(gray, 3), parallel(blur, 3), parallel(sharp, 3), seq(sink)))
    pipeline.setPinning(True)
    var t0 = perf_counter_ns()
    pipeline.run()
    var ms = elapsed_ms(t0)
    var n = count_ptr[]
    count_ptr.free()
    _ = pipeline
    return (n, ms)

# P=4: 4*3+2=14 total threads
fn run_uniform_p4() raises -> Tuple[Int, Float64]:
    var source = TimedImageSource[W, H, DURATION]()
    var gray = Grayscale()
    var blur = GaussianBlur()
    var sharp = Sharpen()
    var sink = ImageSink()
    var count_ptr = sink.count_ptr
    var pipeline = Pipeline((seq(source), parallel(gray, 4), parallel(blur, 4), parallel(sharp, 4), seq(sink)))
    pipeline.setPinning(True)
    var t0 = perf_counter_ns()
    pipeline.run()
    var ms = elapsed_ms(t0)
    var n = count_ptr[]
    count_ptr.free()
    _ = pipeline
    return (n, ms)

# P=5: 5*3+2=17 total threads
fn run_uniform_p5() raises -> Tuple[Int, Float64]:
    var source = TimedImageSource[W, H, DURATION]()
    var gray = Grayscale()
    var blur = GaussianBlur()
    var sharp = Sharpen()
    var sink = ImageSink()
    var count_ptr = sink.count_ptr
    var pipeline = Pipeline((seq(source), parallel(gray, 5), parallel(blur, 5), parallel(sharp, 5), seq(sink)))
    pipeline.setPinning(True)
    var t0 = perf_counter_ns()
    pipeline.run()
    var ms = elapsed_ms(t0)
    var n = count_ptr[]
    count_ptr.free()
    _ = pipeline
    return (n, ms)

# P=6: 6*3+2=20 total threads
fn run_uniform_p6() raises -> Tuple[Int, Float64]:
    var source = TimedImageSource[W, H, DURATION]()
    var gray = Grayscale()
    var blur = GaussianBlur()
    var sharp = Sharpen()
    var sink = ImageSink()
    var count_ptr = sink.count_ptr
    var pipeline = Pipeline((seq(source), parallel(gray, 6), parallel(blur, 6), parallel(sharp, 6), seq(sink)))
    pipeline.setPinning(True)
    var t0 = perf_counter_ns()
    pipeline.run()
    var ms = elapsed_ms(t0)
    var n = count_ptr[]
    count_ptr.free()
    _ = pipeline
    return (n, ms)

# P=7: 7*3+2=23 total threads  (uniform maximum)
fn run_uniform_p7() raises -> Tuple[Int, Float64]:
    var source = TimedImageSource[W, H, DURATION]()
    var gray = Grayscale()
    var blur = GaussianBlur()
    var sharp = Sharpen()
    var sink = ImageSink()
    var count_ptr = sink.count_ptr
    var pipeline = Pipeline((seq(source), parallel(gray, 7), parallel(blur, 7), parallel(sharp, 7), seq(sink)))
    pipeline.setPinning(True)
    var t0 = perf_counter_ns()
    pipeline.run()
    var ms = elapsed_ms(t0)
    var n = count_ptr[]
    count_ptr.free()
    _ = pipeline
    return (n, ms)

# ============================================================================
# Phase 3: Smart configs — parallelism proportional to stage cost
#
# Blur is the heaviest stage, Sharp intermediate, Gray lightweight.
# Budget: 22 transform threads max (to stay within 24 physical cores total).
# ============================================================================

# G1 B2 S1 — 4 transform threads, total 6
fn run_smart_g1_b2_s1() raises -> Tuple[Int, Float64]:
    var source = TimedImageSource[W, H, DURATION]()
    var gray = Grayscale()
    var blur = GaussianBlur()
    var sharp = Sharpen()
    var sink = ImageSink()
    var count_ptr = sink.count_ptr
    var pipeline = Pipeline((seq(source), seq(gray), parallel(blur, 2), seq(sharp), seq(sink)))
    pipeline.setPinning(True)
    var t0 = perf_counter_ns()
    pipeline.run()
    var ms = elapsed_ms(t0)
    var n = count_ptr[]
    count_ptr.free()
    _ = pipeline
    return (n, ms)

# G1 B4 S2 — 7 transform threads, total 9
fn run_smart_g1_b4_s2() raises -> Tuple[Int, Float64]:
    var source = TimedImageSource[W, H, DURATION]()
    var gray = Grayscale()
    var blur = GaussianBlur()
    var sharp = Sharpen()
    var sink = ImageSink()
    var count_ptr = sink.count_ptr
    var pipeline = Pipeline((seq(source), seq(gray), parallel(blur, 4), parallel(sharp, 2), seq(sink)))
    pipeline.setPinning(True)
    var t0 = perf_counter_ns()
    pipeline.run()
    var ms = elapsed_ms(t0)
    var n = count_ptr[]
    count_ptr.free()
    _ = pipeline
    return (n, ms)

# G2 B8 S4 — 14 transform threads, total 16
fn run_smart_g2_b8_s4() raises -> Tuple[Int, Float64]:
    var source = TimedImageSource[W, H, DURATION]()
    var gray = Grayscale()
    var blur = GaussianBlur()
    var sharp = Sharpen()
    var sink = ImageSink()
    var count_ptr = sink.count_ptr
    var pipeline = Pipeline((seq(source), parallel(gray, 2), parallel(blur, 8), parallel(sharp, 4), seq(sink)))
    pipeline.setPinning(True)
    var t0 = perf_counter_ns()
    pipeline.run()
    var ms = elapsed_ms(t0)
    var n = count_ptr[]
    count_ptr.free()
    _ = pipeline
    return (n, ms)

# G2 B14 S6 — 22 transform threads, total 24  (smart maximum, exactly at budget)
fn run_smart_g2_b14_s6() raises -> Tuple[Int, Float64]:
    var source = TimedImageSource[W, H, DURATION]()
    var gray = Grayscale()
    var blur = GaussianBlur()
    var sharp = Sharpen()
    var sink = ImageSink()
    var count_ptr = sink.count_ptr
    var pipeline = Pipeline((seq(source), parallel(gray, 2), parallel(blur, 14), parallel(sharp, 6), seq(sink)))
    pipeline.setPinning(True)
    var t0 = perf_counter_ns()
    pipeline.run()
    var ms = elapsed_ms(t0)
    var n = count_ptr[]
    count_ptr.free()
    _ = pipeline
    return (n, ms)

# ============================================================================
# Main
# ============================================================================
def main():
    print("=" * 70)
    print("  Source-Rate Benchmark (Time-Based Source)")
    print("  Image: " + String(W) + "x" + String(H) + " | Duration=" + String(DURATION) + "s")
    print("  Pipeline: Source -> Gray -> Blur -> Sharp -> Sink")
    print("  Hardware budget: 24 physical cores")
    print("  Thread budget: 22 transform threads (24 - src - sink)")
    print("  Goal: approach Source throughput by tuning parallelism")
    print("=" * 70)

    # Warmup
    print("\n[Warmup]...")
    try:
        _ = run_source_baseline()
    except:
        pass
    print("[Warmup] done.\n")

    # ----------------------------------------------------------------
    # Phase 0: Source baseline
    # ----------------------------------------------------------------
    print("PHASE 0: Source baseline (theoretical ceiling)")
    print("  Config: Source(1) -> PassThrough(1) -> Sink(1)  [2 total threads, N=" + String(BASELINE_N) + "]")
    print("  " + "-" * 66)
    var t_source = run_source_baseline()
    var tput_source = throughput(BASELINE_N, t_source)
    print("  Time: " + String(t_source) + " ms | Throughput: " + String(tput_source) + " img/s  <-- TARGET")

    print("\n  " + "=" * 66)
    print("  Config                    | Threads | N images | Time (ms)  | Tput (img/s) | vs Source")
    print("  " + "-" * 66)

    # ----------------------------------------------------------------
    # Phase 1: Sequential
    # ----------------------------------------------------------------
    var res_seq = run_seq()
    var n_seq = res_seq[0]
    var t_seq = res_seq[1]
    var tput_seq = throughput(n_seq, t_seq)
    print_row("Gray(1) Blur(1) Sharp(1) [SEQ]", 5, n_seq, t_seq, tput_seq, tput_source)

    # ----------------------------------------------------------------
    # Summary
    # ----------------------------------------------------------------
    print("\n" + "=" * 70)
    print("  SUMMARY (time-based source, " + String(DURATION) + "s per config)")
    print("  Source ceiling:   " + String(tput_source) + " img/s  (target)")
    print("  Sequential:       " + String(tput_seq) + " img/s  (" + String(tput_seq / tput_source * 100.0) + "%)  [" + String(n_seq) + " images in " + String(DURATION) + "s]")
    print("=" * 70)
