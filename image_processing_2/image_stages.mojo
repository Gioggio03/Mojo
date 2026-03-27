# Image processing pipeline stages using PPMImage
# Each stage satisfies StageTrait from MoStream

from collections import Optional
from MoStream.communicator import MessageTrait
from MoStream.stage import StageKind, StageTrait
from ppm_image import PPMImage
from time import perf_counter_ns

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
        var w = input.width
        var h = input.height
        var out = PPMImage(w, h)
        for y in range(h):
            for x in range(w):
                var r = input.get_r(x, y).cast[DType.uint32]()
                var g = input.get_g(x, y).cast[DType.uint32]()
                var b = input.get_b(x, y).cast[DType.uint32]()
                # Fixed-point approximation: (77*R + 150*G + 29*B) >> 8
                var gray = UInt8(((r * 77 + g * 150 + b * 29) >> 8).cast[DType.uint8]())
                out.set_pixel(x, y, gray, gray, gray)
        self.compute_time_ns += perf_counter_ns() - t0
        return out

    fn received_eos(mut self):
        print("    [" + Self.name + "] compute time: " + String(Float64(Int(self.compute_time_ns))/1_000_000.0) + " ms")

# ============================================================================
# GaussianBlur — TRANSFORM stage
# Applies a 3x3 Gaussian blur kernel:
#   [1 2 1]
#   [2 4 2]  / 16
#   [1 2 1]
# ============================================================================
struct GaussianBlur(StageTrait):
    comptime kind = StageKind.TRANSFORM
    comptime InType = PPMImage
    comptime OutType = PPMImage
    comptime name = "GaussianBlur"
    var compute_time_ns: UInt

    fn __init__(out self):
        self.compute_time_ns = 0

    fn compute(mut self, var input: PPMImage) raises -> Optional[PPMImage]:
        var t0 = perf_counter_ns()
        var w = input.width
        var h = input.height
        var out = PPMImage(w, h)
        for y in range(h):
            for x in range(w):
                # process each channel
                var sum_r: UInt32 = 0
                var sum_g: UInt32 = 0
                var sum_b: UInt32 = 0
                # 3x3 kernel iteration
                for ky in range(-1, 2):
                    for kx in range(-1, 2):
                        var nx = x + kx
                        var ny = y + ky
                        # clamp to image bounds
                        if nx < 0:
                            nx = 0
                        if nx >= w:
                            nx = w - 1
                        if ny < 0:
                            ny = 0
                        if ny >= h:
                            ny = h - 1
                        # Gaussian weight
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
                out.set_pixel(x, y, (sum_r >> 4).cast[DType.uint8](), (sum_g >> 4).cast[DType.uint8](), (sum_b >> 4).cast[DType.uint8]())
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

    fn compute(mut self, var input: PPMImage) raises -> Optional[PPMImage]:
        var t0 = perf_counter_ns()
        var w = input.width
        var h = input.height
        var out = PPMImage(w, h)
        for y in range(h):
            for x in range(w):
                var sum_r: Int32 = 0
                var sum_g: Int32 = 0
                var sum_b: Int32 = 0
                # Apply sharpening kernel
                # Center pixel * 5
                sum_r += input.get_r(x, y).cast[DType.int32]() * 5
                sum_g += input.get_g(x, y).cast[DType.int32]() * 5
                sum_b += input.get_b(x, y).cast[DType.int32]() * 5
                # 4-connected neighbors * -1
                for i in range(4):
                    var nx = x
                    var ny = y
                    if i == 0:
                        ny = y - 1
                    elif i == 1:
                        ny = y + 1
                    elif i == 2:
                        nx = x - 1
                    else:
                        nx = x + 1
                    # clamp
                    if nx < 0:
                        nx = 0
                    if nx >= w:
                        nx = w - 1
                    if ny < 0:
                        ny = 0
                    if ny >= h:
                        ny = h - 1
                    sum_r -= input.get_r(nx, ny).cast[DType.int32]()
                    sum_g -= input.get_g(nx, ny).cast[DType.int32]()
                    sum_b -= input.get_b(nx, ny).cast[DType.int32]()
                # Clamp to 0-255
                if sum_r < 0:
                    sum_r = 0
                if sum_r > 255:
                    sum_r = 255
                if sum_g < 0:
                    sum_g = 0
                if sum_g > 255:
                    sum_g = 255
                if sum_b < 0:
                    sum_b = 0
                if sum_b > 255:
                    sum_b = 255
                out.set_pixel(x, y, sum_r.cast[DType.uint8](), sum_g.cast[DType.uint8](), sum_b.cast[DType.uint8]())
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
