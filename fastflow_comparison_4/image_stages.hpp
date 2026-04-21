// FastFlow node definitions — V4 planar layout stages
//
// Key difference from V2 (interleaved): each channel is stored in its own
// contiguous plane (R|G|B). Inner loops access stride-1 data, which GCC
// can auto-vectorize even at -O2 (vs -O3 required for interleaved).
//
// GaussianBlur inner loop (per channel, per row):
//   for (int x = 1; x < w-1; x++) {
//       uint32_t v = rm1[x-1] + 2*rm1[x] + rm1[x+1]
//                  + 2*r0[x-1] + 4*r0[x] + 2*r0[x+1]
//                  + rp1[x-1]  + 2*rp1[x]  + rp1[x+1];
//       out_row[x] = v >> 4;
//   }
// → GCC -O2 emits SSE2/AVX2 vector instructions on this pattern.

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
// ImageSource — SOURCE stage (time-based)
// ============================================================================
struct ImageSource : ff_node_t<PPMImage> {
    int img_w, img_h;
    int count = 0;
    double duration_s;
    std::chrono::time_point<std::chrono::high_resolution_clock> start_time;
    PPMImage pool;

    ImageSource(int w, int h, double duration = 60.0)
        : img_w(w), img_h(h), duration_s(duration),
          pool(PPMImage::create_gradient(w, h)) {}

    int svc_init() override {
        start_time = std::chrono::high_resolution_clock::now();
        return 0;
    }

    PPMImage* svc(PPMImage*) override {
        auto elapsed = std::chrono::duration<double>(
            std::chrono::high_resolution_clock::now() - start_time).count();
        if (elapsed >= duration_s) return EOS;
        count++;
        return new PPMImage(pool);
    }
};

// ============================================================================
// GrayscaleWorker — flat loop over planar planes
// gray = (77*R + 150*G + 29*B) >> 8
// ============================================================================
struct GrayscaleWorker : ff_node_t<PPMImage> {
    uint64_t compute_time_ns = 0;
    uint64_t count = 0;

    PPMImage* svc(PPMImage* input) override {
        auto t0 = std::chrono::high_resolution_clock::now();
        count++;
        int n = input->plane_size();
        auto* out = new PPMImage(input->width, input->height);

        const uint8_t* __restrict__ in_r = input->r_plane();
        const uint8_t* __restrict__ in_g = input->g_plane();
        const uint8_t* __restrict__ in_b = input->b_plane();
        uint8_t* __restrict__ out_r = out->r_plane();
        uint8_t* __restrict__ out_g = out->g_plane();
        uint8_t* __restrict__ out_b = out->b_plane();

        // Stride-1 access per channel — uint16_t intermediate + __restrict__ + ivdep → GCC vectorizza
        // Max value: 255*(77+150+29) = 255*256 = 65280 < 65535 → uint16_t sufficiente
        #pragma GCC ivdep
        for (int i = 0; i < n; i++) {
            uint8_t gray = (uint8_t)(((uint16_t)in_r[i] * 77u
                                    + (uint16_t)in_g[i] * 150u
                                    + (uint16_t)in_b[i] * 29u) >> 8);
            out_r[i] = gray;
            out_g[i] = gray;
            out_b[i] = gray;
        }

        compute_time_ns += std::chrono::duration_cast<std::chrono::nanoseconds>(
            std::chrono::high_resolution_clock::now() - t0).count();
        delete input;
        return out;
    }

    void svc_end() override {
        std::printf("    [Grayscale] compute time per image: %.6f ms\n",
                    compute_time_ns / 1'000'000.0 / count);
    }
};

// ============================================================================
// GaussianBlurWorker — planar, auto-vectorizable inner loop
// Kernel: [1 2 1; 2 4 2; 1 2 1] / 16
// ============================================================================
struct GaussianBlurWorker : ff_node_t<PPMImage> {
    uint64_t compute_time_ns = 0;
    uint16_t count = 0;

    inline int clamp_coord(int v, int lo, int hi) const {
        return v < lo ? lo : v > hi ? hi : v;
    }

    // Border pixel (scalar, called only for edge pixels)
    inline uint8_t border_pixel(const uint8_t __restrict__* ch, int x, int y, int w, int h) const {
        uint32_t s = 0;
        for (int ky = -1; ky <= 1; ky++) {
            int yy = clamp_coord(y + ky, 0, h-1);
            for (int kx = -1; kx <= 1; kx++) {
                int xx = clamp_coord(x + kx, 0, w-1);
                uint32_t wt = ((kx==0)?2u:1u) * ((ky==0)?2u:1u);
                s += ch[yy * w + xx] * wt;
            }
        }
        return (uint8_t)(s >> 4);
    }

    PPMImage* svc(PPMImage* input) override {
        auto t0 = std::chrono::high_resolution_clock::now();
        count++;

        int w = input->width, h = input->height;
        auto* out = new PPMImage(w, h);

        // Process each channel independently — stride-1, auto-vectorizable
        const uint8_t __restrict__ * channels_in[3]  = { input->r_plane(), input->g_plane(), input->b_plane() };
              uint8_t __restrict__ * channels_out[3] = { out->r_plane(),   out->g_plane(),   out->b_plane()   };

        for (int ch = 0; ch < 3; ch++) {
            const uint8_t __restrict__ * src = channels_in[ch];
                  uint8_t __restrict__ * dst = channels_out[ch];

            // Interior: stride-1 inner loop, GCC vectorizes this at -O2
            for (int y = 1; y < h-1; y++) {
                const uint8_t __restrict__ * rm1 = src + (y-1) * w;
                const uint8_t __restrict__ * r0  = src +  y    * w;
                const uint8_t __restrict__ * rp1 = src + (y+1) * w;
                      uint8_t __restrict__ * out_row = dst + y * w;

                for (int x = 1; x < w-1; x++) {
                    uint32_t v = rm1[x-1] + 2u*rm1[x] + rm1[x+1]
                               + 2u*r0[x-1] + 4u*r0[x] + 2u*r0[x+1]
                               + rp1[x-1]   + 2u*rp1[x] + rp1[x+1];
                    out_row[x] = (uint8_t)(v >> 4);
                }
            }

            // Borders (scalar)
            for (int x = 0; x < w; x++) {
                dst[x]           = border_pixel(src, x, 0,   w, h);
                dst[(h-1)*w + x] = border_pixel(src, x, h-1, w, h);
            }
            for (int y = 1; y < h-1; y++) {
                dst[y*w]       = border_pixel(src, 0,   y, w, h);
                dst[y*w + w-1] = border_pixel(src, w-1, y, w, h);
            }
        }

        compute_time_ns += std::chrono::duration_cast<std::chrono::nanoseconds>(
            std::chrono::high_resolution_clock::now() - t0).count();
        delete input;
        return out;
    }

    void svc_end() override {
        std::printf("    [GaussianBlur] compute time per image: %.6f ms\n",
                    compute_time_ns / 1'000'000.0 / count);
    }
};

// ============================================================================
// SharpenWorker — planar, auto-vectorizable inner loop
// Kernel: [0 -1 0; -1 5 -1; 0 -1 0]
// ============================================================================
struct SharpenWorker : ff_node_t<PPMImage> {
    uint64_t compute_time_ns = 0;
    uint16_t count = 0;

    inline uint8_t clamp255(int v) const {
        return v < 0 ? 0 : v > 255 ? 255 : (uint8_t)v;
    }

    inline uint8_t border_pixel(const uint8_t __restrict__* ch, int x, int y, int w, int h) const {
        auto clamp = [](int v, int lo, int hi){ return v<lo?lo:v>hi?hi:v; };
        int v = ch[y*w + x] * 5;
        v -= ch[clamp(y-1,0,h-1)*w + x];
        v -= ch[clamp(y+1,0,h-1)*w + x];
        v -= ch[y*w + clamp(x-1,0,w-1)];
        v -= ch[y*w + clamp(x+1,0,w-1)];
        return clamp255(v);
    }

    PPMImage* svc(PPMImage* input) override {
        auto t0 = std::chrono::high_resolution_clock::now();
        count++;

        int w = input->width, h = input->height;
        auto* out = new PPMImage(w, h);

        const uint8_t __restrict__ * channels_in[3]  = { input->r_plane(), input->g_plane(), input->b_plane() };
              uint8_t __restrict__ * channels_out[3] = { out->r_plane(),   out->g_plane(),   out->b_plane()   };

        for (int ch = 0; ch < 3; ch++) {
            const uint8_t __restrict__ * src = channels_in[ch];
                  uint8_t __restrict__ * dst = channels_out[ch];

            // Interior: int16_t arithmetic + std::clamp — GCC vectorizes at -O2
            // Using int16_t avoids int32 widening that prevents vectorization;
            // std::clamp on int16_t emits pmaxsw/pminsw (SSE2), branch-free.
            for (int y = 1; y < h-1; y++) {
                const uint8_t __restrict__ * rm = src + (y-1) * w;
                const uint8_t __restrict__ * r0 = src +  y    * w;
                const uint8_t __restrict__ * rp = src + (y+1) * w;
                      uint8_t __restrict__ * out_row = dst + y * w;

                for (int x = 1; x < w-1; x++) {
                    int16_t v = (int16_t)r0[x] * 5 - rm[x] - rp[x] - r0[x-1] - r0[x+1];
                    out_row[x] = (uint8_t)std::clamp((int16_t)v, (int16_t)0, (int16_t)255);
                }
            }

            // Borders — 4 explicit loops, no h*w scan
            for (int x = 0; x < w; x++) {
                dst[x]           = border_pixel(src, x, 0,   w, h);
                dst[(h-1)*w + x] = border_pixel(src, x, h-1, w, h);
            }
            for (int y = 1; y < h-1; y++) {
                dst[y*w]       = border_pixel(src, 0,   y, w, h);
                dst[y*w + w-1] = border_pixel(src, w-1, y, w, h);
            }
        }

        compute_time_ns += std::chrono::duration_cast<std::chrono::nanoseconds>(
            std::chrono::high_resolution_clock::now() - t0).count();
        delete input;
        return out;
    }

    void svc_end() override {
        std::printf("    [Sharpen] compute time per image: %.6f ms\n",
                    compute_time_ns / 1'000'000.0 / count);
    }
};

// ============================================================================
// PassThroughWorker — no-op
// ============================================================================
struct PassThroughWorker : ff_node_t<PPMImage> {
    PPMImage* svc(PPMImage* input) override { return input; }
};

// ============================================================================
// ImageSink — SINK stage
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
