// PPMImage struct — raw pixel buffer for image processing pipeline
// Direct C++ equivalent of the Mojo PPMImage struct.
// Data is heap-allocated for efficient move semantics.

#ifndef PPM_IMAGE_HPP
#define PPM_IMAGE_HPP

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <algorithm>
#include <iostream>

struct PPMImage {
    int width;
    int height;
    uint8_t* data;  // RGB pixel data (W*H*3 bytes)

    // Default constructor — 0x0 image, null pointer
    PPMImage() : width(0), height(0), data(nullptr) {}

    // Constructor with dimensions — zero-initialized pixel buffer
    PPMImage(int w, int h) : width(w), height(h) {
        int num_bytes = w * h * 3;
        data = new uint8_t[num_bytes]();
    }

    // Constructor with dimensions and fill value
    PPMImage(int w, int h, uint8_t fill) : width(w), height(h) {
        int num_bytes = w * h * 3;
        data = new uint8_t[num_bytes];
        std::memset(data, fill, num_bytes);
    }

    // Copy constructor — deep copy (O(W*H*3))
    PPMImage(const PPMImage& other) : width(other.width), height(other.height) {
        int num_bytes = width * height * 3;
        if (num_bytes > 0 && other.data) {
            data = new uint8_t[num_bytes];
            std::memcpy(data, other.data, num_bytes);
        } else {
            data = nullptr;
        }
    }

    // Copy assignment
    PPMImage& operator=(const PPMImage& other) {
        if (this != &other) {
            delete[] data;
            width = other.width;
            height = other.height;
            int num_bytes = width * height * 3;
            if (num_bytes > 0 && other.data) {
                data = new uint8_t[num_bytes];
                std::memcpy(data, other.data, num_bytes);
            } else {
                data = nullptr;
            }
        }
        return *this;
    }

    // Move constructor — steal pointer (O(1))
    PPMImage(PPMImage&& other) noexcept
        : width(other.width), height(other.height), data(other.data) {
        other.width = 0;
        other.height = 0;
        other.data = nullptr;
    }

    // Move assignment
    PPMImage& operator=(PPMImage&& other) noexcept {
        if (this != &other) {
            delete[] data;
            width = other.width;
            height = other.height;
            data = other.data;
            other.width = 0;
            other.height = 0;
            other.data = nullptr;
        }
        return *this;
    }

    // Destructor
    ~PPMImage() {
        delete[] data;
    }

    int num_bytes() const { return width * height * 3; }

    // Pixel access
    uint8_t get_r(int x, int y) const { return data[(y * width + x) * 3]; }
    uint8_t get_g(int x, int y) const { return data[(y * width + x) * 3 + 1]; }
    uint8_t get_b(int x, int y) const { return data[(y * width + x) * 3 + 2]; }

    void set_pixel(int x, int y, uint8_t r, uint8_t g, uint8_t b) {
        int idx = (y * width + x) * 3;
        data[idx]     = r;
        data[idx + 1] = g;
        data[idx + 2] = b;
    }

    uint8_t get_byte(int index) const { return data[index]; }
    void set_byte(int index, uint8_t value) { data[index] = value; }

    // Simple checksum (sum of all bytes) for validation
    uint64_t checksum() const {
        uint64_t total = 0;
        int n = num_bytes();
        for (int i = 0; i < n; i++) {
            total += data[i];
        }
        return total;
    }

    // Create a gradient test image (matches Mojo's create_gradient exactly)
    static PPMImage create_gradient(int w, int h) {
        PPMImage img(w, h);
        for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
                uint8_t r = (uint8_t)((x * 255) / std::max(w - 1, 1));
                uint8_t g = (uint8_t)((y * 255) / std::max(h - 1, 1));
                uint8_t b = (uint8_t)(((x + y) * 127) / std::max(w + h - 2, 1));
                img.set_pixel(x, y, r, g, b);
            }
        }
        return img;
    }
};

#endif // PPM_IMAGE_HPP
