# Test baseline speed with Mojo

from MoStream import Pipeline, seq, parallel
from image_stages import ImageSource, Grayscale, GaussianBlur, Sharpen, PassThrough, ImageSink
from time import perf_counter_ns

comptime NUM_IMAGES: Int = 10000
comptime W: Int = 512
comptime H: Int = 512

# ============================================================================
# Helpers
# ============================================================================

fn elapsed_ms(t0: UInt) -> Float64:
    return Float64(Int(perf_counter_ns() - t0)) / 1_000_000.0

fn throughput(n: Int, ms: Float64) -> Float64:
    if ms <= 0.0:
        return 0.0
    return Float64(n) / (ms / 1000.0)

fn print_row(config: String, threads: Int, ms: Float64, tput: Float64, source_tput: Float64):
    var eff = tput / source_tput * 100.0
    print("  " + config + " | threads=" + String(threads) + " | " + String(ms) + " ms | " + String(tput) + " img/s | " + String(eff) + "%")

# ============================================================================
# Phase 0: Source baseline (target throughput)
# Source(1) -> PassThrough(1) -> Sink(1)
# Total threads: 2
# ============================================================================

fn run_source_baseline() raises -> Float64:
    var source = ImageSource[W, H, NUM_IMAGES]()
    var pt = PassThrough()
    var sink = ImageSink()
    var pipeline = Pipeline((seq(source), seq(pt), seq(sink)))
    pipeline.setPinning(True)
    var t0 = perf_counter_ns()
    pipeline.run()
    var ms = elapsed_ms(t0)
    _ = pipeline
    return ms

# ============================================================================
# Main
# ============================================================================
def main():
    var n = NUM_IMAGES
    print("=" * 70)
    print("  Source-Rate Benchmark")
    print("  Image: " + String(W) + "x" + String(H) + " | N=" + String(n))
    print("  Pipeline: Source -> Gray -> Blur -> Sharp -> Sink")
    print("  Hardware budget: 24 physical cores")
    print("  Thread budget: 22 transform threads (24 - src - sink)")
    print("  Goal: approach Source throughput by tuning parallelism")
    print("=" * 70)

    # ----------------------------------------------------------------
    # Phase 0: Source baseline
    # ----------------------------------------------------------------
    print("PHASE 0: Source baseline (theoretical ceiling)")
    print("  Config: Source(1) -> PassThrough(1) -> Sink(1)  [3 total threads]")
    print("  " + "-" * 66)
    var t_source = run_source_baseline()
    var tput_source = throughput(n, t_source)
    print("  Time: " + String(t_source) + " ms | Throughput: " + String(tput_source) + " img/s  <-- TARGET")
    print("\n  " + "=" * 66)
    print("  Config                    | Threads | Time (ms)  | Tput (img/s) | vs Source")
    print("  " + "-" * 66)
