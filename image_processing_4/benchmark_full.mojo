# Test Spot Benchmark — V4 stages (planar layout + SIMD)
#
# Structure:
#   Phase 0: Source baseline  — Source -> PassThrough -> Sink
#   Phase 1: Sequential       — Gray(1) -> Blur(1) -> Sharp(1)
#   Phase 2: Uniform sweep    — P=2,3,4,5,6,7
#   Phase 3: Optimal config   — tuned via run_tuning_v4.py (updated after tuning)
#
# Pipeline: Source -> Grayscale -> GaussianBlur -> Sharpen -> Sink
# Layout: PLANAR (R|G|B planes), SIMD with stride-1 loads

from MoStream import Pipeline, seq, parallel
from image_stages_4 import TimedImageSource, ImageSource, Grayscale, GaussianBlur, Sharpen, PassThrough, ImageSink
from time import perf_counter_ns

comptime W: Int = 512
comptime H: Int = 512
comptime DURATION: Int = 60
comptime BASELINE_N: Int = 5000

fn elapsed_ms(t0: UInt) -> Float64:
    return Float64(Int(perf_counter_ns() - t0)) / 1_000_000.0

fn throughput(n: Int, ms: Float64) -> Float64:
    if ms <= 0.0: return 0.0
    return Float64(n) / (ms / 1000.0)

fn print_row(config: String, threads: Int, n: Int, ms: Float64, tput: Float64, source_tput: Float64):
    var eff = tput / source_tput * 100.0
    print("  " + config + " | threads=" + String(threads) + " | n=" + String(n) + " | " + String(ms) + " ms | " + String(tput) + " img/s | " + String(eff) + "%")

fn run_source_baseline() raises -> Float64:
    var source = ImageSource[W, H, BASELINE_N]()
    var pt = PassThrough()
    var sink = ImageSink()
    _ = sink.count_ptr
    var pipeline = Pipeline((seq(source), seq(pt), seq(sink)))
    pipeline.setPinning(True)
    var t0 = perf_counter_ns()
    pipeline.run()
    var ms = elapsed_ms(t0)
    _ = pipeline
    return ms

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

fn run_uniform[P: Int]() raises -> Tuple[Int, Float64]:
    var source = TimedImageSource[W, H, DURATION]()
    var gray = Grayscale()
    var blur = GaussianBlur()
    var sharp = Sharpen()
    var sink = ImageSink()
    var count_ptr = sink.count_ptr
    var pipeline = Pipeline((seq(source), parallel(gray, P), parallel(blur, P), parallel(sharp, P), seq(sink)))
    pipeline.setPinning(True)
    var t0 = perf_counter_ns()
    pipeline.run()
    var ms = elapsed_ms(t0)
    var n = count_ptr[]
    count_ptr.free()
    _ = pipeline
    return (n, ms)

# Optimal config — updated after tuning with run_tuning_v4.py
# V4 stage costs (planar SIMD): Gray=???ms  Blur=???ms  Sharp=???ms
fn run_optimal() raises -> Tuple[Int, Float64]:
    var source = TimedImageSource[W, H, DURATION]()
    var gray = Grayscale()
    var blur = GaussianBlur()
    var sharp = Sharpen()
    var sink = ImageSink()
    var count_ptr = sink.count_ptr
    var pipeline = Pipeline((seq(source), parallel(gray, 3), parallel(blur, 8), parallel(sharp, 8), seq(sink)))
    pipeline.setPinning(True)
    var t0 = perf_counter_ns()
    pipeline.run()
    var ms = elapsed_ms(t0)
    var n = count_ptr[]
    count_ptr.free()
    _ = pipeline
    return (n, ms)

def main():
    print("=" * 70)
    print("  Test Spot Benchmark (V4 stages — Planar layout + SIMD)")
    print("  Image: " + String(W) + "x" + String(H) + " | Duration=" + String(DURATION) + "s")
    print("  Pipeline: Source -> Gray -> Blur -> Sharp -> Sink")
    print("=" * 70)

    print("\n[Warmup]...")
    try: _ = run_source_baseline()
    except: pass
    print("[Warmup] done.\n")

    var t_source = run_source_baseline()
    var tput_source = throughput(BASELINE_N, t_source)
    print("PHASE 0: Source baseline")
    print("  Throughput: " + String(tput_source) + " img/s  <-- TARGET\n")

    print("  Config             | Threads | N images | Time (ms)  | Tput (img/s) | vs Source")
    print("  " + "-" * 66)

    var res_seq = run_seq()
    var n_seq = res_seq[0]; var t_seq = res_seq[1]
    var tput_seq = throughput(n_seq, t_seq)
    print_row("SEQ  G1  B1  S1 ", 5, n_seq, t_seq, tput_seq, tput_source)

    var res_p2 = run_uniform[2]()
    var n_p2 = res_p2[0]; var t_p2 = res_p2[1]
    print_row("Uniform P=2     ", 8,  n_p2, t_p2, throughput(n_p2, t_p2), tput_source)

    var res_p3 = run_uniform[3]()
    var n_p3 = res_p3[0]; var t_p3 = res_p3[1]
    print_row("Uniform P=3     ", 11, n_p3, t_p3, throughput(n_p3, t_p3), tput_source)

    var res_p4 = run_uniform[4]()
    var n_p4 = res_p4[0]; var t_p4 = res_p4[1]
    print_row("Uniform P=4     ", 14, n_p4, t_p4, throughput(n_p4, t_p4), tput_source)

    var res_p5 = run_uniform[5]()
    var n_p5 = res_p5[0]; var t_p5 = res_p5[1]
    print_row("Uniform P=5     ", 17, n_p5, t_p5, throughput(n_p5, t_p5), tput_source)

    var res_p6 = run_uniform[6]()
    var n_p6 = res_p6[0]; var t_p6 = res_p6[1]
    print_row("Uniform P=6     ", 20, n_p6, t_p6, throughput(n_p6, t_p6), tput_source)

    var res_p7 = run_uniform[7]()
    var n_p7 = res_p7[0]; var t_p7 = res_p7[1]
    print_row("Uniform P=7     ", 23, n_p7, t_p7, throughput(n_p7, t_p7), tput_source)

    var res_opt = run_optimal()
    var n_opt = res_opt[0]; var t_opt = res_opt[1]
    var tput_opt = throughput(n_opt, t_opt)
    print_row("OPT  G3  B8  S8 ", 21, n_opt, t_opt, tput_opt, tput_source)

    print("\n" + "=" * 70)
    print("  SUMMARY")
    print("  Source ceiling: " + String(tput_source) + " img/s")
    print("  Sequential:     " + String(tput_seq) + " img/s  (" + String(tput_seq / tput_source * 100.0) + "%)")
    print("  Uniform P=2:    " + String(throughput(n_p2, t_p2)) + " img/s  (" + String(throughput(n_p2, t_p2) / tput_source * 100.0) + "%)")
    print("  Uniform P=3:    " + String(throughput(n_p3, t_p3)) + " img/s  (" + String(throughput(n_p3, t_p3) / tput_source * 100.0) + "%)")
    print("  Uniform P=4:    " + String(throughput(n_p4, t_p4)) + " img/s  (" + String(throughput(n_p4, t_p4) / tput_source * 100.0) + "%)")
    print("  Uniform P=5:    " + String(throughput(n_p5, t_p5)) + " img/s  (" + String(throughput(n_p5, t_p5) / tput_source * 100.0) + "%)")
    print("  Uniform P=6:    " + String(throughput(n_p6, t_p6)) + " img/s  (" + String(throughput(n_p6, t_p6) / tput_source * 100.0) + "%)")
    print("  Uniform P=7:    " + String(throughput(n_p7, t_p7)) + " img/s  (" + String(throughput(n_p7, t_p7) / tput_source * 100.0) + "%)")
    print("  Optimal:        " + String(tput_opt) + " img/s  (" + String(tput_opt / tput_source * 100.0) + "%)")
    print("  Speedup vs seq: " + String(tput_opt / tput_seq) + "x")
    print("=" * 70)

    print("CSV_START")
    print("config,num_images,time_ms,throughput_img_s,efficiency_pct")
    print("source_baseline," + String(BASELINE_N) + "," + String(t_source) + "," + String(tput_source) + ",100.0")
    print("seq," + String(n_seq) + "," + String(t_seq) + "," + String(tput_seq) + "," + String(tput_seq / tput_source * 100.0))
    print("uniform_p2," + String(n_p2) + "," + String(t_p2) + "," + String(throughput(n_p2, t_p2)) + "," + String(throughput(n_p2, t_p2) / tput_source * 100.0))
    print("uniform_p3," + String(n_p3) + "," + String(t_p3) + "," + String(throughput(n_p3, t_p3)) + "," + String(throughput(n_p3, t_p3) / tput_source * 100.0))
    print("uniform_p4," + String(n_p4) + "," + String(t_p4) + "," + String(throughput(n_p4, t_p4)) + "," + String(throughput(n_p4, t_p4) / tput_source * 100.0))
    print("uniform_p5," + String(n_p5) + "," + String(t_p5) + "," + String(throughput(n_p5, t_p5)) + "," + String(throughput(n_p5, t_p5) / tput_source * 100.0))
    print("uniform_p6," + String(n_p6) + "," + String(t_p6) + "," + String(throughput(n_p6, t_p6)) + "," + String(throughput(n_p6, t_p6) / tput_source * 100.0))
    print("uniform_p7," + String(n_p7) + "," + String(t_p7) + "," + String(throughput(n_p7, t_p7)) + "," + String(throughput(n_p7, t_p7) / tput_source * 100.0))
    print("optimal_g3b8s8," + String(n_opt) + "," + String(t_opt) + "," + String(tput_opt) + "," + String(tput_opt / tput_source * 100.0))
    print("CSV_END")
