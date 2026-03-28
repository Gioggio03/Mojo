// Source-Rate Benchmark — FastFlow version
// 
// Direct equivalent of the Mojo source_rate_benchmark.
// Uses ff_pipeline for stage chaining and ff_farm for parallel stages.
// 
// Pipeline: Source -> Grayscale -> GaussianBlur -> Sharpen -> Sink
// 
// Phases:
//   0: Source baseline — Source -> PassThrough -> Sink
//   1: Sequential      — Source -> Gray(1) -> Blur(1) -> Sharp(1) -> Sink
//   2: Uniform sweep   — P=2..7 (all transforms at same P)
//   3: Smart configs   — parallelism proportional to stage cost

#include <ff/ff.hpp>
#include <ff/pipeline.hpp>
#include <ff/farm.hpp>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>
#include <functional>
#include "ppm_image.hpp"
#include "image_stages.hpp"

using namespace ff;

static constexpr double DURATION_S = 60.0;
static constexpr int W = 512;
static constexpr int H = 512;

// ============================================================================
// Pipeline builder
// ============================================================================

// Create an ff_farm with P workers from a factory function.
// The farm includes a default collector for pipeline composition.
static ff_farm* make_farm(std::function<ff_node*()> factory, int nworkers) {
    auto* farm = new ff_farm();
    std::vector<ff_node*> workers;
    for (int i = 0; i < nworkers; i++) {
        workers.push_back(factory());
    }
    farm->add_workers(workers);
    farm->add_collector(nullptr);  // default collector
    return farm;
}

// Build and run a pipeline with the given parallelism per transform stage.
// Returns elapsed time in milliseconds (outer wall-clock).
struct BenchResult {
    double time_ms;
    int    images;
};

static BenchResult run_pipeline(int gray_p, int blur_p, int sharp_p) {
    auto* source = new ImageSource(W, H, DURATION_S);
    auto* sink   = new ImageSink();

    ff_pipeline pipe;
    pipe.add_stage(source);

    // Grayscale stage
    if (gray_p == 1) {
        pipe.add_stage(new GrayscaleWorker());
    } else {
        pipe.add_stage(make_farm([]{ return new GrayscaleWorker(); }, gray_p));
    }

    // GaussianBlur stage
    if (blur_p == 1) {
        pipe.add_stage(new GaussianBlurWorker());
    } else {
        pipe.add_stage(make_farm([]{ return new GaussianBlurWorker(); }, blur_p));
    }

    // Sharpen stage
    if (sharp_p == 1) {
        pipe.add_stage(new SharpenWorker());
    } else {
        pipe.add_stage(make_farm([]{ return new SharpenWorker(); }, sharp_p));
    }

    pipe.add_stage(sink);

    auto t0 = std::chrono::high_resolution_clock::now();
    if (pipe.run_and_wait_end() < 0) {
        std::fprintf(stderr, "ERROR: pipeline execution failed\n");
        return {-1.0, 0};
    }
    auto t1 = std::chrono::high_resolution_clock::now();

    double ms = std::chrono::duration<double, std::milli>(t1 - t0).count();
    int images = sink->get_count();

    return {ms, images};
}

// Source baseline: Source -> PassThrough -> Sink (no farms)
static BenchResult run_source_baseline() {
    auto* source = new ImageSource(W, H, 10.0);
    auto* pt     = new PassThroughWorker();
    auto* sink   = new ImageSink();

    ff_pipeline pipe;
    pipe.add_stage(source);
    pipe.add_stage(pt);
    pipe.add_stage(sink);

    auto t0 = std::chrono::high_resolution_clock::now();
    if (pipe.run_and_wait_end() < 0) {
        std::fprintf(stderr, "ERROR: source baseline failed\n");
        return {-1.0, 0};
    }
    auto t1 = std::chrono::high_resolution_clock::now();

    double ms = std::chrono::duration<double, std::milli>(t1 - t0).count();
    return {ms, sink->get_count()};
}

// ============================================================================
// Helpers
// ============================================================================

static double throughput(int n, double ms) {
    return (ms > 0) ? n / (ms / 1000.0) : 0.0;
}

static void print_row(const char* config, int threads, int n, double ms, double tput, double source_tput) {
    double eff = tput / source_tput * 100.0;
    std::printf("  %s | threads=%d | n=%d | %.2f ms | %.2f img/s | %.1f%%\n",
                config, threads, n, ms, tput, eff);
}

// ============================================================================
// Main
// ============================================================================

int main() {
    std::printf("\n======================================================================\n");
    std::printf("  Source-Rate Benchmark (FastFlow Time-Based)\n");
    std::printf("  Image: %dx%d | Duration=%.0fs\n", W, H, DURATION_S);
    std::printf("  Pipeline: Source -> Gray -> Blur -> Sharp -> Sink\n");
    std::printf("  Note: each ff_farm adds emitter+collector threads\n");
    std::printf("  Goal: approach Source throughput by tuning parallelism\n");
    std::printf("======================================================================\n");
    std::fflush(stdout);

    // Warmup
    std::printf("\n[Warmup]...\n");
    run_source_baseline();
    std::printf("[Warmup] done.\n\n");

    // Phase 0: Source baseline
    std::printf("PHASE 0: Source baseline (theoretical ceiling)\n");
    std::printf("  Config: Source(1) -> PassThrough(1) -> Sink(1)  [3 threads]\n");
    std::printf("  ------------------------------------------------------------------\n");
    auto res0 = run_source_baseline();
    double tput_source = throughput(res0.images, res0.time_ms);
    std::printf("  Time: %.2f ms | Throughput: %.2f img/s  <-- TARGET\n",
                res0.time_ms, tput_source);

    std::printf("\n  ==================================================================\n");
    std::printf("  Config                    | Threads | N images | Time (ms)  | Tput (img/s) | vs Source\n");
    std::printf("  ------------------------------------------------------------------\n");

    // Phase 1: Sequential — Gray(1) Blur(1) Sharp(1)
    // ff_pipeline: 5 stages, 5 threads (no farms)
    std::printf("  [Running] Gray(1) Blur(1) Sharp(1) [SEQ]...\n"); std::fflush(stdout);
    auto res_seq = run_pipeline(1, 1, 1);
    double tput_seq = throughput(res_seq.images, res_seq.time_ms);
    print_row("Gray(1) Blur(1) Sharp(1) [SEQ]", 5, res_seq.images, res_seq.time_ms, tput_seq, tput_source);
    std::fflush(stdout);

    // Summary
    std::printf("\n======================================================================\n");
    std::printf("  SUMMARY\n");
    std::printf("  Source ceiling:   %.2f img/s  (target)\n", tput_source);
    std::printf("  Sequential:       %.2f img/s  (%.1f%%)  [%d images]\n", tput_seq, tput_seq / tput_source * 100.0, res_seq.images);
   
    std::printf("CSV_END\n");

    return 0;
}
