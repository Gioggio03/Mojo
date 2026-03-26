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

static BenchResult run_pipeline(int gray_p, int blur_p, int sharp_p) {
    auto* source = new ImageSource(W, H, NUM_IMAGES);
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

    // Warmup
    std::printf("\n[Warmup]...\n");
    run_source_baseline();
    std::printf("[Warmup] done.\n\n");

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

    // Phase 1: Sequential — Gray(1) Blur(1) Sharp(1)
    // ff_pipeline: 5 stages, 5 threads (no farms)
    auto res_seq = run_pipeline(1, 1, 1);
    double tput_seq = throughput(n, res_seq.time_ms);
    print_row("Gray(1) Blur(1) Sharp(1) [SEQ]", 5, res_seq.time_ms, tput_seq, tput_source);

    // Phase 2: Uniform sweep
    // Each farm adds 2 extra threads (emitter + collector)
    // Total for uniform P: source(1) + 3*(P+2) + sink(1) = 3P+8
    std::printf("  ------------------------------------------------------------------\n");

    struct Config {
        const char* label;
        int gray_p, blur_p, sharp_p;
        int total_threads;  // accounting: source + farms + sink
    };

    Config uniform_configs[] = {
        {"Gray(2) Blur(2) Sharp(2)      ", 2, 2, 2, 8},
        {"Gray(3) Blur(3) Sharp(3)      ", 3, 3, 3, 11},
        {"Gray(4) Blur(4) Sharp(4)      ", 4, 4, 4, 14},
        {"Gray(5) Blur(5) Sharp(5)      ", 5, 5, 5, 17},
        {"Gray(6) Blur(6) Sharp(6)      ", 6, 6, 6, 20},
        {"Gray(7) Blur(7) Sharp(7) [max]", 7, 7, 7, 23},
    };

    double tput_uniform[6];
    double time_uniform[6];
    for (int i = 0; i < 6; i++) {
        auto& c = uniform_configs[i];
        auto res = run_pipeline(c.gray_p, c.blur_p, c.sharp_p);
        tput_uniform[i] = throughput(n, res.time_ms);
        time_uniform[i] = res.time_ms;
        print_row(c.label, c.total_threads, res.time_ms, tput_uniform[i], tput_source);
    }

    // Phase 3: Smart configs — proportional to stage cost
    std::printf("  ------------------------------------------------------------------\n");

    Config smart_configs[] = {
        {"G1 B2  S1  [smart]            ", 1, 2, 1, 6},
        {"G1 B4  S2  [smart]            ", 1, 4, 2, 9},
        {"G2 B8  S4  [smart]            ", 2, 8, 4, 16},
        {"G2 B14 S6  [smart, max=24]    ", 2, 14, 6, 24},
    };

    double tput_smart[4];
    double time_smart[4];
    for (int i = 0; i < 4; i++) {
        auto& c = smart_configs[i];
        auto res = run_pipeline(c.gray_p, c.blur_p, c.sharp_p);
        tput_smart[i] = throughput(n, res.time_ms);
        time_smart[i] = res.time_ms;
        print_row(c.label, c.total_threads, res.time_ms, tput_smart[i], tput_source);
    }

    // Summary
    std::printf("\n======================================================================\n");
    std::printf("  SUMMARY\n");
    std::printf("  Source ceiling:   %.2f img/s  (target)\n", tput_source);
    std::printf("  Sequential:       %.2f img/s  (%.1f%%)\n", tput_seq, tput_seq / tput_source * 100.0);
    std::printf("  Best uniform P=7: %.2f img/s  (%.1f%%)  [23 threads]\n",
                tput_uniform[5], tput_uniform[5] / tput_source * 100.0);
    std::printf("  Best smart:       %.2f img/s  (%.1f%%)  [24 threads]\n",
                tput_smart[3], tput_smart[3] / tput_source * 100.0);
    std::printf("======================================================================\n");

    // CSV output (same format as Mojo for comparison)
    std::printf("\nCSV_START\n");
    std::printf("config,gray_p,blur_p,sharp_p,total_threads,time_ms,throughput,efficiency_pct\n");
    std::printf("source_baseline,0,0,0,3,%.6f,%.6f,100.0\n", res0.time_ms, tput_source);
    std::printf("seq,1,1,1,5,%.6f,%.6f,%.6f\n",
                res_seq.time_ms, tput_seq, tput_seq / tput_source * 100.0);

    const char* uniform_names[] = {
        "uniform_p2", "uniform_p3", "uniform_p4",
        "uniform_p5", "uniform_p6", "uniform_p7"
    };
    for (int i = 0; i < 6; i++) {
        auto& c = uniform_configs[i];
        std::printf("%s,%d,%d,%d,%d,%.6f,%.6f,%.6f\n",
                    uniform_names[i], c.gray_p, c.blur_p, c.sharp_p,
                    c.total_threads, time_uniform[i], tput_uniform[i],
                    tput_uniform[i] / tput_source * 100.0);
    }

    const char* smart_names[] = {
        "smart_g1_b2_s1", "smart_g1_b4_s2", "smart_g2_b8_s4", "smart_g2_b14_s6"
    };
    for (int i = 0; i < 4; i++) {
        auto& c = smart_configs[i];
        std::printf("%s,%d,%d,%d,%d,%.6f,%.6f,%.6f\n",
                    smart_names[i], c.gray_p, c.blur_p, c.sharp_p,
                    c.total_threads, time_smart[i], tput_smart[i],
                    tput_smart[i] / tput_source * 100.0);
    }
    std::printf("CSV_END\n");

    return 0;
}
