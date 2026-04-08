// PPMImage — PLANAR layout (V4)
//
// Layout in memory: [R plane: W*H bytes | G plane: W*H bytes | B plane: W*H bytes]
// (same total size as interleaved, different organization)
//
// Benefit: consecutive pixels of the same channel are adjacent in memory.
// This allows GCC to auto-vectorize convolution inner loops at -O2 (not just -O3),
// because the access pattern is stride-1 (contiguous), not stride-3 (interleaved).

#ifndef PPM_IMAGE_HPP
#define PPM_IMAGE_HPP

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <algorithm>

struct PPMImage {
    int width;
    int height;
    uint8_t* data;  // W*H*3 bytes: [R plane | G plane | B plane]

    PPMImage() : width(0), height(0), data(nullptr) {}

    PPMImage(int w, int h) : width(w), height(h) {
        data = new uint8_t[w * h * 3]();
    }

    PPMImage(const PPMImage& o) : width(o.width), height(o.height) {
        int n = width * height * 3;
        data = (n > 0 && o.data) ? new uint8_t[n] : nullptr;
        if (data) std::memcpy(data, o.data, n);
    }

    PPMImage& operator=(const PPMImage& o) {
        if (this != &o) {
            delete[] data;
            width = o.width; height = o.height;
            int n = width * height * 3;
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

    // Planar channel accessors
    uint8_t*       r_plane()       { return data; }
    const uint8_t* r_plane() const { return data; }
    uint8_t*       g_plane()       { return data + width * height; }
    const uint8_t* g_plane() const { return data + width * height; }
    uint8_t*       b_plane()       { return data + 2 * width * height; }
    const uint8_t* b_plane() const { return data + 2 * width * height; }

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
