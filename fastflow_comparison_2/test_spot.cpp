// Test Spot — FastFlow V2 stages, configurazione singola da linea di comando
//
// Uso:
//   ./test_spot <G> <B> <S>
//
// Esempio:
//   ./test_spot 2 7 10
//
// Esegue una sola pipeline per 60 secondi con G worker per Grayscale,
// B worker per GaussianBlur, S worker per Sharpen, e stampa il throughput.
//
// Per il benchmark completo (sweep P=2..7 + configurazione ottimale)
// usare benchmark_full.

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
    pipe.add_stage(make_stage([]{ return (ff_node*)new GrayscaleWorker();   }, gray_p));
    pipe.add_stage(make_stage([]{ return (ff_node*)new GaussianBlurWorker();}, blur_p));
    pipe.add_stage(make_stage([]{ return (ff_node*)new SharpenWorker();     }, sharp_p));
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

int main(int argc, char* argv[]) {
    if (argc != 4) {
        std::fprintf(stderr, "Uso: %s <G> <B> <S>\n", argv[0]);
        std::fprintf(stderr, "  G = parallelismo Grayscale\n");
        std::fprintf(stderr, "  B = parallelismo GaussianBlur\n");
        std::fprintf(stderr, "  S = parallelismo Sharpen\n");
        std::fprintf(stderr, "Esempio: %s 2 7 10\n", argv[0]);
        return 1;
    }

    int g = std::atoi(argv[1]);
    int b = std::atoi(argv[2]);
    int s = std::atoi(argv[3]);
    int threads = g + b + s + 2;

    if (g < 1 || b < 1 || s < 1) {
        std::fprintf(stderr, "Errore: G, B, S devono essere >= 1\n");
        return 1;
    }

    std::printf("======================================================================\n");
    std::printf("  Test Spot (FastFlow V2) — configurazione singola\n");
    std::printf("  Image: %dx%d | Duration=%.0fs\n", W, H, DURATION_S);
    std::printf("  Config: G=%d B=%d S=%d | threads=%d\n", g, b, s, threads);
    std::printf("======================================================================\n\n");
    std::fflush(stdout);

    std::printf("[Warmup]...\n"); std::fflush(stdout);
    run_source_baseline();
    std::printf("[Warmup] done.\n\n"); std::fflush(stdout);

    auto res0 = run_source_baseline();
    double tput_source = throughput(res0.images, res0.time_ms);
    std::printf("Source baseline: %.2f img/s\n\n", tput_source);
    std::fflush(stdout);

    std::printf("[Running] G=%d B=%d S=%d...\n", g, b, s); std::fflush(stdout);
    auto res = run_pipeline(g, b, s);
    double tput = throughput(res.images, res.time_ms);
    double eff  = tput / tput_source * 100.0;

    std::printf("\nRisultato:\n");
    std::printf("  Config  : G=%d B=%d S=%d\n", g, b, s);
    std::printf("  Threads : %d\n", threads);
    std::printf("  N images: %d\n", res.images);
    std::printf("  Time    : %.6f ms\n", res.time_ms);
    std::printf("  Tput    : %.4f img/s\n", tput);
    std::printf("  vs Src  : %.4f%%\n", eff);
    std::printf("======================================================================\n");

    std::printf("CSV_START\n");
    std::printf("config,num_images,time_ms,throughput_img_s,efficiency_pct\n");
    std::printf("source_baseline,%d,%.6f,%.10f,100.0\n", res0.images, res0.time_ms, tput_source);
    std::printf("g%db%ds%d,%d,%.6f,%.10f,%.6f\n", g, b, s, res.images, res.time_ms, tput, eff);
    std::printf("CSV_END\n");

    return 0;
}
