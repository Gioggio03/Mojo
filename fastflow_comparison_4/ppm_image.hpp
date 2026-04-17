// PPMImage — PLANAR layout (V4)
//
// Layout: [R plane: W*H bytes | pad | G plane: W*H bytes | pad | B plane: W*H bytes]
//
// PLANE_PAD (128 bytes = 2 cache lines) is added between planes to break
// cache-set aliasing.  On the Xeon E5-2695 v2 used for benchmarks:
//   L1: 32 KB, 8-way, 64 B lines → aliasing every 4096 bytes
//   L2: 256 KB, 8-way, 64 B lines → aliasing every 32768 bytes
// For a 512×512 image, plane size = 262144 bytes = 64×4096 = 8×32768.
// Without padding, R and G planes map to exactly the same L1 and L2 cache
// sets: every access to the G (or B) plane evicts the R plane from both L1
// and L2, causing thrashing across the 3 channel passes in each convolution.
// Adding 128 bytes shifts the plane offset to 262272 ≡ 128 (mod 4096) and
// 262272 ≡ 128 (mod 32768) — no aliasing in either cache level.

#ifndef PPM_IMAGE_HPP
#define PPM_IMAGE_HPP

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <algorithm>

struct PPMImage {
    static constexpr int PLANE_PAD = 128;  // bytes of padding between planes

    int width;
    int height;
    uint8_t* data;  // [R plane | PAD | G plane | PAD | B plane]

    int plane_stride() const { return width * height + PLANE_PAD; }
    int alloc_size()   const { return width * height * 3 + 2 * PLANE_PAD; }

    PPMImage() : width(0), height(0), data(nullptr) {}

    PPMImage(int w, int h) : width(w), height(h) {
        data = new uint8_t[w * h * 3 + 2 * PLANE_PAD]();
    }

    PPMImage(const PPMImage& o) : width(o.width), height(o.height) {
        int n = o.alloc_size();
        data = (n > 0 && o.data) ? new uint8_t[n] : nullptr;
        if (data) std::memcpy(data, o.data, n);
    }

    PPMImage& operator=(const PPMImage& o) {
        if (this != &o) {
            delete[] data;
            width = o.width; height = o.height;
            int n = o.alloc_size();
            data = (n > 0 && o.data) ? new uint8_t[n] : nullptr;
            if (data) std::memcpy(data, o.data, n);
        }
        return *this;
    }

    PPMImage(PPMImage&& o) noexcept : width(o.width), height(o.height), data(o.data) {
        o.width = 0; o.height = 0; o.data = nullptr;
    }

    PPMImage& operator=(PPMImage&& o) noexcept {
        if (this != &o) {
            delete[] data;
            width = o.width; height = o.height; data = o.data;
            o.width = 0; o.height = 0; o.data = nullptr;
        }
        return *this;
    }

    ~PPMImage() { delete[] data; }

    int plane_size() const { return width * height; }
    int num_bytes()  const { return width * height * 3; }

    // Planar channel accessors (stride = plane_size + PLANE_PAD)
    uint8_t*       r_plane()       { return data; }
    const uint8_t* r_plane() const { return data; }
    uint8_t*       g_plane()       { return data + plane_stride(); }
    const uint8_t* g_plane() const { return data + plane_stride(); }
    uint8_t*       b_plane()       { return data + 2 * plane_stride(); }
    const uint8_t* b_plane() const { return data + 2 * plane_stride(); }

    uint8_t get_r(int x, int y) const { return r_plane()[y * width + x]; }
    uint8_t get_g(int x, int y) const { return g_plane()[y * width + x]; }
    uint8_t get_b(int x, int y) const { return b_plane()[y * width + x]; }

    void set_pixel(int x, int y, uint8_t r, uint8_t g, uint8_t b) {
        int idx = y * width + x;
        r_plane()[idx] = r;
        g_plane()[idx] = g;
        b_plane()[idx] = b;
    }

    static PPMImage create_gradient(int w, int h) {
        PPMImage img(w, h);
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
                img.set_pixel(x, y,
                    (uint8_t)((x * 255) / std::max(w-1, 1)),
                    (uint8_t)((y * 255) / std::max(h-1, 1)),
                    (uint8_t)(((x+y) * 127) / std::max(w+h-2, 1)));
        return img;
    }
};

#endif // PPM_IMAGE_HPP
