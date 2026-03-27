// FastFlow node definitions for the image processing pipeline.
// Each stage is a direct equivalent of the corresponding Mojo stage,
// implemented as an ff_node_t<PPMImage> for use in ff_pipeline / ff_farm.

#ifndef IMAGE_STAGES_HPP
#define IMAGE_STAGES_HPP

#include <ff/ff.hpp>
#include <ff/pipeline.hpp>
#include <ff/farm.hpp>
#include <chrono>
#include <cstdio>
#include <cstdint>
#include <algorithm>
#include "ppm_image.hpp"

using namespace ff;

// ============================================================================
// ImageSource — first pipeline stage (generates images)
// Produces NUM_IMAGES copies of a synthetic gradient image.
// ============================================================================

struct ImageSource : ff_node_t<PPMImage> {
    int img_w, img_h;
    int count;
    double duration_s;
    std::chrono::time_point<std::chrono::high_resolution_clock> start_time;
    PPMImage pool;

    ImageSource(int w, int h, double duration = 60.0)
        : img_w(w), img_h(h), count(0), duration_s(duration),
          pool(PPMImage::create_gradient(w, h)) {}

    int svc_init() override {
        start_time = std::chrono::high_resolution_clock::now();
        return 0;
    }

    PPMImage* svc(PPMImage*) override {
        auto now = std::chrono::high_resolution_clock::now();
        std::chrono::duration<double> elapsed = now - start_time;
        if (elapsed.count() >= duration_s) {
            return EOS;
        }
        count++;
        return new PPMImage(pool);  // deep copy
    }
};

// ============================================================================
// GrayscaleWorker — TRANSFORM stage
// Converts RGB to grayscale: gray = (77*R + 150*G + 29*B) >> 8
// Output is 3-channel (R=G=B=gray) to maintain PPMImage format.
// ============================================================================

struct GrayscaleWorker : ff_node_t<PPMImage> {
    PPMImage* svc(PPMImage* input) override {
        int w = input->width;
        int h = input->height;
        auto* out = new PPMImage(w, h);
        for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
                uint32_t r = input->get_r(x, y);
                uint32_t g = input->get_g(x, y);
                uint32_t b = input->get_b(x, y);
                uint8_t gray = (uint8_t)((r * 77 + g * 150 + b * 29) >> 8);
                out->set_pixel(x, y, gray, gray, gray);
            }
        }
        delete input;
        return out;
    }
};

// ============================================================================
// GaussianBlurWorker — TRANSFORM stage
// 3x3 Gaussian kernel: [1 2 1; 2 4 2; 1 2 1] / 16
// ============================================================================

struct GaussianBlurWorker : ff_node_t<PPMImage> {
    PPMImage* svc(PPMImage* input) override {
        int w = input->width;
        int h = input->height;
        auto* out = new PPMImage(w, h);
        for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
                uint32_t sum_r = 0, sum_g = 0, sum_b = 0;
                for (int ky = -1; ky <= 1; ky++) {
                    for (int kx = -1; kx <= 1; kx++) {
                        int nx = std::clamp(x + kx, 0, w - 1);
                        int ny = std::clamp(y + ky, 0, h - 1);
                        uint32_t weight;
                        if (kx == 0 && ky == 0)      weight = 4;
                        else if (kx == 0 || ky == 0)  weight = 2;
                        else                           weight = 1;
                        sum_r += input->get_r(nx, ny) * weight;
                        sum_g += input->get_g(nx, ny) * weight;
                        sum_b += input->get_b(nx, ny) * weight;
                    }
                }
                out->set_pixel(x, y,
                    (uint8_t)(sum_r >> 4),
                    (uint8_t)(sum_g >> 4),
                    (uint8_t)(sum_b >> 4));
            }
        }
        delete input;
        return out;
    }
};

// ============================================================================
// SharpenWorker — TRANSFORM stage
// 3x3 sharpening kernel: [0 -1 0; -1 5 -1; 0 -1 0]
// ============================================================================

struct SharpenWorker : ff_node_t<PPMImage> {
    PPMImage* svc(PPMImage* input) override {
        int w = input->width;
        int h = input->height;
        auto* out = new PPMImage(w, h);
        for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
                int32_t sum_r = input->get_r(x, y) * 5;
                int32_t sum_g = input->get_g(x, y) * 5;
                int32_t sum_b = input->get_b(x, y) * 5;
                // 4-connected neighbors
                int dx[] = {0, 0, -1, 1};
                int dy[] = {-1, 1, 0, 0};
                for (int i = 0; i < 4; i++) {
                    int nx = std::clamp(x + dx[i], 0, w - 1);
                    int ny = std::clamp(y + dy[i], 0, h - 1);
                    sum_r -= input->get_r(nx, ny);
                    sum_g -= input->get_g(nx, ny);
                    sum_b -= input->get_b(nx, ny);
                }
                out->set_pixel(x, y,
                    (uint8_t)std::clamp(sum_r, (int32_t)0, (int32_t)255),
                    (uint8_t)std::clamp(sum_g, (int32_t)0, (int32_t)255),
                    (uint8_t)std::clamp(sum_b, (int32_t)0, (int32_t)255));
            }
        }
        delete input;
        return out;
    }
};

// ============================================================================
// PassThroughWorker — TRANSFORM stage (no-op)
// Forwards images without processing. Used for source bandwidth baseline.
// ============================================================================

struct PassThroughWorker : ff_node_t<PPMImage> {
    PPMImage* svc(PPMImage* input) override {
        return input;
    }
};

// ============================================================================
// ImageSink — last pipeline stage (collects results)
// Counts images, computes checksum, reports timing/throughput.
// ============================================================================

struct ImageSink : ff_node_t<PPMImage> {
    int count;
    uint64_t checksum_total;
    std::chrono::high_resolution_clock::time_point start_time;

    ImageSink() : count(0), checksum_total(0) {}

    PPMImage* svc(PPMImage* input) override {
        if (count == 0)
            start_time = std::chrono::high_resolution_clock::now();
        count++;
        // checksum_total += input->checksum();
        delete input;
        return GO_ON;
    }

    void svc_end() override {
        auto end_time = std::chrono::high_resolution_clock::now();
        double ms = std::chrono::duration<double, std::milli>(end_time - start_time).count();
        double tput = (ms > 0) ? count / (ms / 1000.0) : 0;
        std::printf("  [Sink] Images received: %d | Checksum: %lu | Time: %.2f ms | Throughput: %.2f img/s\n",
                    count, checksum_total, ms, tput);
    }

    // Accessors for outer timing
    int get_count() const { return count; }
    uint64_t get_checksum() const { return checksum_total; }
};

#endif // IMAGE_STAGES_HPP
