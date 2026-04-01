# blur_debug.mojo
#
# Confronto pixel-per-pixel tra GaussianBlurV1 (originale) e GaussianBlurV2 (ottimizzata).
# Entrambe le implementazioni sono copiate qui con nomi diversi per isolare il bug.
#
# Eseguire con:
#   cd debug && mojo blur_debug.mojo

from collections import Optional
from ppm_image import PPMImage
from time import perf_counter_ns

# ============================================================================
# GaussianBlurV1 — implementazione originale (image_stages.mojo)
# Loop annidato 3x3 su tutti i pixel con clamp ai bordi.
# ============================================================================
struct GaussianBlurV1:
    fn __init__(out self):
        pass

    fn compute(self, input: PPMImage) -> PPMImage:
        var w = input.width
        var h = input.height
        var out = PPMImage(w, h)
        for y in range(h):
            for x in range(w):
                var sum_r: UInt32 = 0
                var sum_g: UInt32 = 0
                var sum_b: UInt32 = 0
                for ky in range(-1, 2):
                    for kx in range(-1, 2):
                        var nx = x + kx
                        var ny = y + ky
                        if nx < 0: nx = 0
                        if nx >= w: nx = w - 1
                        if ny < 0: ny = 0
                        if ny >= h: ny = h - 1
                        var weight: UInt32
                        if kx == 0 and ky == 0:
                            weight = 4
                        elif kx == 0 or ky == 0:
                            weight = 2
                        else:
                            weight = 1
                        sum_r += input.get_r(nx, ny).cast[DType.uint32]() * weight
                        sum_g += input.get_g(nx, ny).cast[DType.uint32]() * weight
                        sum_b += input.get_b(nx, ny).cast[DType.uint32]() * weight
                out.set_pixel(x, y,
                    (sum_r >> 4).cast[DType.uint8](),
                    (sum_g >> 4).cast[DType.uint8](),
                    (sum_b >> 4).cast[DType.uint8]())
        return out

# ============================================================================
# Helpers condivisi tra V2 e debug
# ============================================================================
struct RGB3:
    var r: Int
    var g: Int
    var b: Int
    fn __init__(out self, r: Int, g: Int, b: Int):
        self.r = r
        self.g = g
        self.b = b

@always_inline
fn load_u8(base: UnsafePointer[UInt8, MutExternalOrigin], i: Int) -> Int:
    return Int((base + i).load())

@always_inline
fn clamp_val(v: Int, lo: Int, hi: Int) -> Int:
    if v < lo: return lo
    if v > hi: return hi
    return v

@always_inline
fn idx3(x: Int, y: Int, width: Int) -> Int:
    return (y * width + x) * 3

fn blur_border_pixel(
    in_ptr: UnsafePointer[UInt8, MutExternalOrigin],
    x: Int, y: Int, width: Int, height: Int
) -> RGB3:
    var sr: Int = 0
    var sg: Int = 0
    var sb: Int = 0
    for ky in range(-1, 2):
        var yy = clamp_val(y + ky, 0, height - 1)
        for kx in range(-1, 2):
            var xx = clamp_val(x + kx, 0, width - 1)
            var i = idx3(xx, yy, width)
            var w: Int = 1
            if ky == 0: w = w << 1
            if kx == 0: w = w << 1
            sr += w * load_u8(in_ptr, i)
            sg += w * load_u8(in_ptr, i + 1)
            sb += w * load_u8(in_ptr, i + 2)
    return RGB3(sr >> 4, sg >> 4, sb >> 4)

# ============================================================================
# GaussianBlurV2 — implementazione ottimizzata (image_stages_2.mojo)
# Fast interior path + border handling separato.
# ============================================================================
struct GaussianBlurV2:
    fn __init__(out self):
        pass

    fn compute(self, input: PPMImage) -> PPMImage:
        var width = input.width
        var height = input.height
        var out = PPMImage(width, height)
        var in_ptr = input.data_ptr

        if width < 3 or height < 3:
            for y in range(height):
                for x in range(width):
                    var rgb = blur_border_pixel(in_ptr, x, y, width, height)
                    out.set_pixel(x, y, UInt8(rgb.r), UInt8(rgb.g), UInt8(rgb.b))
            return out

        # Fast interior: y in [1, height-2], x in [1, width-2]
        for y in range(1, height - 1):
            var row_m1 = (y - 1) * width
            var row_0  = y * width
            var row_p1 = (y + 1) * width

            for x in range(1, width - 1):
                var xm1 = x - 1
                var xp1 = x + 1

                var i00 = (row_m1 + xm1) * 3
                var i01 = (row_m1 + x  ) * 3
                var i02 = (row_m1 + xp1) * 3
                var i10 = (row_0  + xm1) * 3
                var i11 = (row_0  + x  ) * 3
                var i12 = (row_0  + xp1) * 3
                var i20 = (row_p1 + xm1) * 3
                var i21 = (row_p1 + x  ) * 3
                var i22 = (row_p1 + xp1) * 3

                var r =
                    load_u8(in_ptr, i00) +
                    (load_u8(in_ptr, i01) << 1) +
                    load_u8(in_ptr, i02) +
                    (load_u8(in_ptr, i10) << 1) +
                    (load_u8(in_ptr, i11) << 2) +
                    (load_u8(in_ptr, i12) << 1) +
                    load_u8(in_ptr, i20) +
                    (load_u8(in_ptr, i21) << 1) +
                    load_u8(in_ptr, i22)

                var g =
                    load_u8(in_ptr, i00 + 1) +
                    (load_u8(in_ptr, i01 + 1) << 1) +
                    load_u8(in_ptr, i02 + 1) +
                    (load_u8(in_ptr, i10 + 1) << 1) +
                    (load_u8(in_ptr, i11 + 1) << 2) +
                    (load_u8(in_ptr, i12 + 1) << 1) +
                    load_u8(in_ptr, i20 + 1) +
                    (load_u8(in_ptr, i21 + 1) << 1) +
                    load_u8(in_ptr, i22 + 1)

                var b =
                    load_u8(in_ptr, i00 + 2) +
                    (load_u8(in_ptr, i01 + 2) << 1) +
                    load_u8(in_ptr, i02 + 2) +
                    (load_u8(in_ptr, i10 + 2) << 1) +
                    (load_u8(in_ptr, i11 + 2) << 2) +
                    (load_u8(in_ptr, i12 + 2) << 1) +
                    load_u8(in_ptr, i20 + 2) +
                    (load_u8(in_ptr, i21 + 2) << 1) +
                    load_u8(in_ptr, i22 + 2)

                out.set_pixel(x, y, UInt8(r >> 4), UInt8(g >> 4), UInt8(b >> 4))

        # Borders
        for x in range(width):
            var top = blur_border_pixel(in_ptr, x, 0, width, height)
            out.set_pixel(x, 0, UInt8(top.r), UInt8(top.g), UInt8(top.b))
            var bot = blur_border_pixel(in_ptr, x, height - 1, width, height)
            out.set_pixel(x, height - 1, UInt8(bot.r), UInt8(bot.g), UInt8(bot.b))

        for y in range(1, height - 1):
            var left = blur_border_pixel(in_ptr, 0, y, width, height)
            out.set_pixel(0, y, UInt8(left.r), UInt8(left.g), UInt8(left.b))
            var right = blur_border_pixel(in_ptr, width - 1, y, width, height)
            out.set_pixel(width - 1, y, UInt8(right.r), UInt8(right.g), UInt8(right.b))

        return out

# ============================================================================
# Main — confronto pixel per pixel
# ============================================================================
fn compare(img: PPMImage, label: String, max_print: Int = 10):
    var W = img.width
    var H = img.height
    print("\n--- " + label + " (" + String(W) + "x" + String(H) + ") ---")
    var b1 = GaussianBlurV1()
    var out1 = b1.compute(img)
    var b2 = GaussianBlurV2()
    var out2 = b2.compute(img)
    var cs1 = out1.checksum()
    var cs2 = out2.checksum()
    print("Checksum V1=" + String(cs1) + "  V2=" + String(cs2))
    if cs1 == cs2:
        print("[OK] identico")
        return
    var diff_count = 0
    var border_diffs = 0
    var interior_diffs = 0
    for y in range(H):
        for x in range(W):
            var r1 = out1.get_r(x, y); var g1 = out1.get_g(x, y); var bl1 = out1.get_b(x, y)
            var r2 = out2.get_r(x, y); var g2 = out2.get_g(x, y); var bl2 = out2.get_b(x, y)
            if r1 != r2 or g1 != g2 or bl1 != bl2:
                diff_count += 1
                var is_border = (x == 0 or x == W-1 or y == 0 or y == H-1)
                if is_border: border_diffs += 1
                else: interior_diffs += 1
                if diff_count <= max_print:
                    var flag = " [BORDER]" if is_border else " [INTERIOR]"
                    print("  pixel(" + String(x) + "," + String(y) + ")" + flag +
                          "  V1=(" + String(Int(r1)) + "," + String(Int(g1)) + "," + String(Int(bl1)) + ")" +
                          "  V2=(" + String(Int(r2)) + "," + String(Int(g2)) + "," + String(Int(bl2)) + ")")
    print("[DIFF] totale=" + String(diff_count) + "  bordo=" + String(border_diffs) + "  interno=" + String(interior_diffs))

fn make_random_image(w: Int, h: Int, seed: UInt8) -> PPMImage:
    var img = PPMImage(w, h)
    var v: UInt8 = seed
    for i in range(w * h * 3):
        v = v ^ (v << 3) ^ (v >> 5) ^ UInt8(i & 0xFF)  # cheap LFSR
        img.set_byte(i, v)
    return img

fn make_uniform_image(w: Int, h: Int, r: UInt8, g: UInt8, b: UInt8) -> PPMImage:
    var img = PPMImage(w, h)
    for y in range(h):
        for x in range(w):
            img.set_pixel(x, y, r, g, b)
    return img

def main():
    print("=" * 60)
    print("GaussianBlur V1 vs V2 — confronto pixel per pixel")
    print("=" * 60)

    # Test 1: gradiente standard 512x512
    var img = PPMImage.create_gradient(512, 512)

    compare(img, "gradiente 512x512")

    # Test 2: immagine piccola 4x4 (quasi tutto bordo)
    var img_small = PPMImage.create_gradient(4, 4)
    compare(img_small, "gradiente 4x4 (quasi tutto bordo)")

    # Test 3: immagine piccola 3x3 (solo bordo, nessun interior)
    var img_3x3 = PPMImage.create_gradient(3, 3)
    compare(img_3x3, "gradiente 3x3 (solo bordo)")

    # Test 4: immagine con pixel random
    var img_rand = make_random_image(512, 512, 42)
    compare(img_rand, "random 512x512 (seed=42)")

    # Test 5: immagine uniforme (tutti i pixel uguali)
    var img_unif = make_uniform_image(512, 512, 128, 64, 200)
    compare(img_unif, "uniforme 512x512 (128,64,200)")

    # Test 6: simula output Grayscale (R=G=B per ogni pixel)
    var img_gray = PPMImage.create_gradient(512, 512)
    for y in range(512):
        for x in range(512):
            var r = img_gray.get_r(x, y)
            var g = img_gray.get_g(x, y)
            var b = img_gray.get_b(x, y)
            var gr = UInt8(((r.cast[DType.uint32]() * 77 + g.cast[DType.uint32]() * 150 + b.cast[DType.uint32]() * 29) >> 8).cast[DType.uint8]())
            img_gray.set_pixel(x, y, gr, gr, gr)
    compare(img_gray, "grayscale 512x512 (simula output dopo Grayscale stage)")

    print("\n" + "=" * 60)
    print("Fine test.")
