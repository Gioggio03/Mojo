// Test Spot Benchmark — FastFlow V4 (planar layout)
//
// Struttura speculare a image_processing_4/test_spot.mojo:
//   Phase 0: Source baseline  — Source -> PassThrough -> Sink
//   Phase 1: Sequential       — Gray(1) -> Blur(1) -> Sharp(1)
//   Phase 2: Uniform sweep    — P=2..7
//   Phase 3: Optimal config   — G=2 B=7 S=10 (placeholder, update after tuning)
//
// Stage V4: layout planar — inner loops stride-1, auto-vettorizzabili da GCC -O2.

#include <ff/ff.hpp>
#include <ff/pipeline.hpp>
#include <ff/farm.hpp>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <vector>
#include <functional>
#include "ppm_image.hpp"
#include "image_stages.hpp"

using namespace ff;

static constexpr double DURATION_S = 60.0;
static constexpr double BASELINE_S = 10.0;
static constexpr int    W          = 512;
static constexpr int    H          = 512;

static ff_node* make_stage(std::function<ff_node*()> factory, int p) {
    if (p == 1) return factory();
    auto* farm = new ff_farm();
    std::vector<ff_node*> ww;
    for (int i = 0; i < p; i++) ww.push_back(factory());
    farm->add_workers(ww);
    farm->add_collector(nullptr);
    return farm;
}

struct BenchResult { double time_ms; int images; };

static BenchResult run_pipeline(int gray_p, int blur_p, int sharp_p) {
    auto* sink = new ImageSink();
    ff_pipeline pipe;
    pipe.add_stage(new ImageSource(W, H, DURATION_S));
    pipe.add_stage(make_stage([]{ return (ff_node*)new GrayscaleWorker();    }, gray_p));
    pipe.add_stage(make_stage([]{ return (ff_node*)new GaussianBlurWorker(); }, blur_p));
    pipe.add_stage(make_stage([]{ return (ff_node*)new SharpenWorker();      }, sharp_p));
    pipe.add_stage(sink);

    auto t0 = std::chrono::high_resolution_clock::now();
    if (pipe.run_and_wait_end() < 0) {
        std::fprintf(stderr, "ERROR: pipeline failed\n");
        return {-1.0, 0};
    }
    double ms = std::chrono::duration<double, std::milli>(
        std::chrono::high_resolution_clock::now() - t0).count();
    return {ms, sink->get_count()};
}

static BenchResult run_source_baseline() {
    auto* sink = new ImageSink();
    ff_pipeline pipe;
    pipe.add_stage(new ImageSource(W, H, BASELINE_S));
    pipe.add_stage(new PassThroughWorker());
    pipe.add_stage(sink);
    auto t0 = std::chrono::high_resolution_clock::now();
    pipe.run_and_wait_end();
    double ms = std::chrono::duration<double, std::milli>(
        std::chrono::high_resolution_clock::now() - t0).count();
    return {ms, sink->get_count()};
}

static double throughput(int n, double ms) { return ms > 0 ? n / (ms/1000.0) : 0.0; }

static void print_row(const char* config, int threads, int n, double ms,
                      double tput, double src_tput) {
    std::printf("  %s | threads=%d | n=%d | %.6f ms | %.10f img/s | %.4f%%\n",
                config, threads, n, ms, tput, tput/src_tput*100.0);
    std::fflush(stdout);
}

int main() {
    std::printf("======================================================================\n");
    std::printf("  Test Spot Benchmark (FastFlow — V4 planar layout)\n");
    std::printf("  Image: %dx%d | Duration=%.0fs\n", W, H, DURATION_S);
    std::printf("  Pipeline: Source -> Gray -> Blur -> Sharp -> Sink\n");
    std::printf("======================================================================\n\n");
    std::fflush(stdout);

    std::printf("[Warmup]...\n"); std::fflush(stdout);
    run_source_baseline();
    std::printf("[Warmup] done.\n\n"); std::fflush(stdout);

    std::printf("PHASE 0: Source baseline\n");
    auto res0 = run_source_baseline();
    double tput_source = throughput(res0.images, res0.time_ms);
    std::printf("  Throughput: %.10f img/s  <-- TARGET\n\n", tput_source);
    std::fflush(stdout);

    std::printf("  Config              | Threads | N images | Time (ms)  | Tput (img/s) | vs Source\n");
    std::printf("  ------------------------------------------------------------------\n");

    std::printf("  [Running] SEQ G1 B1 S1...\n"); std::fflush(stdout);
    auto res_seq = run_pipeline(1, 1, 1);
    double tput_seq = throughput(res_seq.images, res_seq.time_ms);
    print_row("SEQ  G1  B1  S1 ", 5, res_seq.images, res_seq.time_ms, tput_seq, tput_source);

    BenchResult res_p[8] = {};
    for (int p = 2; p <= 7; p++) {
        std::printf("  [Running] Uniform P=%d...\n", p); std::fflush(stdout);
        res_p[p] = run_pipeline(p, p, p);
        char label[32]; std::snprintf(label, sizeof(label), "Uniform P=%d     ", p);
        print_row(label, p*3+2, res_p[p].images, res_p[p].time_ms,
                  throughput(res_p[p].images, res_p[p].time_ms), tput_source);
    }

    // Optimal — placeholder G=2 B=7 S=10, update after tuning
    std::printf("  [Running] OPT G2 B7 S10...\n"); std::fflush(stdout);
    auto res_opt = run_pipeline(2, 7, 10);
    double tput_opt = throughput(res_opt.images, res_opt.time_ms);
    print_row("OPT  G2  B7  S10", 21, res_opt.images, res_opt.time_ms, tput_opt, tput_source);

    std::printf("\n======================================================================\n");
    std::printf("  SUMMARY\n");
    std::printf("  Source ceiling: %.2f img/s\n", tput_source);
    std::printf("  Sequential:     %.2f img/s  (%.2f%%)\n", tput_seq, tput_seq/tput_source*100.0);
    for (int p = 2; p <= 7; p++) {
        double t = throughput(res_p[p].images, res_p[p].time_ms);
        std::printf("  Uniform P=%d:    %.2f img/s  (%.2f%%)\n", p, t, t/tput_source*100.0);
    }
    std::printf("  Optimal G2B7S10:%.2f img/s  (%.2f%%)\n", tput_opt, tput_opt/tput_source*100.0);
    std::printf("  Speedup vs seq: %.2fx\n", tput_opt/tput_seq);
    std::printf("======================================================================\n");

    std::printf("CSV_START\n");
    std::printf("config,num_images,time_ms,throughput_img_s,efficiency_pct\n");
    std::printf("source_baseline,%d,%.6f,%.10f,100.0\n", res0.images, res0.time_ms, tput_source);
    std::printf("seq,%d,%.6f,%.10f,%.6f\n", res_seq.images, res_seq.time_ms, tput_seq, tput_seq/tput_source*100.0);
    for (int p = 2; p <= 7; p++) {
        double t = throughput(res_p[p].images, res_p[p].time_ms);
        std::printf("uniform_p%d,%d,%.6f,%.10f,%.6f\n", p, res_p[p].images, res_p[p].time_ms, t, t/tput_source*100.0);
    }
    std::printf("optimal_g2b7s10,%d,%.6f,%.10f,%.6f\n", res_opt.images, res_opt.time_ms, tput_opt, tput_opt/tput_source*100.0);
    std::printf("CSV_END\n");

    return 0;
}
