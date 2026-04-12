# PPMImage struct — PLANAR layout for SIMD-friendly access
#
# V4 change vs V3: instead of interleaved RGB (RGBRGB...), pixels are stored
# in three contiguous planes:
#   [R0 R1 R2 ... R(W*H-1) | G0 G1 ... G(W*H-1) | B0 B1 ... B(W*H-1)]
#
# Plane access:
#   R plane: data_ptr + 0
#   G plane: data_ptr + width * height
#   B plane: data_ptr + 2 * width * height
#
# SIMD benefit: consecutive pixels of the same channel are now adjacent in memory
# (stride-1 access), allowing LLVM to emit vector loads (vmovdqu) instead of
# stride-3 gathers. This enables full auto-vectorization in C++ and more efficient
# SIMD in Mojo compared to the interleaved layout used in V2/V3.

from std.memory import memcpy, memset

struct PPMImage(ImplicitlyCopyable, Writable, Defaultable):
    var width: Int
    var height: Int
    var data_ptr: UnsafePointer[UInt8, MutExternalOrigin]  # W*H*3 bytes, planar

    fn __init__(out self):
        self.width = 0
        self.height = 0
        self.data_ptr = UnsafePointer[UInt8, MutExternalOrigin]()

    def __init__(out self, width: Int, height: Int):
        self.width = width
        self.height = height
        var num_bytes = width * height * 3
        self.data_ptr = alloc[UInt8](num_bytes)
        memset(self.data_ptr, UInt8(0), num_bytes)

    def __init__(out self, width: Int, height: Int, fill: UInt8):
        self.width = width
        self.height = height
        var num_bytes = width * height * 3
        self.data_ptr = alloc[UInt8](num_bytes)
        memset(self.data_ptr, fill, num_bytes)

    # Copy constructor — deep copy of pixel data
    fn __copyinit__(out self, existing: Self):
        self.width = existing.width
        self.height = existing.height
        var num_bytes = self.width * self.height * 3
        if num_bytes > 0:
            self.data_ptr = alloc[UInt8](num_bytes)
            memcpy(dest=self.data_ptr, src=existing.data_ptr, count=num_bytes)
        else:
            self.data_ptr = UnsafePointer[UInt8, MutExternalOrigin]()

    # Move constructor — steal pointer O(1)
    fn __moveinit__(out self, deinit existing: Self):
        self.width = existing.width
        self.height = existing.height
        self.data_ptr = existing.data_ptr

    fn __del__(deinit self):
        if self.data_ptr:
            self.data_ptr.free()

    @always_inline
    def num_bytes(self) -> Int:
        return self.width * self.height * 3

    @always_inline
    def plane_size(self) -> Int:
        return self.width * self.height

    # Planar channel pointers
    @always_inline
    def r_ptr(self) -> UnsafePointer[UInt8, MutExternalOrigin]:
        return self.data_ptr

    @always_inline
    def g_ptr(self) -> UnsafePointer[UInt8, MutExternalOrigin]:
        return self.data_ptr + self.width * self.height

    @always_inline
    def b_ptr(self) -> UnsafePointer[UInt8, MutExternalOrigin]:
        return self.data_ptr + 2 * self.width * self.height

    @always_inline
    def get_r(self, x: Int, y: Int) -> UInt8:
        return (self.r_ptr() + y * self.width + x).load()

    @always_inline
    def get_g(self, x: Int, y: Int) -> UInt8:
        return (self.g_ptr() + y * self.width + x).load()

    @always_inline
    def get_b(self, x: Int, y: Int) -> UInt8:
        return (self.b_ptr() + y * self.width + x).load()

    @always_inline
    def set_pixel(mut self, x: Int, y: Int, r: UInt8, g: UInt8, b: UInt8):
        var idx = y * self.width + x
        (self.r_ptr() + idx).store(r)
        (self.g_ptr() + idx).store(g)
        (self.b_ptr() + idx).store(b)

    @always_inline
    def checksum(self) -> UInt64:
        var total: UInt64 = 0
        var n = self.num_bytes()
        for i in range(n):
            total += (self.data_ptr + i)[].cast[DType.uint64]()
        return total

    def write_to[W: Writer](self, mut writer: W):
        writer.write("PPMImage[", self.width, "x", self.height, "] (planar)")

    @staticmethod
    def create_gradient(width: Int, height: Int) -> PPMImage:
        var img = PPMImage(width, height)
        for y in range(height):
            for x in range(width):
                var r = UInt8((x * 255) // max(width - 1, 1))
                var g = UInt8((y * 255) // max(height - 1, 1))
                var b = UInt8(((x + y) * 127) // max(width + height - 2, 1))
                img.set_pixel(x, y, r, g, b)
        return img
