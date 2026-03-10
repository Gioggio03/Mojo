#!/usr/bin/env python3
"""Generate test PPM (P6) images of various sizes with gradient patterns."""

import struct
import os

def generate_ppm(filename, width, height):
    """Generate a PPM P6 (binary) image with a gradient pattern."""
    with open(filename, 'wb') as f:
        # PPM header
        header = f"P6\n{width} {height}\n255\n"
        f.write(header.encode('ascii'))
        # Pixel data: gradient pattern
        for y in range(height):
            for x in range(width):
                r = int((x * 255) / max(width - 1, 1))
                g = int((y * 255) / max(height - 1, 1))
                b = int(((x + y) * 127) / max(width + height - 2, 1))
                f.write(struct.pack('BBB', r, g, b))
    print(f"  Generated {filename} ({width}x{height}, {os.path.getsize(filename)} bytes)")

def main():
    os.makedirs("test_images", exist_ok=True)
    sizes = [(64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)]
    print("Generating test PPM images...")
    for w, h in sizes:
        generate_ppm(f"test_images/gradient_{w}x{h}.ppm", w, h)
    print("Done!")

if __name__ == "__main__":
    main()
