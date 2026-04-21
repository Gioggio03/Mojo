# Image processing pipeline stages — V4 (planar layout + true vector loads)
# Each stage satisfies StageTrait from MoStream
#
# V4 goal: planar layout (R|G|B planes) + genuine SIMD via ptr.load[width=8]().
#
# KEY DIFFERENCE from V3 (interleaved):
#   V3: @parameter for j in range(8): v[j] = (ptr + base + j*3).load()
#       → stride-3 gather, 8 scalar loads, LLVM cannot fuse into a vector instruction
#
#   V4: var v8 = (ptr + base).load[width=8]()
#       → single vmovdqu / vpmovsxbw, true 128-bit vector load
#       → possible because planar layout makes the 8 tap values contiguous
#
# C++ equivalent: the inner loop `for x: out[x] = f(src[x-1], src[x], src[x+1])`
# is auto-vectorized by GCC even at -O2 when data is contiguous (planar).
#
# Stage summary:
#   Grayscale:    8 pixels per step, 3 vector loads (R/G/B planes)
#   GaussianBlur: 8 pixels per step, 9 vector loads per channel (3 rows × 3 offsets)
#   Sharpen:      8 pixels per step, 5 vector loads per channel

from MoStream.communicator import MessageTrait
from MoStream.stage import StageKind, StageTrait
from ppm_image import PPMImage
from time import perf_counter_ns

# ============================================================================
# TimedImageSource
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

    def __init__(out self):
        self.count = 0
        self.pool = PPMImage.create_gradient(Self.ImgW, Self.ImgH)
        self.start_ns = 0
        self.started = False

    def next_element(mut self) -> Optional[PPMImage]:
        if not self.started:
            self.start_ns = perf_counter_ns()
            self.started = True
        if perf_counter_ns() - self.start_ns >= UInt(Self.DurationSec) * 1_000_000_000:
            return None
        self.count += 1
        return self.pool

    def received_eos(mut self):
        pass

# ============================================================================
# ImageSource (count-based, for source baseline)
# ============================================================================
struct ImageSource[ImgW: Int, ImgH: Int, NumMessages: Int](StageTrait):
    comptime kind = StageKind.SOURCE
    comptime InType = PPMImage
    comptime OutType = PPMImage
    comptime name = "ImageSource"
    var count: Int
    var pool: PPMImage

    def __init__(out self):
        self.count = 0
        self.pool = PPMImage.create_gradient(Self.ImgW, Self.ImgH)

    def next_element(mut self) -> Optional[PPMImage]:
        if self.count >= Self.NumMessages:
            return None
        self.count += 1
        return self.pool

    fn received_eos(mut self):
        pass

# ============================================================================
# Grayscale — V4: true vector loads from 3 planar channels
# gray = (77*R + 150*G + 29*B) >> 8
# ============================================================================
struct Grayscale(StageTrait):
    comptime kind = StageKind.TRANSFORM
    comptime InType = PPMImage
    comptime OutType = PPMImage
    comptime name = "Grayscale"
    var compute_time_ns: UInt
    var count: Int

    def __init__(out self):
        self.compute_time_ns = 0
        self.count = 0

    def compute(mut self, var input: PPMImage) -> Optional[PPMImage]:
        var t0 = perf_counter_ns()
        comptime CHUNK = 8
        var n = input.width * input.height
        var out = PPMImage(input.width, input.height)
        var in_r = input.r_ptr(); var in_g = input.g_ptr(); var in_b = input.b_ptr()
        var out_r = out.r_ptr();  var out_g = out.g_ptr();  var out_b = out.b_ptr()

        var i = 0
        while i + CHUNK <= n:
            # Single vector load per channel — vmovdqu + vpmovsxbw
            var rv = (in_r + i).load[width=CHUNK]().cast[DType.uint16]()
            var gv = (in_g + i).load[width=CHUNK]().cast[DType.uint16]()
            var bv = (in_b + i).load[width=CHUNK]().cast[DType.uint16]()
            var gray8 = ((rv * 77 + gv * 150 + bv * 29) >> 8).cast[DType.uint8]()
            (out_r + i).store(gray8)
            (out_g + i).store(gray8)
            (out_b + i).store(gray8)
            i += CHUNK

        while i < n:
            var gray = UInt8((Int((in_r+i).load())*77 + Int((in_g+i).load())*150 + Int((in_b+i).load())*29) >> 8)
            (out_r + i).store(gray); (out_g + i).store(gray); (out_b + i).store(gray)
            i += 1

        self.compute_time_ns += perf_counter_ns() - t0
        self.count += 1
        return out

    fn received_eos(mut self):
        var total_ms = Float64(Int(self.compute_time_ns)) / 1_000_000.0
        var avg_ms = total_ms / Float64(self.count) if self.count > 0 else 0.0
        print("    [" + Self.name + "] total=" + String(total_ms) + " ms | n=" + String(self.count) + " | avg/img=" + String(avg_ms) + " ms")

# ============================================================================
# GaussianBlur — V4: 9 true vector loads per channel
#
# For 8 consecutive output pixels at row y, column x..x+7:
#   tap (dy, dx): ch_ptr[row+dy*w + x+dx .. x+dx+7]  — contiguous, 1 vmovdqu
#
# Kernel: [1 2 1; 2 4 2; 1 2 1] / 16
# ============================================================================
struct GaussianBlur(StageTrait):
    comptime kind = StageKind.TRANSFORM
    comptime InType = PPMImage
    comptime OutType = PPMImage
    comptime name = "GaussianBlur"
    var compute_time_ns: UInt
    var count: Int

    def __init__(out self):
        self.compute_time_ns = 0
        self.count = 0

    @always_inline
    def clamp_coord(self, v: Int, lo: Int, hi: Int) -> Int:
        if v < lo: return lo
        if v > hi: return hi
        return v

    @always_inline
    def border_pixel(self, ch: UnsafePointer[UInt8, MutExternalOrigin],
                     x: Int, y: Int, w: Int, h: Int) -> UInt8:
        var s: Int = 0
        for ky in range(-1, 2):
            var yy = self.clamp_coord(y + ky, 0, h - 1)
            for kx in range(-1, 2):
                var xx = self.clamp_coord(x + kx, 0, w - 1)
                var wt: Int = 1
                if ky == 0: wt <<= 1
                if kx == 0: wt <<= 1
                s += wt * Int((ch + yy * w + xx).load())
        return UInt8(s >> 4)

    def compute(mut self, var input: PPMImage) -> Optional[PPMImage]:
        var t0 = perf_counter_ns()
        comptime CHUNK = 8
        var w = input.width; var h = input.height
        if w <= 0 or h <= 0: return Optional[PPMImage]()

        var out = PPMImage(w, h)

        if w < 3 or h < 3:
            for y in range(h):
                for x in range(w):
                    (out.r_ptr() + y*w + x).store(self.border_pixel(input.r_ptr(), x, y, w, h))
                    (out.g_ptr() + y*w + x).store(self.border_pixel(input.g_ptr(), x, y, w, h))
                    (out.b_ptr() + y*w + x).store(self.border_pixel(input.b_ptr(), x, y, w, h))
            self.compute_time_ns += perf_counter_ns() - t0
            self.count += 1
            return out

        # Process each channel separately — stride-1, 9 vector loads per pixel group
        for ch in range(3):
            var ch_in  = input.r_ptr() if ch == 0 else (input.g_ptr() if ch == 1 else input.b_ptr())
            var ch_out = out.r_ptr()   if ch == 0 else (out.g_ptr()   if ch == 1 else out.b_ptr())

            for y in range(1, h - 1):
                var rm1 = ch_in + (y - 1) * w
                var r0  = ch_in +  y      * w
                var rp1 = ch_in + (y + 1) * w
                var dst = ch_out + y * w

                var x = 1
                while x + CHUNK <= w - 1:
                    # 9 vector loads — each is a true contiguous load of 8 uint8 values
                    var t00 = (rm1 + x - 1).load[width=CHUNK]().cast[DType.uint16]()
                    var t01 = (rm1 + x    ).load[width=CHUNK]().cast[DType.uint16]()
                    var t02 = (rm1 + x + 1).load[width=CHUNK]().cast[DType.uint16]()
                    var t10 = (r0  + x - 1).load[width=CHUNK]().cast[DType.uint16]()
                    var t11 = (r0  + x    ).load[width=CHUNK]().cast[DType.uint16]()
                    var t12 = (r0  + x + 1).load[width=CHUNK]().cast[DType.uint16]()
                    var t20 = (rp1 + x - 1).load[width=CHUNK]().cast[DType.uint16]()
                    var t21 = (rp1 + x    ).load[width=CHUNK]().cast[DType.uint16]()
                    var t22 = (rp1 + x + 1).load[width=CHUNK]().cast[DType.uint16]()

                    var res = (t00 + (t01 << 1) + t02
                             + (t10 << 1) + (t11 << 2) + (t12 << 1)
                             + t20 + (t21 << 1) + t22) >> 4

                    (dst + x).store(res.cast[DType.uint8]())
                    x += CHUNK

                while x < w - 1:
                    var xm1 = x - 1; var xp1 = x + 1
                    var v = Int((rm1 + xm1).load()) + (Int((rm1 + x).load()) << 1) + Int((rm1 + xp1).load())
                          + (Int((r0  + xm1).load()) << 1) + (Int((r0  + x).load()) << 2) + (Int((r0  + xp1).load()) << 1)
                          + Int((rp1 + xm1).load()) + (Int((rp1 + x).load()) << 1) + Int((rp1 + xp1).load())
                    (dst + x).store(UInt8(v >> 4))
                    x += 1

            # Borders
            for x in range(w):
                (ch_out + x).store(self.border_pixel(ch_in, x, 0, w, h))
                (ch_out + (h-1)*w + x).store(self.border_pixel(ch_in, x, h-1, w, h))
            for y in range(1, h - 1):
                (ch_out + y*w).store(self.border_pixel(ch_in, 0, y, w, h))
                (ch_out + y*w + w-1).store(self.border_pixel(ch_in, w-1, y, w, h))

        self.compute_time_ns += perf_counter_ns() - t0
        self.count += 1
        return out

    fn received_eos(mut self):
        var total_ms = Float64(Int(self.compute_time_ns)) / 1_000_000.0
        var avg_ms = total_ms / Float64(self.count) if self.count > 0 else 0.0
        print("    [" + Self.name + "] total=" + String(total_ms) + " ms | n=" + String(self.count) + " | avg/img=" + String(avg_ms) + " ms")

# ============================================================================
# Sharpen — V4: 5 true vector loads per channel
#
# Kernel: [0 -1 0; -1 5 -1; 0 -1 0]
# 5 taps: center, up, down, left, right — all contiguous 8-element loads
# ============================================================================
struct Sharpen(StageTrait):
    comptime kind = StageKind.TRANSFORM
    comptime InType = PPMImage
    comptime OutType = PPMImage
    comptime name = "Sharpen"
    var compute_time_ns: UInt
    var count: Int

    def __init__(out self):
        self.compute_time_ns = 0
        self.count = 0

    @always_inline
    def clamp255(self, v: Int) -> UInt8:
        if v < 0: return 0
        if v > 255: return 255
        return UInt8(v)

    @always_inline
    def border_pixel(
        self,
        ch_in: UnsafePointer[UInt8, MutExternalOrigin],
        x: Int, y: Int, w: Int, h: Int
    ) -> UInt8:
        var xm1 = x - 1
        if xm1 < 0: xm1 = 0
        var xp1 = x + 1
        if xp1 >= w: xp1 = w - 1
        var ym1 = y - 1
        if ym1 < 0: ym1 = 0
        var yp1 = y + 1
        if yp1 >= h: yp1 = h - 1
        var v = Int((ch_in + y   * w + x  ).load()) * 5 \
              - Int((ch_in + ym1 * w + x  ).load()) \
              - Int((ch_in + yp1 * w + x  ).load()) \
              - Int((ch_in + y   * w + xm1).load()) \
              - Int((ch_in + y   * w + xp1).load())
        return self.clamp255(v)

    @always_inline
    def sharpen_plane(
        self,
        ch_in:  UnsafePointer[UInt8, MutExternalOrigin],
        ch_out: UnsafePointer[UInt8, MutExternalOrigin],
        w: Int, h: Int
    ):
        comptime CHUNK = 8

        # Interior
        for y in range(1, h - 1):
            var rm  = ch_in  + (y - 1) * w
            var r0  = ch_in  +  y      * w
            var rp  = ch_in  + (y + 1) * w
            var dst = ch_out +  y      * w

            var x = 1
            while x + CHUNK <= w - 1:
                var tc  = (r0 + x    ).load[width=CHUNK]().cast[DType.int16]()
                var tup = (rm + x    ).load[width=CHUNK]().cast[DType.int16]()
                var tdn = (rp + x    ).load[width=CHUNK]().cast[DType.int16]()
                var tlt = (r0 + x - 1).load[width=CHUNK]().cast[DType.int16]()
                var trt = (r0 + x + 1).load[width=CHUNK]().cast[DType.int16]()
                var res = tc * 5 - tup - tdn - tlt - trt
                (dst + x).store(res.clamp(0, 255).cast[DType.uint8]())
                x += CHUNK

            while x < w - 1:
                var v = Int((r0 + x).load()) * 5 \
                      - Int((rm + x).load()) \
                      - Int((rp + x).load()) \
                      - Int((r0 + x - 1).load()) \
                      - Int((r0 + x + 1).load())
                (dst + x).store(self.clamp255(v))
                x += 1

        # Borders — 4 explicit loops, no h*w scan
        for x in range(w):
            (ch_out + x).store(self.border_pixel(ch_in, x, 0, w, h))
        var bottom = (h - 1) * w
        for x in range(w):
            (ch_out + bottom + x).store(self.border_pixel(ch_in, x, h - 1, w, h))
        for y in range(1, h - 1):
            (ch_out + y * w        ).store(self.border_pixel(ch_in, 0,     y, w, h))
            (ch_out + y * w + w - 1).store(self.border_pixel(ch_in, w - 1, y, w, h))

    def compute(mut self, var input: PPMImage) -> Optional[PPMImage]:
        var t0 = perf_counter_ns()
        var w = input.width; var h = input.height
        var out = PPMImage(w, h)

        self.sharpen_plane(input.r_ptr(), out.r_ptr(), w, h)
        self.sharpen_plane(input.g_ptr(), out.g_ptr(), w, h)
        self.sharpen_plane(input.b_ptr(), out.b_ptr(), w, h)

        self.compute_time_ns += perf_counter_ns() - t0
        self.count += 1
        return out

    fn received_eos(mut self):
        var total_ms = Float64(Int(self.compute_time_ns)) / 1_000_000.0
        var avg_ms = total_ms / Float64(self.count) if self.count > 0 else 0.0
        print("    [" + Self.name + "] total=" + String(total_ms) + " ms | n=" + String(self.count) + " | avg/img=" + String(avg_ms) + " ms")

# ============================================================================
# PassThrough
# ============================================================================
struct PassThrough(StageTrait):
    comptime kind = StageKind.TRANSFORM
    comptime InType = PPMImage
    comptime OutType = PPMImage
    comptime name = "PassThrough"
    def __init__(out self): pass
    def compute(mut self, var input: PPMImage) -> Optional[PPMImage]: return input
    def received_eos(mut self): pass

# ============================================================================
# ImageSink
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

    def __init__(out self):
        self.count = 0
        self.checksum_total = 0
        self.start_ns = 0
        self.count_ptr = alloc[Int](1)
        self.count_ptr[] = 0

    fn __del__(deinit self): pass

    def consume_element(mut self, var input: PPMImage):
        if self.count == 0: self.start_ns = perf_counter_ns()
        self.count += 1
        self.count_ptr[] = self.count

    fn received_eos(mut self):
        var elapsed_ns = perf_counter_ns() - self.start_ns
        var elapsed_ms = Float64(Int(elapsed_ns)) / 1_000_000.0
        var throughput: Float64 = 0.0
        if elapsed_ms > 0: throughput = Float64(self.count) / (elapsed_ms / 1000.0)
        print("  [Sink] Images received:", self.count,
              "| Checksum:", self.checksum_total,
              "| Time:", elapsed_ms, "ms",
              "| Throughput:", throughput, "img/s")
