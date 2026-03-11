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

    # Calculations
    var r_num = Float64(NUM_IMAGES)
    var s_ms = 1000.0
    
    # Throughputs (img/s)
    var seq3_tput = r_num / (seq3_ms / s_ms)
    var seq4_tput = r_num / (seq4_ms / s_ms)
    var seq5_tput = r_num / (seq5_ms / s_ms)
    var seq6_tput = r_num / (seq6_ms / s_ms)
    
    var par2_3_tput = r_num / (par2_3_ms / s_ms)
    var par2_4_tput = r_num / (par2_4_ms / s_ms)
    var par2_5_tput = r_num / (par2_5_ms / s_ms)
    var par2_6_tput = r_num / (par2_6_ms / s_ms)

    var par4_3_tput = r_num / (par4_3_ms / s_ms)
    var par4_4_tput = r_num / (par4_4_ms / s_ms)
    var par4_5_tput = r_num / (par4_5_ms / s_ms)
    var par4_6_tput = r_num / (par4_6_ms / s_ms)

    # Scalability (vs 3 stages SEQ)
    var seq3_scal = seq3_ms / seq3_ms
    var seq4_scal = seq3_ms / seq4_ms
    var seq5_scal = seq3_ms / seq5_ms
    var seq6_scal = seq3_ms / seq6_ms

    # Speedups
    var s2_3 = seq3_ms / par2_3_ms; var s4_3 = seq3_ms / par4_3_ms
    var s2_4 = seq4_ms / par2_4_ms; var s4_4 = seq4_ms / par4_4_ms
    var s2_5 = seq5_ms / par2_5_ms; var s4_5 = seq5_ms / par4_5_ms
    var s2_6 = seq6_ms / par2_6_ms; var s4_6 = seq6_ms / par4_6_ms

    # Efficiency (Speedup / P)
    var e2_3 = s2_3 / 2.0; var e4_3 = s4_3 / 4.0
    var e2_4 = s2_4 / 2.0; var e4_4 = s4_4 / 4.0
    var e2_5 = s2_5 / 2.0; var e4_5 = s4_5 / 4.0
    var e2_6 = s2_6 / 2.0; var e4_6 = s4_6 / 4.0

    # Summary tables
    print("\n  --- Summary (Sequential P=1) ---")
    print("  Stages | Time (ms)      | Throughput (img/s) | Scalability (vs 3 stg)")
    print("  -------|----------------|--------------------|-----------------------")
    print("  3      | " + String(seq3_ms) + " | " + String(seq3_tput) + " | " + String(seq3_scal))
    print("  4      | " + String(seq4_ms) + " | " + String(seq4_tput) + " | " + String(seq4_scal))
    print("  5      | " + String(seq5_ms) + " | " + String(seq5_tput) + " | " + String(seq5_scal))
    print("  6      | " + String(seq6_ms) + " | " + String(seq6_tput) + " | " + String(seq6_scal))

    print("\n  --- Summary (Parallel Performance vs Sequential Baseline) ---")
    print("  Stages | P=2 T(ms)      | P=2 (img/s) | P=2 Sp. | P=2 Eff. | P=4 T(ms)      | P=4 (img/s) | P=4 Sp. | P=4 Eff.")
    print("  -------|----------------|-------------|---------|----------|----------------|-------------|---------|---------")
    print("  3      | " + String(par2_3_ms) + " | " + String(par2_3_tput) + " | " + String(s2_3) + " | " + String(e2_3) + " | " + String(par4_3_ms) + " | " + String(par4_3_tput) + " | " + String(s4_3) + " | " + String(e4_3))
    print("  4      | " + String(par2_4_ms) + " | " + String(par2_4_tput) + " | " + String(s2_4) + " | " + String(e2_4) + " | " + String(par4_4_ms) + " | " + String(par4_4_tput) + " | " + String(s4_4) + " | " + String(e4_4))
    print("  5      | " + String(par2_5_ms) + " | " + String(par2_5_tput) + " | " + String(s2_5) + " | " + String(e2_5) + " | " + String(par4_5_ms) + " | " + String(par4_5_tput) + " | " + String(s4_5) + " | " + String(e4_5))
    print("  6      | " + String(par2_6_ms) + " | " + String(par2_6_tput) + " | " + String(s2_6) + " | " + String(e2_6) + " | " + String(par4_6_ms) + " | " + String(par4_6_tput) + " | " + String(s4_6) + " | " + String(e4_6))


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

    # Warmup run to initialize Mojo runtime and thread pools
    print("\n[Warmup] Initializing runtime...")
    try:
        run_seq_3[64, 64]()
    except:
        pass
    print("[Warmup] Complete.\n")

    # Run benchmarks for different image sizes
    bench_image_size[64, 64]()
    bench_image_size[128, 128]()
    bench_image_size[256, 256]()
    bench_image_size[512, 512]()
    bench_image_size[1024, 1024]()

    print("\n" + "=" * 70)
    print("  Benchmark complete!")
    print("=" * 70)

