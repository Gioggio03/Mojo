# Image processing pipeline stages — V3 (SIMD experiment, interleaved layout)
# Each stage satisfies StageTrait from MoStream
#
# V3 goal: add explicit SIMD to GaussianBlur and Sharpen interior paths
# to match (or exceed) the auto-vectorization that GCC -O3 applies on C++.
#
# Strategy (interleaved RGB layout, RGBRGB...):
#   - Process CHUNK=8 output pixels at a time along each row
#   - For each kernel tap, manually load 8 values per channel (stride-3 gather)
#   - GaussianBlur: SIMD[DType.uint16, 8] accumulation
#   - Sharpen:      SIMD[DType.int16,  8] accumulation (signed for subtract)
#   - Border pixels: unchanged scalar path from V2

from collections import Optional
from MoStream.communicator import MessageTrait
from MoStream.stage import StageKind, StageTrait
from ppm_image import PPMImage
from time import perf_counter_ns
from builtin import Tuple

struct RGB3:
    var r: Int
    var g: Int
    var b: Int

    fn __init__(out self, r: Int, g: Int, b: Int):
        self.r = r
        self.g = g
        self.b = b

# ============================================================================
# TimedImageSource — SOURCE stage (time-based)
# ============================================================================
struct TimedImageSource[ImgW: Int, ImgH: Int, DurationSec: Int = 60](StageTrait):
    comptime kind = StageKind.SOURCE
    comptime InType = PPMImage
    comptime OutType = PPMImage
    comptime name = "TimedImageSource"
    var count: Int
    var pool: PPMImage
    var start_ns: UInt
    var started: Bool

    fn __init__(out self):
        self.count = 0
        self.pool = PPMImage.create_gradient(Self.ImgW, Self.ImgH)
        self.start_ns = 0
        self.started = False

    fn next_element(mut self) raises -> Optional[PPMImage]:
        if not self.started:
            self.start_ns = perf_counter_ns()
            self.started = True
        var elapsed_ns = perf_counter_ns() - self.start_ns
        var limit_ns = UInt(Self.DurationSec) * 1_000_000_000
        if elapsed_ns >= limit_ns:
            return None
        self.count += 1
        return self.pool

    fn received_eos(mut self):
        pass

# ============================================================================
# ImageSource — SOURCE stage (count-based, for source baseline measurement)
# ============================================================================
struct ImageSource[ImgW: Int, ImgH: Int, NumMessages: Int](StageTrait):
    comptime kind = StageKind.SOURCE
    comptime InType = PPMImage
    comptime OutType = PPMImage
    comptime name = "ImageSource"
    var count: Int
    var pool: PPMImage

    fn __init__(out self):
        self.count = 0
        self.pool = PPMImage.create_gradient(Self.ImgW, Self.ImgH)

    fn next_element(mut self) raises -> Optional[PPMImage]:
        if self.count >= Self.NumMessages:
            return None
        self.count += 1
        return self.pool

    fn received_eos(mut self):
        pass

# ============================================================================
# Grayscale — TRANSFORM stage (unchanged from V2)
# ============================================================================
struct Grayscale(StageTrait):
    comptime kind = StageKind.TRANSFORM
    comptime InType = PPMImage
    comptime OutType = PPMImage
    comptime name = "Grayscale"
    var compute_time_ns: UInt

    fn __init__(out self):
        self.compute_time_ns = 0

    fn compute(mut self, var input: PPMImage) raises -> Optional[PPMImage]:
        var t0 = perf_counter_ns()
        comptime CHUNK = 8
        var n_pixels = input.width * input.height
        var out = PPMImage(input.width, input.height)
        var in_ptr  = input.data_ptr
        var out_ptr = out.data_ptr

        # SIMD path: gather CHUNK pixels (stride-3) per channel, compute gray vector
        var i = 0
        while i + CHUNK <= n_pixels:
            var base = i * 3
            var rv = SIMD[DType.uint16, CHUNK](0)
            var gv = SIMD[DType.uint16, CHUNK](0)
            var bv = SIMD[DType.uint16, CHUNK](0)
            @parameter
            for j in range(CHUNK):
                rv[j] = (in_ptr + base + j*3    ).load().cast[DType.uint16]()
                gv[j] = (in_ptr + base + j*3 + 1).load().cast[DType.uint16]()
                bv[j] = (in_ptr + base + j*3 + 2).load().cast[DType.uint16]()
            var gray = ((rv * 77 + gv * 150 + bv * 29) >> 8).cast[DType.uint8]()
            @parameter
            for j in range(CHUNK):
                (out_ptr + base + j*3    ).store(gray[j])
                (out_ptr + base + j*3 + 1).store(gray[j])
                (out_ptr + base + j*3 + 2).store(gray[j])
            i += CHUNK

        # Scalar remainder
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

        self.compute_time_ns += perf_counter_ns() - t0
        return out

    fn received_eos(mut self):
        print("    [" + Self.name + "] compute time: " + String(Float64(Int(self.compute_time_ns))/1_000_000.0) + " ms")

# ============================================================================
# GaussianBlur — TRANSFORM stage (V3: SIMD interior path, 8 pixels at a time)
#
# Kernel (Gaussian 3x3, divisor 16):
#   1 2 1
#   2 4 2
#   1 2 1
#
# Interior path: CHUNK=8 pixels per step, stride-3 gather per channel
# Border path:   unchanged scalar V2 code
# ============================================================================
struct GaussianBlur(StageTrait):
    comptime kind = StageKind.TRANSFORM
    comptime InType = PPMImage
    comptime OutType = PPMImage
    comptime name = "GaussianBlur"
    var compute_time_ns: UInt

    fn __init__(out self):
        self.compute_time_ns = 0

    @always_inline
    fn idx3(self, x: Int, y: Int, width: Int) -> Int:
        return (y * width + x) * 3

    @always_inline
    fn clamp(self, v: Int, lo: Int, hi: Int) -> Int:
        if v < lo: return lo
        if v > hi: return hi
        return v

    @always_inline
    fn load_u8(self, base: UnsafePointer[UInt8], i: Int) -> Int:
        return Int((base + i).load())

    @always_inline
    fn blur_border_pixel(
        self,
        in_ptr: UnsafePointer[UInt8],
        x: Int, y: Int, width: Int, height: Int,
    ) -> RGB3:
        var sr: Int = 0; var sg: Int = 0; var sb: Int = 0
        for ky in range(-1, 2):
            var yy = self.clamp(y + ky, 0, height - 1)
            for kx in range(-1, 2):
                var xx = self.clamp(x + kx, 0, width - 1)
                var i = self.idx3(xx, yy, width)
                var w: Int = 1
                if ky == 0: w = w << 1
                if kx == 0: w = w << 1
                sr += w * self.load_u8(in_ptr, i)
                sg += w * self.load_u8(in_ptr, i + 1)
                sb += w * self.load_u8(in_ptr, i + 2)
        return RGB3(sr >> 4, sg >> 4, sb >> 4)

    fn compute(mut self, var input: PPMImage) raises -> Optional[PPMImage]:
        var t0 = perf_counter_ns()
        comptime CHUNK = 8

        var width  = input.width
        var height = input.height
        if width <= 0 or height <= 0:
            return Optional[PPMImage]()

        var out     = PPMImage(width, height)
        var in_ptr  = input.data_ptr
        var out_ptr = out.data_ptr

        if width < 3 or height < 3:
            for y in range(height):
                for x in range(width):
                    var rgb = self.blur_border_pixel(in_ptr, x, y, width, height)
                    out.set_pixel(x, y, UInt8(rgb.r), UInt8(rgb.g), UInt8(rgb.b))
            self.compute_time_ns += perf_counter_ns() - t0
            return out

        # ── Interior: SIMD path (CHUNK pixels per step) ──────────────────────
        for y in range(1, height - 1):
            var row_m1 = (y - 1) * width
            var row_0  = y       * width
            var row_p1 = (y + 1) * width

            var x = 1
            while x + CHUNK <= width - 1:
                # Base byte indices for the 9 tap positions (channel-0 offset)
                var b00 = (row_m1 + x - 1) * 3   # (-1,-1)
                var b01 = (row_m1 + x    ) * 3   # (-1, 0)
                var b02 = (row_m1 + x + 1) * 3   # (-1,+1)
                var b10 = (row_0  + x - 1) * 3   # ( 0,-1)
                var b11 = (row_0  + x    ) * 3   # ( 0, 0)  ← output
                var b12 = (row_0  + x + 1) * 3   # ( 0,+1)
                var b20 = (row_p1 + x - 1) * 3   # (+1,-1)
                var b21 = (row_p1 + x    ) * 3   # (+1, 0)
                var b22 = (row_p1 + x + 1) * 3   # (+1,+1)

                # ── Red channel ───────────────────────────────────────────────
                var r00 = SIMD[DType.uint16, CHUNK](0); var r01 = SIMD[DType.uint16, CHUNK](0)
                var r02 = SIMD[DType.uint16, CHUNK](0); var r10 = SIMD[DType.uint16, CHUNK](0)
                var r11 = SIMD[DType.uint16, CHUNK](0); var r12 = SIMD[DType.uint16, CHUNK](0)
                var r20 = SIMD[DType.uint16, CHUNK](0); var r21 = SIMD[DType.uint16, CHUNK](0)
                var r22 = SIMD[DType.uint16, CHUNK](0)
                @parameter
                for j in range(CHUNK):
                    r00[j] = (in_ptr + b00 + j*3).load().cast[DType.uint16]()
                    r01[j] = (in_ptr + b01 + j*3).load().cast[DType.uint16]()
                    r02[j] = (in_ptr + b02 + j*3).load().cast[DType.uint16]()
                    r10[j] = (in_ptr + b10 + j*3).load().cast[DType.uint16]()
                    r11[j] = (in_ptr + b11 + j*3).load().cast[DType.uint16]()
                    r12[j] = (in_ptr + b12 + j*3).load().cast[DType.uint16]()
                    r20[j] = (in_ptr + b20 + j*3).load().cast[DType.uint16]()
                    r21[j] = (in_ptr + b21 + j*3).load().cast[DType.uint16]()
                    r22[j] = (in_ptr + b22 + j*3).load().cast[DType.uint16]()
                var res_r = (r00 + (r01 << 1) + r02
                           + (r10 << 1) + (r11 << 2) + (r12 << 1)
                           + r20 + (r21 << 1) + r22) >> 4
                @parameter
                for j in range(CHUNK):
                    (out_ptr + b11 + j*3).store(res_r[j].cast[DType.uint8]())

                # ── Green channel ─────────────────────────────────────────────
                var g00 = SIMD[DType.uint16, CHUNK](0); var g01 = SIMD[DType.uint16, CHUNK](0)
                var g02 = SIMD[DType.uint16, CHUNK](0); var g10 = SIMD[DType.uint16, CHUNK](0)
                var g11 = SIMD[DType.uint16, CHUNK](0); var g12 = SIMD[DType.uint16, CHUNK](0)
                var g20 = SIMD[DType.uint16, CHUNK](0); var g21 = SIMD[DType.uint16, CHUNK](0)
                var g22 = SIMD[DType.uint16, CHUNK](0)
                @parameter
                for j in range(CHUNK):
                    g00[j] = (in_ptr + b00 + 1 + j*3).load().cast[DType.uint16]()
                    g01[j] = (in_ptr + b01 + 1 + j*3).load().cast[DType.uint16]()
                    g02[j] = (in_ptr + b02 + 1 + j*3).load().cast[DType.uint16]()
                    g10[j] = (in_ptr + b10 + 1 + j*3).load().cast[DType.uint16]()
                    g11[j] = (in_ptr + b11 + 1 + j*3).load().cast[DType.uint16]()
                    g12[j] = (in_ptr + b12 + 1 + j*3).load().cast[DType.uint16]()
                    g20[j] = (in_ptr + b20 + 1 + j*3).load().cast[DType.uint16]()
                    g21[j] = (in_ptr + b21 + 1 + j*3).load().cast[DType.uint16]()
                    g22[j] = (in_ptr + b22 + 1 + j*3).load().cast[DType.uint16]()
                var res_g = (g00 + (g01 << 1) + g02
                           + (g10 << 1) + (g11 << 2) + (g12 << 1)
                           + g20 + (g21 << 1) + g22) >> 4
                @parameter
                for j in range(CHUNK):
                    (out_ptr + b11 + 1 + j*3).store(res_g[j].cast[DType.uint8]())

                # ── Blue channel ──────────────────────────────────────────────
                var bl00 = SIMD[DType.uint16, CHUNK](0); var bl01 = SIMD[DType.uint16, CHUNK](0)
                var bl02 = SIMD[DType.uint16, CHUNK](0); var bl10 = SIMD[DType.uint16, CHUNK](0)
                var bl11 = SIMD[DType.uint16, CHUNK](0); var bl12 = SIMD[DType.uint16, CHUNK](0)
                var bl20 = SIMD[DType.uint16, CHUNK](0); var bl21 = SIMD[DType.uint16, CHUNK](0)
                var bl22 = SIMD[DType.uint16, CHUNK](0)
                @parameter
                for j in range(CHUNK):
                    bl00[j] = (in_ptr + b00 + 2 + j*3).load().cast[DType.uint16]()
                    bl01[j] = (in_ptr + b01 + 2 + j*3).load().cast[DType.uint16]()
                    bl02[j] = (in_ptr + b02 + 2 + j*3).load().cast[DType.uint16]()
                    bl10[j] = (in_ptr + b10 + 2 + j*3).load().cast[DType.uint16]()
                    bl11[j] = (in_ptr + b11 + 2 + j*3).load().cast[DType.uint16]()
                    bl12[j] = (in_ptr + b12 + 2 + j*3).load().cast[DType.uint16]()
                    bl20[j] = (in_ptr + b20 + 2 + j*3).load().cast[DType.uint16]()
                    bl21[j] = (in_ptr + b21 + 2 + j*3).load().cast[DType.uint16]()
                    bl22[j] = (in_ptr + b22 + 2 + j*3).load().cast[DType.uint16]()
                var res_b = (bl00 + (bl01 << 1) + bl02
                           + (bl10 << 1) + (bl11 << 2) + (bl12 << 1)
                           + bl20 + (bl21 << 1) + bl22) >> 4
                @parameter
                for j in range(CHUNK):
                    (out_ptr + b11 + 2 + j*3).store(res_b[j].cast[DType.uint8]())

                x += CHUNK

            # ── Scalar remainder (pixels that don't fill a full CHUNK) ────────
            while x < width - 1:
                var xm1 = x - 1; var xp1 = x + 1
                var i00 = (row_m1 + xm1) * 3; var i01 = (row_m1 + x  ) * 3; var i02 = (row_m1 + xp1) * 3
                var i10 = (row_0  + xm1) * 3; var i11 = (row_0  + x  ) * 3; var i12 = (row_0  + xp1) * 3
                var i20 = (row_p1 + xm1) * 3; var i21 = (row_p1 + x  ) * 3; var i22 = (row_p1 + xp1) * 3
                var r = self.load_u8(in_ptr, i00) + (self.load_u8(in_ptr, i01) << 1) + self.load_u8(in_ptr, i02)
                      + (self.load_u8(in_ptr, i10) << 1) + (self.load_u8(in_ptr, i11) << 2) + (self.load_u8(in_ptr, i12) << 1)
                      + self.load_u8(in_ptr, i20) + (self.load_u8(in_ptr, i21) << 1) + self.load_u8(in_ptr, i22)
                var g = self.load_u8(in_ptr, i00+1) + (self.load_u8(in_ptr, i01+1) << 1) + self.load_u8(in_ptr, i02+1)
                      + (self.load_u8(in_ptr, i10+1) << 1) + (self.load_u8(in_ptr, i11+1) << 2) + (self.load_u8(in_ptr, i12+1) << 1)
                      + self.load_u8(in_ptr, i20+1) + (self.load_u8(in_ptr, i21+1) << 1) + self.load_u8(in_ptr, i22+1)
                var b = self.load_u8(in_ptr, i00+2) + (self.load_u8(in_ptr, i01+2) << 1) + self.load_u8(in_ptr, i02+2)
                      + (self.load_u8(in_ptr, i10+2) << 1) + (self.load_u8(in_ptr, i11+2) << 2) + (self.load_u8(in_ptr, i12+2) << 1)
                      + self.load_u8(in_ptr, i20+2) + (self.load_u8(in_ptr, i21+2) << 1) + self.load_u8(in_ptr, i22+2)
                (out_ptr + i11  ).store(UInt8(r >> 4))
                (out_ptr + i11+1).store(UInt8(g >> 4))
                (out_ptr + i11+2).store(UInt8(b >> 4))
                x += 1

        # ── Border pixels (top, bottom, left, right edges) ────────────────────
        for x in range(width):
            var top = self.blur_border_pixel(in_ptr, x, 0, width, height)
            out.set_pixel(x, 0, UInt8(top.r), UInt8(top.g), UInt8(top.b))
            var bot = self.blur_border_pixel(in_ptr, x, height - 1, width, height)
            out.set_pixel(x, height - 1, UInt8(bot.r), UInt8(bot.g), UInt8(bot.b))
        for y in range(1, height - 1):
            var lft = self.blur_border_pixel(in_ptr, 0, y, width, height)
            out.set_pixel(0, y, UInt8(lft.r), UInt8(lft.g), UInt8(lft.b))
            var rgt = self.blur_border_pixel(in_ptr, width - 1, y, width, height)
            out.set_pixel(width - 1, y, UInt8(rgt.r), UInt8(rgt.g), UInt8(rgt.b))

        self.compute_time_ns += perf_counter_ns() - t0
        return out

    fn received_eos(mut self):
        print("    [" + Self.name + "] compute time: " + String(Float64(Int(self.compute_time_ns))/1_000_000.0) + " ms")

# ============================================================================
# Sharpen — TRANSFORM stage (V3: SIMD interior path, 8 pixels at a time)
#
# Kernel:
#    0 -1  0
#   -1  5 -1
#    0 -1  0
#
# Interior path: CHUNK=8 pixels per step, SIMD[int16] for signed arithmetic
# Border path:   unchanged scalar V2 code
# ============================================================================
struct Sharpen(StageTrait):
    comptime kind = StageKind.TRANSFORM
    comptime InType = PPMImage
    comptime OutType = PPMImage
    comptime name = "Sharpen"
    var compute_time_ns: UInt

    fn __init__(out self):
        self.compute_time_ns = 0

    @always_inline
    fn clamp255(self, v: Int) -> UInt8:
        if v < 0:   return 0
        if v > 255: return 255
        return UInt8(v)

    @always_inline
    fn load_px(self, ptr: UnsafePointer[UInt8, MutExternalOrigin], i: Int) -> Int:
        return Int((ptr + i).load())

    fn compute(mut self, var input: PPMImage) raises -> Optional[PPMImage]:
        var t0 = perf_counter_ns()
        comptime CHUNK = 8
        var w = input.width
        var h = input.height
        var out     = PPMImage(w, h)
        var in_ptr  = input.data_ptr
        var out_ptr = out.data_ptr

        # ── Interior: SIMD path ───────────────────────────────────────────────
        for y in range(1, h - 1):
            var row_m = (y - 1) * w
            var row_0 = y       * w
            var row_p = (y + 1) * w

            var x = 1
            while x + CHUNK <= w - 1:
                # Base byte indices (channel-0 offset)
                var bc  = (row_0 + x    ) * 3   # center  ← output
                var bup = (row_m + x    ) * 3   # up
                var bdn = (row_p + x    ) * 3   # down
                var blt = (row_0 + x - 1) * 3   # left
                var brt = (row_0 + x + 1) * 3   # right

                # ── Red channel ───────────────────────────────────────────────
                var rc  = SIMD[DType.int16, CHUNK](0); var rup = SIMD[DType.int16, CHUNK](0)
                var rdn = SIMD[DType.int16, CHUNK](0); var rlt = SIMD[DType.int16, CHUNK](0)
                var rrt = SIMD[DType.int16, CHUNK](0)
                @parameter
                for j in range(CHUNK):
                    rc[j]  = (in_ptr + bc  + j*3).load().cast[DType.int16]()
                    rup[j] = (in_ptr + bup + j*3).load().cast[DType.int16]()
                    rdn[j] = (in_ptr + bdn + j*3).load().cast[DType.int16]()
                    rlt[j] = (in_ptr + blt + j*3).load().cast[DType.int16]()
                    rrt[j] = (in_ptr + brt + j*3).load().cast[DType.int16]()
                var res_r = rc * 5 - rup - rdn - rlt - rrt
                var cr = max(min(res_r, SIMD[DType.int16, CHUNK](255)), SIMD[DType.int16, CHUNK](0))
                @parameter
                for j in range(CHUNK):
                    (out_ptr + bc + j*3).store(cr[j].cast[DType.uint8]())

                # ── Green channel ─────────────────────────────────────────────
                var gc  = SIMD[DType.int16, CHUNK](0); var gup = SIMD[DType.int16, CHUNK](0)
                var gdn = SIMD[DType.int16, CHUNK](0); var glt = SIMD[DType.int16, CHUNK](0)
                var grt = SIMD[DType.int16, CHUNK](0)
                @parameter
                for j in range(CHUNK):
                    gc[j]  = (in_ptr + bc  + 1 + j*3).load().cast[DType.int16]()
                    gup[j] = (in_ptr + bup + 1 + j*3).load().cast[DType.int16]()
                    gdn[j] = (in_ptr + bdn + 1 + j*3).load().cast[DType.int16]()
                    glt[j] = (in_ptr + blt + 1 + j*3).load().cast[DType.int16]()
                    grt[j] = (in_ptr + brt + 1 + j*3).load().cast[DType.int16]()
                var res_g = gc * 5 - gup - gdn - glt - grt
                var cg = max(min(res_g, SIMD[DType.int16, CHUNK](255)), SIMD[DType.int16, CHUNK](0))
                @parameter
                for j in range(CHUNK):
                    (out_ptr + bc + 1 + j*3).store(cg[j].cast[DType.uint8]())

                # ── Blue channel ──────────────────────────────────────────────
                var blc  = SIMD[DType.int16, CHUNK](0); var blup = SIMD[DType.int16, CHUNK](0)
                var bldn = SIMD[DType.int16, CHUNK](0); var bllt = SIMD[DType.int16, CHUNK](0)
                var blrt = SIMD[DType.int16, CHUNK](0)
                @parameter
                for j in range(CHUNK):
                    blc[j]  = (in_ptr + bc  + 2 + j*3).load().cast[DType.int16]()
                    blup[j] = (in_ptr + bup + 2 + j*3).load().cast[DType.int16]()
                    bldn[j] = (in_ptr + bdn + 2 + j*3).load().cast[DType.int16]()
                    bllt[j] = (in_ptr + blt + 2 + j*3).load().cast[DType.int16]()
                    blrt[j] = (in_ptr + brt + 2 + j*3).load().cast[DType.int16]()
                var res_b = blc * 5 - blup - bldn - bllt - blrt
                var cb = max(min(res_b, SIMD[DType.int16, CHUNK](255)), SIMD[DType.int16, CHUNK](0))
                @parameter
                for j in range(CHUNK):
                    (out_ptr + bc + 2 + j*3).store(cb[j].cast[DType.uint8]())

                x += CHUNK

            # ── Scalar remainder ──────────────────────────────────────────────
            while x < w - 1:
                var c  = (y * w + x    ) * 3
                var up = ((y-1) * w + x) * 3
                var dn = ((y+1) * w + x) * 3
                var lt = (y * w + x - 1) * 3
                var rt = (y * w + x + 1) * 3
                for ch in range(3):
                    var v = self.load_px(in_ptr, c+ch) * 5
                          - self.load_px(in_ptr, up+ch)
                          - self.load_px(in_ptr, dn+ch)
                          - self.load_px(in_ptr, lt+ch)
                          - self.load_px(in_ptr, rt+ch)
                    (out_ptr + c + ch).store(self.clamp255(v))
                x += 1

        # ── Border pixels ─────────────────────────────────────────────────────
        for y in range(h):
            for x in range(w):
                if x != 0 and x != w - 1 and y != 0 and y != h - 1:
                    continue
                var sum_r = self.load_px(in_ptr, (y * w + x) * 3    ) * 5
                var sum_g = self.load_px(in_ptr, (y * w + x) * 3 + 1) * 5
                var sum_b = self.load_px(in_ptr, (y * w + x) * 3 + 2) * 5
                var ny: Int
                var nx: Int
                ny = y - 1
                if ny < 0: ny = 0
                sum_r -= self.load_px(in_ptr, (ny * w + x) * 3    )
                sum_g -= self.load_px(in_ptr, (ny * w + x) * 3 + 1)
                sum_b -= self.load_px(in_ptr, (ny * w + x) * 3 + 2)
                ny = y + 1
                if ny >= h: ny = h - 1
                sum_r -= self.load_px(in_ptr, (ny * w + x) * 3    )
                sum_g -= self.load_px(in_ptr, (ny * w + x) * 3 + 1)
                sum_b -= self.load_px(in_ptr, (ny * w + x) * 3 + 2)
                nx = x - 1
                if nx < 0: nx = 0
                sum_r -= self.load_px(in_ptr, (y * w + nx) * 3    )
                sum_g -= self.load_px(in_ptr, (y * w + nx) * 3 + 1)
                sum_b -= self.load_px(in_ptr, (y * w + nx) * 3 + 2)
                nx = x + 1
                if nx >= w: nx = w - 1
                sum_r -= self.load_px(in_ptr, (y * w + nx) * 3    )
                sum_g -= self.load_px(in_ptr, (y * w + nx) * 3 + 1)
                sum_b -= self.load_px(in_ptr, (y * w + nx) * 3 + 2)
                var base = (y * w + x) * 3
                (out_ptr + base    ).store(self.clamp255(sum_r))
                (out_ptr + base + 1).store(self.clamp255(sum_g))
                (out_ptr + base + 2).store(self.clamp255(sum_b))

        self.compute_time_ns += perf_counter_ns() - t0
        return out

    fn received_eos(mut self):
        print("    [" + Self.name + "] compute time: " + String(Float64(Int(self.compute_time_ns))/1_000_000.0) + " ms")

# ============================================================================
# PassThrough — TRANSFORM stage (no-op)
# ============================================================================
struct PassThrough(StageTrait):
    comptime kind = StageKind.TRANSFORM
    comptime InType = PPMImage
    comptime OutType = PPMImage
    comptime name = "PassThrough"

    fn __init__(out self):
        pass

    fn compute(mut self, var input: PPMImage) raises -> Optional[PPMImage]:
        return input

    fn received_eos(mut self):
        pass

# ============================================================================
# ImageSink — SINK stage
# ============================================================================
struct ImageSink(StageTrait):
    comptime kind = StageKind.SINK
    comptime InType = PPMImage
    comptime OutType = PPMImage
    comptime name = "ImageSink"
    var count: Int
    var checksum_total: UInt64
    var start_ns: UInt
    var count_ptr: UnsafePointer[Int, MutExternalOrigin]

    fn __init__(out self):
        self.count = 0
        self.checksum_total = 0
        self.start_ns = 0
        self.count_ptr = alloc[Int](1)
        self.count_ptr[] = 0

    fn __del__(deinit self):
        pass

    fn consume_element(mut self, var input: PPMImage) raises:
        if self.count == 0:
            self.start_ns = perf_counter_ns()
        self.count += 1
        self.count_ptr[] = self.count

    fn received_eos(mut self):
        var elapsed_ns = perf_counter_ns() - self.start_ns
        var elapsed_ms = Float64(Int(elapsed_ns)) / 1_000_000.0
        var throughput: Float64 = 0.0
        if elapsed_ms > 0:
            throughput = Float64(self.count) / (elapsed_ms / 1000.0)
        print("  [Sink] Images received:", self.count,
              "| Checksum:", self.checksum_total,
              "| Time:", elapsed_ms, "ms",
              "| Throughput:", throughput, "img/s")
