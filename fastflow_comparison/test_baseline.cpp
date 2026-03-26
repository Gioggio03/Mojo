// Test baseline speed with FastFlow

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

static constexpr int NUM_IMAGES = 1000;
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

// Source baseline: Source -> PassThrough -> Sink (no farms)
static BenchResult run_source_baseline() {
    auto* source = new ImageSource(W, H, NUM_IMAGES);
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

static void print_row(const char* config, int threads, double ms, double tput, double source_tput) {
    double eff = tput / source_tput * 100.0;
    std::printf("  %s | threads=%d | %.2f ms | %.2f img/s | %.1f%%\n",
                config, threads, ms, tput, eff);
}

// ============================================================================
// Main
// ============================================================================
int main() {
    int n = NUM_IMAGES;
    std::printf("======================================================================\n");
    std::printf("  Source-Rate Benchmark (FastFlow)\n");
    std::printf("  Image: %dx%d | N=%d\n", W, H, n);
    std::printf("  Pipeline: Source -> Gray -> Blur -> Sharp -> Sink\n");
    std::printf("  Note: each ff_farm adds emitter+collector threads\n");
    std::printf("  Goal: approach Source throughput by tuning parallelism\n");
    std::printf("======================================================================\n");

    // Phase 0: Source baseline
    std::printf("PHASE 0: Source baseline (theoretical ceiling)\n");
    std::printf("  Config: Source(1) -> PassThrough(1) -> Sink(1)  [3 threads]\n");
    std::printf("  ------------------------------------------------------------------\n");
    auto res0 = run_source_baseline();
    double tput_source = throughput(n, res0.time_ms);
    std::printf("  Time: %.2f ms | Throughput: %.2f img/s  <-- TARGET\n",
                res0.time_ms, tput_source);

    std::printf("\n  ==================================================================\n");
    std::printf("  Config                    | Threads | Time (ms)  | Tput (img/s) | vs Source\n");
    std::printf("  ------------------------------------------------------------------\n");
    std::printf("CSV_END\n");

    return 0;
}
