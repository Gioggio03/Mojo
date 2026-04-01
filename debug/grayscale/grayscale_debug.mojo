# grayscale_debug.mojo
#
# Confronto pixel-per-pixel tra V1, V2 e V3 (SIMD).
#
# V1: loop y,x + accessor get_r/g/b + set_pixel
# V2: loop piatto, pointer diretto, scalare
# V3: loop piatto, pointer diretto, SIMD[UInt16, 8] per aritmetica su 8 pixel alla volta
#
# Eseguire con:
#   cd debug/grayscale && mojo grayscale_debug.mojo

from ppm_image import PPMImage
from time import perf_counter_ns

# ============================================================================
# GrayscaleV1 — originale da image_stages.mojo
# ============================================================================
fn grayscale_v1(input: PPMImage) -> PPMImage:
    var w = input.width
    var h = input.height
    var out = PPMImage(w, h)
    for y in range(h):
        for x in range(w):
            var r = input.get_r(x, y).cast[DType.uint32]()
            var g = input.get_g(x, y).cast[DType.uint32]()
            var b = input.get_b(x, y).cast[DType.uint32]()
            var gray = UInt8(((r * 77 + g * 150 + b * 29) >> 8).cast[DType.uint8]())
            out.set_pixel(x, y, gray, gray, gray)
    return out

# ============================================================================
# GrayscaleV2 — loop piatto, pointer diretto, scalare
# ============================================================================
fn grayscale_v2(input: PPMImage) -> PPMImage:
    var n_pixels = input.width * input.height
    var out = PPMImage(input.width, input.height)
    var in_ptr  = input.data_ptr
    var out_ptr = out.data_ptr
    for i in range(n_pixels):
        var base = i * 3
        var r = Int((in_ptr + base    ).load())
        var g = Int((in_ptr + base + 1).load())
        var b = Int((in_ptr + base + 2).load())
        var gray = UInt8((r * 77 + g * 150 + b * 29) >> 8)
        (out_ptr + base    ).store(gray)
        (out_ptr + base + 1).store(gray)
        (out_ptr + base + 2).store(gray)
    return out

# ============================================================================
# GrayscaleV3 — SIMD: processa 8 pixel alla volta con SIMD[UInt16, 8]
#
# L'aritmetica  gray = (77*R + 150*G + 29*B) >> 8  viene eseguita su vettori
# di 8 elementi, permettendo al compilatore di emettere istruzioni AVX2/SSE4.
# I load rimangono scalari (stride 3 non è vettorizzabile direttamente) ma il
# loop viene completamente unrollato da @parameter for.
# ============================================================================
fn grayscale_v3(input: PPMImage) -> PPMImage:
    alias CHUNK = 8
    var n_pixels = input.width * input.height
    var out = PPMImage(input.width, input.height)
    var in_ptr  = input.data_ptr
    var out_ptr = out.data_ptr

    var i = 0
    var limit = n_pixels - (n_pixels % CHUNK)

    while i < limit:
        var base = i * 3

        # Carica 8 pixel in vettori UInt16
        var r = SIMD[DType.uint16, CHUNK](0)
        var g = SIMD[DType.uint16, CHUNK](0)
        var b = SIMD[DType.uint16, CHUNK](0)

        @parameter
        for j in range(CHUNK):
            r[j] = (in_ptr + base + j * 3    ).load().cast[DType.uint16]()
            g[j] = (in_ptr + base + j * 3 + 1).load().cast[DType.uint16]()
            b[j] = (in_ptr + base + j * 3 + 2).load().cast[DType.uint16]()

        # Aritmetica vettoriale su 8 pixel simultaneamente
        var gray = (r * 77 + g * 150 + b * 29) >> 8

        @parameter
        for j in range(CHUNK):
            var gv = gray[j].cast[DType.uint8]()
            (out_ptr + base + j * 3    ).store(gv)
            (out_ptr + base + j * 3 + 1).store(gv)
            (out_ptr + base + j * 3 + 2).store(gv)

        i += CHUNK

    # Resto (pixel non multipli di 8)
    while i < n_pixels:
        var base = i * 3
        var r = Int((in_ptr + base    ).load())
        var g = Int((in_ptr + base + 1).load())
        var b = Int((in_ptr + base + 2).load())
        var gray = UInt8((r * 77 + g * 150 + b * 29) >> 8)
        (out_ptr + base    ).store(gray)
        (out_ptr + base + 1).store(gray)
        (out_ptr + base + 2).store(gray)
        i += 1

    return out

# ============================================================================
# Helpers
# ============================================================================
fn make_random_image(w: Int, h: Int, seed: UInt8) -> PPMImage:
    var img = PPMImage(w, h)
    var v: UInt8 = seed
    for i in range(w * h * 3):
        v = v ^ (v << 3) ^ (v >> 5) ^ UInt8(i & 0xFF)
        img.set_byte(i, v)
    return img

fn compare(img: PPMImage, label: String):
    var W = img.width
    var H = img.height
    print("\n--- " + label + " (" + String(W) + "x" + String(H) + ") ---")

    var t0 = perf_counter_ns()
    var out1 = grayscale_v1(img)
    var t1 = perf_counter_ns()
    var out2 = grayscale_v2(img)
    var t2 = perf_counter_ns()
    var out3 = grayscale_v3(img)
    var t3 = perf_counter_ns()

    var ms1 = Float64(Int(t1 - t0)) / 1_000_000.0
    var ms2 = Float64(Int(t2 - t1)) / 1_000_000.0
    var ms3 = Float64(Int(t3 - t2)) / 1_000_000.0
    print("  V1: " + String(ms1) + " ms")
    print("  V2: " + String(ms2) + " ms  (speedup vs V1: " + String(ms1 / ms2) + "x)")
    print("  V3: " + String(ms3) + " ms  (speedup vs V1: " + String(ms1 / ms3) + "x  |  vs V2: " + String(ms2 / ms3) + "x)")

    var cs1 = out1.checksum()
    var cs2 = out2.checksum()
    var cs3 = out3.checksum()
    print("  Checksum: V1=" + String(cs1) + "  V2=" + String(cs2) + "  V3=" + String(cs3))

    if cs1 == cs2 and cs1 == cs3:
        print("  [OK] tutti identici")
    else:
        if cs1 != cs2: print("  [DIFF] V1 != V2")
        if cs1 != cs3: print("  [DIFF] V1 != V3")

# ============================================================================
# Main
# ============================================================================
def main():
    print("=" * 60)
    print("Grayscale V1 vs V2 vs V3 (SIMD) — confronto pixel per pixel")
    print("=" * 60)

    compare(PPMImage.create_gradient(512, 512), "gradiente 512x512")
    compare(PPMImage.create_gradient(4, 4),     "gradiente 4x4")
    compare(make_random_image(512, 512, 42),    "random 512x512 (seed=42)")
    compare(make_random_image(512, 512, 99),    "random 512x512 (seed=99)")

    print("\n" + "=" * 60)
    print("Fine test.")
