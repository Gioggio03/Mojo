# sharpen_debug.mojo
#
# Confronto pixel-per-pixel tra SharpenV1 (originale) e SharpenV2 (ottimizzata).
#
# Ottimizzazioni in V2 (stessa strategia di blur_v2):
#   - Interior path (pixel non di bordo): nessun loop sui 4 vicini, tap espliciti
#   - Nessun clamp nel hot path (solo sui pixel di bordo)
#   - Accesso diretto via data_ptr invece di get_r/get_g/get_b
#   - Scrittura diretta dei 3 canali con un unico indice base
#
# Kernel sharpening: center*5 - top - bottom - left - right (clamp a [0,255])
#
# Eseguire con:
#   cd debug/sharpen && mojo sharpen_debug.mojo

from ppm_image import PPMImage
from time import perf_counter_ns

# ============================================================================
# SharpenV1 — originale da image_stages.mojo
# ============================================================================
fn sharpen_v1(input: PPMImage) -> PPMImage:
    var w = input.width
    var h = input.height
    var out = PPMImage(w, h)
    for y in range(h):
        for x in range(w):
            var sum_r: Int32 = input.get_r(x, y).cast[DType.int32]() * 5
            var sum_g: Int32 = input.get_g(x, y).cast[DType.int32]() * 5
            var sum_b: Int32 = input.get_b(x, y).cast[DType.int32]() * 5
            for i in range(4):
                var nx = x; var ny = y
                if i == 0:   ny = y - 1
                elif i == 1: ny = y + 1
                elif i == 2: nx = x - 1
                else:        nx = x + 1
                if nx < 0: nx = 0
                if nx >= w: nx = w - 1
                if ny < 0: ny = 0
                if ny >= h: ny = h - 1
                sum_r -= input.get_r(nx, ny).cast[DType.int32]()
                sum_g -= input.get_g(nx, ny).cast[DType.int32]()
                sum_b -= input.get_b(nx, ny).cast[DType.int32]()
            if sum_r < 0: sum_r = 0
            if sum_r > 255: sum_r = 255
            if sum_g < 0: sum_g = 0
            if sum_g > 255: sum_g = 255
            if sum_b < 0: sum_b = 0
            if sum_b > 255: sum_b = 255
            out.set_pixel(x, y,
                sum_r.cast[DType.uint8](),
                sum_g.cast[DType.uint8](),
                sum_b.cast[DType.uint8]())
    return out

# ============================================================================
# SharpenV2 — ottimizzata
# Interior path senza clamp + border path con clamp.
# ============================================================================
@always_inline
fn load_byte(ptr: UnsafePointer[UInt8, MutExternalOrigin], i: Int) -> Int:
    return Int((ptr + i).load())

@always_inline
fn clamp255(v: Int) -> UInt8:
    if v < 0:   return 0
    if v > 255: return 255
    return UInt8(v)

fn sharpen_v2(input: PPMImage) -> PPMImage:
    var w = input.width
    var h = input.height
    var out = PPMImage(w, h)
    var in_ptr  = input.data_ptr
    var out_ptr = out.data_ptr

    # ---- Interior: y in [1, h-2], x in [1, w-2] — no clamp ----
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            var c  = (y * w + x) * 3          # center
            var up = ((y - 1) * w + x) * 3    # above
            var dn = ((y + 1) * w + x) * 3    # below
            var lt = (y * w + (x - 1)) * 3    # left
            var rt = (y * w + (x + 1)) * 3    # right

            for ch in range(3):
                var v = load_byte(in_ptr, c  + ch) * 5 \
                      - load_byte(in_ptr, up + ch) \
                      - load_byte(in_ptr, dn + ch) \
                      - load_byte(in_ptr, lt + ch) \
                      - load_byte(in_ptr, rt + ch)
                (out_ptr + c + ch).store(clamp255(v))

    # ---- Border: pixels on the 4 edges — with clamp ----
    for y in range(h):
        for x in range(w):
            if x != 0 and x != w - 1 and y != 0 and y != h - 1:
                continue
            var sum_r: Int = load_byte(in_ptr, (y * w + x) * 3    ) * 5
            var sum_g: Int = load_byte(in_ptr, (y * w + x) * 3 + 1) * 5
            var sum_b: Int = load_byte(in_ptr, (y * w + x) * 3 + 2) * 5
            # 4 neighbors with clamp
            var nx: Int; var ny: Int
            # up
            ny = y - 1
            if ny < 0: ny = 0
            sum_r -= load_byte(in_ptr, (ny * w + x) * 3    )
            sum_g -= load_byte(in_ptr, (ny * w + x) * 3 + 1)
            sum_b -= load_byte(in_ptr, (ny * w + x) * 3 + 2)
            # down
            ny = y + 1
            if ny >= h: ny = h - 1
            sum_r -= load_byte(in_ptr, (ny * w + x) * 3    )
            sum_g -= load_byte(in_ptr, (ny * w + x) * 3 + 1)
            sum_b -= load_byte(in_ptr, (ny * w + x) * 3 + 2)
            # left
            nx = x - 1
            if nx < 0: nx = 0
            sum_r -= load_byte(in_ptr, (y * w + nx) * 3    )
            sum_g -= load_byte(in_ptr, (y * w + nx) * 3 + 1)
            sum_b -= load_byte(in_ptr, (y * w + nx) * 3 + 2)
            # right
            nx = x + 1
            if nx >= w: nx = w - 1
            sum_r -= load_byte(in_ptr, (y * w + nx) * 3    )
            sum_g -= load_byte(in_ptr, (y * w + nx) * 3 + 1)
            sum_b -= load_byte(in_ptr, (y * w + nx) * 3 + 2)

            var base = (y * w + x) * 3
            (out_ptr + base    ).store(clamp255(sum_r))
            (out_ptr + base + 1).store(clamp255(sum_g))
            (out_ptr + base + 2).store(clamp255(sum_b))

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

fn compare(img: PPMImage, label: String, max_print: Int = 10):
    var W = img.width
    var H = img.height
    print("\n--- " + label + " (" + String(W) + "x" + String(H) + ") ---")

    var t0 = perf_counter_ns()
    var out1 = sharpen_v1(img)
    var t1 = perf_counter_ns()
    var out2 = sharpen_v2(img)
    var t2 = perf_counter_ns()

    var ms1 = Float64(Int(t1 - t0)) / 1_000_000.0
    var ms2 = Float64(Int(t2 - t1)) / 1_000_000.0
    print("  V1: " + String(ms1) + " ms  |  V2: " + String(ms2) + " ms  |  speedup: " + String(ms1 / ms2) + "x")

    var cs1 = out1.checksum()
    var cs2 = out2.checksum()
    print("  Checksum V1=" + String(cs1) + "  V2=" + String(cs2))

    if cs1 == cs2:
        print("  [OK] identico")
        return

    var diff_count = 0
    for y in range(H):
        for x in range(W):
            var r1 = out1.get_r(x, y); var g1 = out1.get_g(x, y); var b1 = out1.get_b(x, y)
            var r2 = out2.get_r(x, y); var g2 = out2.get_g(x, y); var b2 = out2.get_b(x, y)
            if r1 != r2 or g1 != g2 or b1 != b2:
                diff_count += 1
                if diff_count <= max_print:
                    var flag = " [BORDER]" if (x == 0 or x == W-1 or y == 0 or y == H-1) else " [INTERIOR]"
                    print("  pixel(" + String(x) + "," + String(y) + ")" + flag +
                          "  V1=(" + String(Int(r1)) + "," + String(Int(g1)) + "," + String(Int(b1)) + ")" +
                          "  V2=(" + String(Int(r2)) + "," + String(Int(g2)) + "," + String(Int(b2)) + ")")
    print("  [DIFF] totale pixel diversi: " + String(diff_count))

# ============================================================================
# Main
# ============================================================================
def main():
    print("=" * 60)
    print("Sharpen V1 vs V2 — confronto pixel per pixel")
    print("=" * 60)

    compare(PPMImage.create_gradient(512, 512), "gradiente 512x512")
    compare(PPMImage.create_gradient(4, 4),     "gradiente 4x4 (quasi tutto bordo)")
    compare(PPMImage.create_gradient(3, 3),     "gradiente 3x3 (solo bordo)")
    compare(make_random_image(512, 512, 42),    "random 512x512 (seed=42)")
    compare(make_random_image(512, 512, 99),    "random 512x512 (seed=99)")

    print("\n" + "=" * 60)
    print("Fine test.")
