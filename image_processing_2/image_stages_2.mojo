# Image processing pipeline stages using PPMImage
# Each stage satisfies StageTrait from MoStream

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
# Generates images for a fixed duration (default 60 seconds).
# Images are created synthetically as gradients of the given size.
# ============================================================================
struct TimedImageSource[ImgW: Int, ImgH: Int, DurationSec: Int = 60](StageTrait):
    comptime kind = StageKind.SOURCE
    comptime InType = PPMImage
    comptime OutType = PPMImage
    comptime name = "TimedImageSource"
    var count: Int
    var pool: PPMImage  # single gradient image used as template
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
        # return a copy of the pooled image
        return self.pool

    fn received_eos(mut self):
        pass

# ============================================================================
# ImageSource — SOURCE stage (count-based, for source baseline measurement)
# Generates images from a pre-loaded pool, cycling through them N times.
# Images are created synthetically as gradients of the given size.
# ============================================================================
struct ImageSource[ImgW: Int, ImgH: Int, NumMessages: Int](StageTrait):
    comptime kind = StageKind.SOURCE
    comptime InType = PPMImage
    comptime OutType = PPMImage
    comptime name = "ImageSource"
    var count: Int
    var pool: PPMImage  # single gradient image used as template

    fn __init__(out self):
        self.count = 0
        self.pool = PPMImage.create_gradient(Self.ImgW, Self.ImgH)

    fn next_element(mut self) raises -> Optional[PPMImage]:
        if self.count >= Self.NumMessages:
            return None
        self.count += 1
        # return a copy of the pooled image
        return self.pool

    fn received_eos(mut self):
        pass

# ============================================================================
# Grayscale — TRANSFORM stage
# Converts RGB image to grayscale using luminance formula:
#   gray = 0.299*R + 0.587*G + 0.114*B
# Output is still 3-channel (R=G=B=gray) to maintain PPMImage format.
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
        self.compute_time_ns += perf_counter_ns() - t0
        return out

    fn received_eos(mut self):
        print("    [" + Self.name + "] compute time: " + String(Float64(Int(self.compute_time_ns))/1_000_000.0) + " ms")

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
        if v < lo:
            return lo
        if v > hi:
            return hi
        return v

    @always_inline
    fn load_u8(self, base: UnsafePointer[UInt8], i: Int) -> Int:
        return Int((base + i).load())

    @always_inline
    fn blur_border_pixel(
        self,
        in_ptr: UnsafePointer[UInt8],
        x: Int,
        y: Int,
        width: Int,
        height: Int,
    ) -> RGB3:
        var sr: Int = 0
        var sg: Int = 0
        var sb: Int = 0

        for ky in range(-1, 2):
            var yy = self.clamp(y + ky, 0, height - 1)
            for kx in range(-1, 2):
                var xx = self.clamp(x + kx, 0, width - 1)
                var i = self.idx3(xx, yy, width)

                var w: Int = 1
                if ky == 0:
                    w = w << 1
                if kx == 0:
                    w = w << 1

                sr += w * self.load_u8(in_ptr, i)
                sg += w * self.load_u8(in_ptr, i + 1)
                sb += w * self.load_u8(in_ptr, i + 2)

        return RGB3(sr >> 4, sg >> 4, sb >> 4)

    fn compute(mut self, var input: PPMImage) raises -> Optional[PPMImage]:
        var t0 = perf_counter_ns()

        var width = input.width
        var height = input.height

        if width <= 0 or height <= 0:
            return Optional[PPMImage]()

        var out = PPMImage(width, height)

        var in_ptr = input.data_ptr

        # Small images: use only the slow border-safe path.
        if width < 3 or height < 3:
            for y in range(height):
                for x in range(width):
                    var rgb = self.blur_border_pixel(in_ptr, x, y, width, height)
                    out.set_pixel(
                        x,
                        y,
                        UInt8(rgb.r),
                        UInt8(rgb.g),
                        UInt8(rgb.b),
                    )
            return out

        #
        # Fast interior path:
        # no ky/kx loops, no clamps
        #
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
                    self.load_u8(in_ptr, i00) +
                    (self.load_u8(in_ptr, i01) << 1) +
                    self.load_u8(in_ptr, i02) +
                    (self.load_u8(in_ptr, i10) << 1) +
                    (self.load_u8(in_ptr, i11) << 2) +
                    (self.load_u8(in_ptr, i12) << 1) +
                    self.load_u8(in_ptr, i20) +
                    (self.load_u8(in_ptr, i21) << 1) +
                    self.load_u8(in_ptr, i22)

                var g =
                    self.load_u8(in_ptr, i00 + 1) +
                    (self.load_u8(in_ptr, i01 + 1) << 1) +
                    self.load_u8(in_ptr, i02 + 1) +
                    (self.load_u8(in_ptr, i10 + 1) << 1) +
                    (self.load_u8(in_ptr, i11 + 1) << 2) +
                    (self.load_u8(in_ptr, i12 + 1) << 1) +
                    self.load_u8(in_ptr, i20 + 1) +
                    (self.load_u8(in_ptr, i21 + 1) << 1) +
                    self.load_u8(in_ptr, i22 + 1)

                var b =
                    self.load_u8(in_ptr, i00 + 2) +
                    (self.load_u8(in_ptr, i01 + 2) << 1) +
                    self.load_u8(in_ptr, i02 + 2) +
                    (self.load_u8(in_ptr, i10 + 2) << 1) +
                    (self.load_u8(in_ptr, i11 + 2) << 2) +
                    (self.load_u8(in_ptr, i12 + 2) << 1) +
                    self.load_u8(in_ptr, i20 + 2) +
                    (self.load_u8(in_ptr, i21 + 2) << 1) +
                    self.load_u8(in_ptr, i22 + 2)

                out.set_pixel(
                    x,
                    y,
                    UInt8(r >> 4),
                    UInt8(g >> 4),
                    UInt8(b >> 4),
                )

        #
        # Borders: slower safe path
        #
        for x in range(width):
            var top_rgb = self.blur_border_pixel(in_ptr, x, 0, width, height)
            out.set_pixel(
                x,
                0,
                UInt8(top_rgb.r),
                UInt8(top_rgb.g),
                UInt8(top_rgb.b),
            )

            var bot_rgb = self.blur_border_pixel(in_ptr, x, height - 1, width, height)
            out.set_pixel(
                x,
                height - 1,
                UInt8(bot_rgb.r),
                UInt8(bot_rgb.g),
                UInt8(bot_rgb.b),
            )

        for y in range(1, height - 1):
            var left_rgb = self.blur_border_pixel(in_ptr, 0, y, width, height)
            out.set_pixel(
                0,
                y,
                UInt8(left_rgb.r),
                UInt8(left_rgb.g),
                UInt8(left_rgb.b),
            )

            var right_rgb = self.blur_border_pixel(in_ptr, width - 1, y, width, height)
            out.set_pixel(
                width - 1,
                y,
                UInt8(right_rgb.r),
                UInt8(right_rgb.g),
                UInt8(right_rgb.b),
            )

        self.compute_time_ns += perf_counter_ns() - t0
        return out

    fn received_eos(mut self):
        print("    [" + Self.name + "] compute time: " + String(Float64(Int(self.compute_time_ns))/1_000_000.0) + " ms")

# ============================================================================
# Sharpen — TRANSFORM stage
# Applies a 3x3 sharpening kernel:
#   [ 0 -1  0]
#   [-1  5 -1]
#   [ 0 -1  0]
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
        var w = input.width
        var h = input.height
        var out = PPMImage(w, h)
        var in_ptr  = input.data_ptr
        var out_ptr = out.data_ptr

        # Fast interior path: y in [1, h-2], x in [1, w-2] — no clamp needed
        for y in range(1, h - 1):
            for x in range(1, w - 1):
                var c  = (y * w + x) * 3
                var up = ((y - 1) * w + x) * 3
                var dn = ((y + 1) * w + x) * 3
                var lt = (y * w + (x - 1)) * 3
                var rt = (y * w + (x + 1)) * 3
                for ch in range(3):
                    var v = self.load_px(in_ptr, c  + ch) * 5 \
                          - self.load_px(in_ptr, up + ch) \
                          - self.load_px(in_ptr, dn + ch) \
                          - self.load_px(in_ptr, lt + ch) \
                          - self.load_px(in_ptr, rt + ch)
                    (out_ptr + c + ch).store(self.clamp255(v))

        # Border path: pixels on the 4 edges — with clamp on neighbors
        for y in range(h):
            for x in range(w):
                if x != 0 and x != w - 1 and y != 0 and y != h - 1:
                    continue
                var sum_r = self.load_px(in_ptr, (y * w + x) * 3    ) * 5
                var sum_g = self.load_px(in_ptr, (y * w + x) * 3 + 1) * 5
                var sum_b = self.load_px(in_ptr, (y * w + x) * 3 + 2) * 5
                var ny: Int
                var nx: Int
                # up
                ny = y - 1
                if ny < 0: ny = 0
                sum_r -= self.load_px(in_ptr, (ny * w + x) * 3    )
                sum_g -= self.load_px(in_ptr, (ny * w + x) * 3 + 1)
                sum_b -= self.load_px(in_ptr, (ny * w + x) * 3 + 2)
                # down
                ny = y + 1
                if ny >= h: ny = h - 1
                sum_r -= self.load_px(in_ptr, (ny * w + x) * 3    )
                sum_g -= self.load_px(in_ptr, (ny * w + x) * 3 + 1)
                sum_b -= self.load_px(in_ptr, (ny * w + x) * 3 + 2)
                # left
                nx = x - 1
                if nx < 0: nx = 0
                sum_r -= self.load_px(in_ptr, (y * w + nx) * 3    )
                sum_g -= self.load_px(in_ptr, (y * w + nx) * 3 + 1)
                sum_b -= self.load_px(in_ptr, (y * w + nx) * 3 + 2)
                # right
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
# Brightness — TRANSFORM stage
# Adjusts brightness by adding a fixed offset to all channels.
# Values are clamped to [0, 255].
# ============================================================================
struct Brightness[Offset: Int](StageTrait):
    comptime kind = StageKind.TRANSFORM
    comptime InType = PPMImage
    comptime OutType = PPMImage
    comptime name = "Brightness"

    fn __init__(out self):
        pass

    fn compute(mut self, var input: PPMImage) raises -> Optional[PPMImage]:
        var w = input.width
        var h = input.height
        var num_bytes = w * h * 3
        var out = PPMImage(w, h)
        for i in range(num_bytes):
            var val = input.get_byte(i).cast[DType.int32]() + Int32(Self.Offset)
            if val < 0:
                val = 0
            if val > 255:
                val = 255
            out.set_byte(i, val.cast[DType.uint8]())
        return out

    fn received_eos(mut self):
        pass

# ============================================================================
# PassThrough — TRANSFORM stage (no-op)
# Forwards images without any processing.
# Used to measure ideal source bandwidth: Source -> PassThrough -> Sink
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
# Collects processed images, counts them, computes checksum for validation,
# and reports timing/throughput at end of stream.
# ============================================================================
struct ImageSink(StageTrait):
    comptime kind = StageKind.SINK
    comptime InType = PPMImage
    comptime OutType = PPMImage
    comptime name = "ImageSink"
    var count: Int
    var checksum_total: UInt64
    var start_ns: UInt
    # Heap-allocated counter so the caller can read the final count after
    # pipeline.run() moves this sink internally.
    var count_ptr: UnsafePointer[Int, MutExternalOrigin]

    fn __init__(out self):
        self.count = 0
        self.checksum_total = 0
        self.start_ns = 0
        self.count_ptr = alloc[Int](1)
        self.count_ptr[] = 0

    fn __del__(deinit self):
        # NOTE: caller must call count_ptr.free() after reading if needed;
        # here we just destroy the pointee but do NOT free the allocation so
        # callers that saved the pointer before the pipeline move can still read.
        pass

    fn consume_element(mut self, var input: PPMImage) raises:
        if self.count == 0:
            self.start_ns = perf_counter_ns()
        self.count += 1
        self.count_ptr[] = self.count
        # self.checksum_total += input.checksum()

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
