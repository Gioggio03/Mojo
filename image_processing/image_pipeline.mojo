# Image Processing Pipeline Benchmark
# Runs the image processing pipeline with different configurations:
#   - Image sizes: 64x64, 128x128, 256x256, 512x512, 1024x1024
#   - Pipeline depths: 3, 4, 5, 6 stages
#   - Parallelism: SEQ (all seq) vs PAR(P=2) vs PAR(P=4) on intermediate stages
# Source and Sink always remain seq(); only TRANSFORM stages are parallelized.
# Measures throughput, speedup, and scalability.

from MoStream import Pipeline, seq, parallel
from image_stages import ImageSource, Grayscale, GaussianBlur, Sharpen, Brightness, ImageSink
from time import perf_counter_ns

# Number of images to process per run
comptime NUM_IMAGES: Int = 200

# ============================================================================
# SEQUENTIAL pipeline (1 replica per stage) — baseline
# All stages use seq() = 1 thread each
# ============================================================================

# 3 stages: Source -> Grayscale -> Sink
fn run_seq_3[W: Int, H: Int]() raises:
    var source = ImageSource[W, H, NUM_IMAGES]()
    var gray = Grayscale()
    var sink = ImageSink()
    var pipeline = Pipeline((seq(source), seq(gray), seq(sink)))
    pipeline.setPinning(True)
    pipeline.run()
    _ = pipeline

# 4 stages: Source -> Grayscale -> Blur -> Sink
fn run_seq_4[W: Int, H: Int]() raises:
    var source = ImageSource[W, H, NUM_IMAGES]()
    var gray = Grayscale()
    var blur = GaussianBlur()
    var sink = ImageSink()
    var pipeline = Pipeline((seq(source), seq(gray), seq(blur), seq(sink)))
    pipeline.setPinning(True)
    pipeline.run()
    _ = pipeline

# 5 stages: Source -> Grayscale -> Blur -> Sharpen -> Sink
fn run_seq_5[W: Int, H: Int]() raises:
    var source = ImageSource[W, H, NUM_IMAGES]()
    var gray = Grayscale()
    var blur = GaussianBlur()
    var sharp = Sharpen()
    var sink = ImageSink()
    var pipeline = Pipeline((seq(source), seq(gray), seq(blur), seq(sharp), seq(sink)))
    pipeline.setPinning(True)
    pipeline.run()
    _ = pipeline

# 6 stages: Source -> Grayscale -> Blur -> Sharpen -> Brightness -> Sink
fn run_seq_6[W: Int, H: Int]() raises:
    var source = ImageSource[W, H, NUM_IMAGES]()
    var gray = Grayscale()
    var blur = GaussianBlur()
    var sharp = Sharpen()
    var bright = Brightness[20]()
    var sink = ImageSink()
    var pipeline = Pipeline((seq(source), seq(gray), seq(blur), seq(sharp), seq(bright), seq(sink)))
    pipeline.setPinning(True)
    pipeline.run()
    _ = pipeline

# ============================================================================
# PARALLEL pipeline — intermediate TRANSFORM stages use parallel(stage, P)
# Source and Sink remain seq()
# ============================================================================

# 3 stages: Source -> parallel(Grayscale, P) -> Sink
fn run_par_3[W: Int, H: Int, P: Int]() raises:
    var source = ImageSource[W, H, NUM_IMAGES]()
    var gray = Grayscale()
    var sink = ImageSink()
    var pipeline = Pipeline((seq(source), parallel(gray, P), seq(sink)))
    pipeline.setPinning(True)
    pipeline.run()
    _ = pipeline

# 4 stages: Source -> parallel(Grayscale, P) -> parallel(Blur, P) -> Sink
fn run_par_4[W: Int, H: Int, P: Int]() raises:
    var source = ImageSource[W, H, NUM_IMAGES]()
    var gray = Grayscale()
    var blur = GaussianBlur()
    var sink = ImageSink()
    var pipeline = Pipeline((seq(source), parallel(gray, P), parallel(blur, P), seq(sink)))
    pipeline.setPinning(True)
    pipeline.run()
    _ = pipeline

# 5 stages: Source -> parallel(Grayscale, P) -> parallel(Blur, P) -> parallel(Sharpen, P) -> Sink
fn run_par_5[W: Int, H: Int, P: Int]() raises:
    var source = ImageSource[W, H, NUM_IMAGES]()
    var gray = Grayscale()
    var blur = GaussianBlur()
    var sharp = Sharpen()
    var sink = ImageSink()
    var pipeline = Pipeline((seq(source), parallel(gray, P), parallel(blur, P), parallel(sharp, P), seq(sink)))
    pipeline.setPinning(True)
    pipeline.run()
    _ = pipeline

# 6 stages: Source -> parallel(Gray, P) -> parallel(Blur, P) -> parallel(Sharp, P) -> parallel(Bright, P) -> Sink
fn run_par_6[W: Int, H: Int, P: Int]() raises:
    var source = ImageSource[W, H, NUM_IMAGES]()
    var gray = Grayscale()
    var blur = GaussianBlur()
    var sharp = Sharpen()
    var bright = Brightness[20]()
    var sink = ImageSink()
    var pipeline = Pipeline((seq(source), parallel(gray, P), parallel(blur, P), parallel(sharp, P), parallel(bright, P), seq(sink)))
    pipeline.setPinning(True)
    pipeline.run()
    _ = pipeline

# ============================================================================
# Benchmark runner for a given image size
# ============================================================================

fn bench_image_size[W: Int, H: Int]() raises:
    print("\n" + "=" * 70)
    print("  Image Size: " + String(W) + "x" + String(H) + " (" + String(W * H * 3) + " bytes)")
    print("  Messages per run: " + String(NUM_IMAGES))
    print("=" * 70)

    # ---- Sequential pipeline (1 replica per stage) ----
    print("\n  --- SEQ: all stages with 1 replica ---")

    print("\n  [SEQ] 3 stages (Source->Gray->Sink):")
    var t0 = perf_counter_ns()
    run_seq_3[W, H]()
    var seq3_ms = Float64(Int(perf_counter_ns() - t0)) / 1_000_000.0
    print("    Total: " + String(seq3_ms) + " ms")

    print("\n  [SEQ] 4 stages (Source->Gray->Blur->Sink):")
    t0 = perf_counter_ns()
    run_seq_4[W, H]()
    var seq4_ms = Float64(Int(perf_counter_ns() - t0)) / 1_000_000.0
    print("    Total: " + String(seq4_ms) + " ms")

    print("\n  [SEQ] 5 stages (Source->Gray->Blur->Sharp->Sink):")
    t0 = perf_counter_ns()
    run_seq_5[W, H]()
    var seq5_ms = Float64(Int(perf_counter_ns() - t0)) / 1_000_000.0
    print("    Total: " + String(seq5_ms) + " ms")

    print("\n  [SEQ] 6 stages (Source->Gray->Blur->Sharp->Bright->Sink):")
    t0 = perf_counter_ns()
    run_seq_6[W, H]()
    var seq6_ms = Float64(Int(perf_counter_ns() - t0)) / 1_000_000.0
    print("    Total: " + String(seq6_ms) + " ms")

    # ---- Parallel pipeline P=2 ----
    print("\n  --- PAR(P=2): intermediate stages with 2 replicas ---")

    print("\n  [PAR P=2] 3 stages (Source->Gray(2)->Sink):")
    t0 = perf_counter_ns()
    run_par_3[W, H, 2]()
    var par2_3_ms = Float64(Int(perf_counter_ns() - t0)) / 1_000_000.0
    print("    Total: " + String(par2_3_ms) + " ms")

    print("\n  [PAR P=2] 4 stages (Source->Gray(2)->Blur(2)->Sink):")
    t0 = perf_counter_ns()
    run_par_4[W, H, 2]()
    var par2_4_ms = Float64(Int(perf_counter_ns() - t0)) / 1_000_000.0
    print("    Total: " + String(par2_4_ms) + " ms")

    print("\n  [PAR P=2] 5 stages (Source->Gray(2)->Blur(2)->Sharp(2)->Sink):")
    t0 = perf_counter_ns()
    run_par_5[W, H, 2]()
    var par2_5_ms = Float64(Int(perf_counter_ns() - t0)) / 1_000_000.0
    print("    Total: " + String(par2_5_ms) + " ms")

    print("\n  [PAR P=2] 6 stages (Source->Gray(2)->Blur(2)->Sharp(2)->Bright(2)->Sink):")
    t0 = perf_counter_ns()
    run_par_6[W, H, 2]()
    var par2_6_ms = Float64(Int(perf_counter_ns() - t0)) / 1_000_000.0
    print("    Total: " + String(par2_6_ms) + " ms")

    # ---- Parallel pipeline P=4 ----
    print("\n  --- PAR(P=4): intermediate stages with 4 replicas ---")

    print("\n  [PAR P=4] 3 stages (Source->Gray(4)->Sink):")
    t0 = perf_counter_ns()
    run_par_3[W, H, 4]()
    var par4_3_ms = Float64(Int(perf_counter_ns() - t0)) / 1_000_000.0
    print("    Total: " + String(par4_3_ms) + " ms")

    print("\n  [PAR P=4] 4 stages (Source->Gray(4)->Blur(4)->Sink):")
    t0 = perf_counter_ns()
    run_par_4[W, H, 4]()
    var par4_4_ms = Float64(Int(perf_counter_ns() - t0)) / 1_000_000.0
    print("    Total: " + String(par4_4_ms) + " ms")

    print("\n  [PAR P=4] 5 stages (Source->Gray(4)->Blur(4)->Sharp(4)->Sink):")
    t0 = perf_counter_ns()
    run_par_5[W, H, 4]()
    var par4_5_ms = Float64(Int(perf_counter_ns() - t0)) / 1_000_000.0
    print("    Total: " + String(par4_5_ms) + " ms")

    print("\n  [PAR P=4] 6 stages (Source->Gray(4)->Blur(4)->Sharp(4)->Bright(4)->Sink):")
    t0 = perf_counter_ns()
    run_par_6[W, H, 4]()
    var par4_6_ms = Float64(Int(perf_counter_ns() - t0)) / 1_000_000.0
    print("    Total: " + String(par4_6_ms) + " ms")

    # Summary table
    print("\n  --- Summary ---")
    print("  Stages | SEQ (ms)       | PAR P=2 (ms)   | Speedup(2) | PAR P=4 (ms)   | Speedup(4)")
    print("  -------|----------------|----------------|------------|----------------|----------")
    print("  3      | " + String(seq3_ms) + " | " + String(par2_3_ms) + " | " + String(seq3_ms / par2_3_ms) + " | " + String(par4_3_ms) + " | " + String(seq3_ms / par4_3_ms))
    print("  4      | " + String(seq4_ms) + " | " + String(par2_4_ms) + " | " + String(seq4_ms / par2_4_ms) + " | " + String(par4_4_ms) + " | " + String(seq4_ms / par4_4_ms))
    print("  5      | " + String(seq5_ms) + " | " + String(par2_5_ms) + " | " + String(seq5_ms / par2_5_ms) + " | " + String(par4_5_ms) + " | " + String(seq5_ms / par4_5_ms))
    print("  6      | " + String(seq6_ms) + " | " + String(par2_6_ms) + " | " + String(seq6_ms / par2_6_ms) + " | " + String(par4_6_ms) + " | " + String(seq6_ms / par4_6_ms))


# ============================================================================
# Main
# ============================================================================
def main():
    print("=" * 70)
    print("  Image Processing Pipeline Benchmark [SEQ vs PAR]")
    print("  Pipeline: Source -> Grayscale -> Blur -> Sharpen -> Brightness -> Sink")
    print("  Images per run: " + String(NUM_IMAGES))
    print("  Queue: MPMC_padding_optional_v2")
    print("  Parallelism tested: SEQ, PAR(P=2), PAR(P=4)")
    print("=" * 70)

    # Run benchmarks for different image sizes
    bench_image_size[64, 64]()
    bench_image_size[128, 128]()
    bench_image_size[256, 256]()
    bench_image_size[512, 512]()
    bench_image_size[1024, 1024]()

    print("\n" + "=" * 70)
    print("  Benchmark complete!")
    print("=" * 70)

