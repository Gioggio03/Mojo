// FastFlow node definitions — V2 optimized stages
// Equivalent to image_stages_2.mojo: same optimizations applied to C++.
//
// Grayscale V2:  flat loop, direct pointer, no accessor overhead
// GaussianBlur V2: interior path (no clamp) + border path, unrolled kernel
// Sharpen V2:    interior path (no clamp, 5 explicit taps) + border path
//
// Each transform stage accumulates compute_time_ns and prints it in svc_end().

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
// ImageSource — SOURCE stage (time-based, 60s default)
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
        if (elapsed.count() >= duration_s) return EOS;
        count++;
        return new PPMImage(pool);
    }
};

// ============================================================================
// GrayscaleWorker V2 — flat loop, direct pointer
// gray = (77*R + 150*G + 29*B) >> 8
// ============================================================================
struct GrayscaleWorker : ff_node_t<PPMImage> {
    uint64_t compute_time_ns = 0;

    PPMImage* svc(PPMImage* input) override {
        auto t0 = std::chrono::high_resolution_clock::now();

        int n_pixels = input->width * input->height;
        auto* out = new PPMImage(input->width, input->height);
        const uint8_t* __restrict__ in_ptr  = input->data;
              uint8_t* __restrict__ out_ptr = out->data;

        for (int i = 0; i < n_pixels; i++) {
            int base = i * 3;
            uint32_t r = in_ptr[base];
            uint32_t g = in_ptr[base + 1];
            uint32_t b = in_ptr[base + 2];
            uint8_t gray = (uint8_t)((r * 77 + g * 150 + b * 29) >> 8);
            out_ptr[base]     = gray;
            out_ptr[base + 1] = gray;
            out_ptr[base + 2] = gray;
        }

        compute_time_ns += std::chrono::duration_cast<std::chrono::nanoseconds>(
            std::chrono::high_resolution_clock::now() - t0).count();
        delete input;
        return out;
    }

    void svc_end() override {
        std::printf("    [Grayscale] compute time: %.6f ms\n",
                    compute_time_ns / 1'000'000.0);
    }
};

// ============================================================================
// GaussianBlurWorker V2 — interior path (no clamp) + border path
// Kernel: [1 2 1; 2 4 2; 1 2 1] / 16
// ============================================================================
struct GaussianBlurWorker : ff_node_t<PPMImage> {
    uint64_t compute_time_ns = 0;

    inline int clamp_idx(int v, int lo, int hi) const {
        if (v < lo) return lo;
        if (v > hi) return hi;
        return v;
    }

    PPMImage* svc(PPMImage* input) override {
        auto t0 = std::chrono::high_resolution_clock::now();

        int w = input->width;
        int h = input->height;
        auto* out = new PPMImage(w, h);
        const uint8_t* in_ptr  = input->data;
              uint8_t* out_ptr = out->data;

        // Interior path — no clamp needed
        for (int y = 1; y < h - 1; y++) {
            int row_m1 = (y - 1) * w;
            int row_0  =  y      * w;
            int row_p1 = (y + 1) * w;
            for (int x = 1; x < w - 1; x++) {
                int xm1 = x - 1, xp1 = x + 1;
                int i00 = (row_m1 + xm1) * 3, i01 = (row_m1 + x) * 3, i02 = (row_m1 + xp1) * 3;
                int i10 = (row_0  + xm1) * 3, i11 = (row_0  + x) * 3, i12 = (row_0  + xp1) * 3;
                int i20 = (row_p1 + xm1) * 3, i21 = (row_p1 + x) * 3, i22 = (row_p1 + xp1) * 3;
                for (int c = 0; c < 3; c++) {
                    uint32_t v =
                          in_ptr[i00+c]
                        + (in_ptr[i01+c] << 1)
                        +  in_ptr[i02+c]
                        + (in_ptr[i10+c] << 1)
                        + (in_ptr[i11+c] << 2)
                        + (in_ptr[i12+c] << 1)
                        +  in_ptr[i20+c]
                        + (in_ptr[i21+c] << 1)
                        +  in_ptr[i22+c];
                    out_ptr[i11 + c] = (uint8_t)(v >> 4);
                }
            }
        }

        // Border path — top and bottom rows
        for (int x = 0; x < w; x++) {
            for (int pass = 0; pass < 2; pass++) {
                int y = (pass == 0) ? 0 : h - 1;
                uint32_t sr = 0, sg = 0, sb = 0;
                for (int ky = -1; ky <= 1; ky++) {
                    int yy = clamp_idx(y + ky, 0, h - 1);
                    for (int kx = -1; kx <= 1; kx++) {
                        int xx = clamp_idx(x + kx, 0, w - 1);
                        int idx = (yy * w + xx) * 3;
                        uint32_t wt = ((kx == 0) ? 2u : 1u) * ((ky == 0) ? 2u : 1u);
                        sr += in_ptr[idx]   * wt;
                        sg += in_ptr[idx+1] * wt;
                        sb += in_ptr[idx+2] * wt;
                    }
                }
                int oidx = (y * w + x) * 3;
                out_ptr[oidx]   = (uint8_t)(sr >> 4);
                out_ptr[oidx+1] = (uint8_t)(sg >> 4);
                out_ptr[oidx+2] = (uint8_t)(sb >> 4);
            }
        }

        // Border path — left and right columns (skip corners already done)
        for (int y = 1; y < h - 1; y++) {
            for (int pass = 0; pass < 2; pass++) {
                int x = (pass == 0) ? 0 : w - 1;
                uint32_t sr = 0, sg = 0, sb = 0;
                for (int ky = -1; ky <= 1; ky++) {
                    int yy = clamp_idx(y + ky, 0, h - 1);
                    for (int kx = -1; kx <= 1; kx++) {
                        int xx = clamp_idx(x + kx, 0, w - 1);
                        int idx = (yy * w + xx) * 3;
                        uint32_t wt = ((kx == 0) ? 2u : 1u) * ((ky == 0) ? 2u : 1u);
                        sr += in_ptr[idx]   * wt;
                        sg += in_ptr[idx+1] * wt;
                        sb += in_ptr[idx+2] * wt;
                    }
                }
                int oidx = (y * w + x) * 3;
                out_ptr[oidx]   = (uint8_t)(sr >> 4);
                out_ptr[oidx+1] = (uint8_t)(sg >> 4);
                out_ptr[oidx+2] = (uint8_t)(sb >> 4);
            }
        }

        compute_time_ns += std::chrono::duration_cast<std::chrono::nanoseconds>(
            std::chrono::high_resolution_clock::now() - t0).count();
        delete input;
        return out;
    }

    void svc_end() override {
        std::printf("    [GaussianBlur] compute time: %.6f ms\n",
                    compute_time_ns / 1'000'000.0);
    }
};

// ============================================================================
// SharpenWorker V2 — interior path (no clamp) + border path
// Kernel: [0 -1 0; -1 5 -1; 0 -1 0]
// ============================================================================
struct SharpenWorker : ff_node_t<PPMImage> {
    uint64_t compute_time_ns = 0;

    inline uint8_t clamp255(int v) const {
        if (v < 0)   return 0;
        if (v > 255) return 255;
        return (uint8_t)v;
    }

    PPMImage* svc(PPMImage* input) override {
        auto t0 = std::chrono::high_resolution_clock::now();

        int w = input->width;
        int h = input->height;
        auto* out = new PPMImage(w, h);
        const uint8_t* in_ptr  = input->data;
              uint8_t* out_ptr = out->data;

        // Interior path — no clamp needed
        for (int y = 1; y < h - 1; y++) {
            for (int x = 1; x < w - 1; x++) {
                int c  = (y * w + x) * 3;
                int up = ((y-1) * w + x) * 3;
                int dn = ((y+1) * w + x) * 3;
                int lt = (y * w + (x-1)) * 3;
                int rt = (y * w + (x+1)) * 3;
                for (int ch = 0; ch < 3; ch++) {
                    int v = in_ptr[c+ch]  * 5
                          - in_ptr[up+ch]
                          - in_ptr[dn+ch]
                          - in_ptr[lt+ch]
                          - in_ptr[rt+ch];
                    out_ptr[c + ch] = clamp255(v);
                }
            }
        }

        // Border path — only edge pixels
        for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
                if (x != 0 && x != w-1 && y != 0 && y != h-1) continue;
                int c = (y * w + x) * 3;
                for (int ch = 0; ch < 3; ch++) {
                    int v = in_ptr[c+ch] * 5;
                    int ny, nx;
                    ny = (y-1 < 0) ? 0 : y-1; v -= in_ptr[(ny*w+x)*3+ch];
                    ny = (y+1 >= h) ? h-1 : y+1; v -= in_ptr[(ny*w+x)*3+ch];
                    nx = (x-1 < 0) ? 0 : x-1; v -= in_ptr[(y*w+nx)*3+ch];
                    nx = (x+1 >= w) ? w-1 : x+1; v -= in_ptr[(y*w+nx)*3+ch];
                    out_ptr[c + ch] = clamp255(v);
                }
            }
        }

        compute_time_ns += std::chrono::duration_cast<std::chrono::nanoseconds>(
            std::chrono::high_resolution_clock::now() - t0).count();
        delete input;
        return out;
    }

    void svc_end() override {
        std::printf("    [Sharpen] compute time: %.6f ms\n",
                    compute_time_ns / 1'000'000.0);
    }
};

// ============================================================================
// PassThroughWorker — no-op (source baseline)
// ============================================================================
struct PassThroughWorker : ff_node_t<PPMImage> {
    PPMImage* svc(PPMImage* input) override { return input; }
};

// ============================================================================
// ImageSink — collects results, reports timing/throughput
// ============================================================================
struct ImageSink : ff_node_t<PPMImage> {
    int count = 0;
    uint64_t checksum_total = 0;
    std::chrono::high_resolution_clock::time_point start_time;

    PPMImage* svc(PPMImage* input) override {
        if (count == 0)
            start_time = std::chrono::high_resolution_clock::now();
        count++;
        delete input;
        return GO_ON;
    }

    void svc_end() override {
        auto end_time = std::chrono::high_resolution_clock::now();
        double ms = std::chrono::duration<double, std::milli>(end_time - start_time).count();
        double tput = (ms > 0) ? count / (ms / 1000.0) : 0;
        std::printf("  [Sink] Images received: %d | Checksum: %lu | Time: %.6f ms | Throughput: %.10f img/s\n",
                    count, checksum_total, ms, tput);
    }

    int get_count() const { return count; }
    uint64_t get_checksum() const { return checksum_total; }
};

#endif // IMAGE_STAGES_HPP
