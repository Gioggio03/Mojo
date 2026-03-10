# PPMImage struct — raw pixel buffer for image processing pipeline
# Satisfies MessageTrait (= ImplicitlyCopyable & Writable) required by MoStream communicators.
# Data is heap-allocated via UnsafePointer for efficient move semantics.

from memory import memcpy

# PPMImage struct
struct PPMImage(ImplicitlyCopyable, Writable, Defaultable):
    var width: Int
    var height: Int
    var data_ptr: UnsafePointer[UInt8, MutExternalOrigin]  # RGB pixel data (W*H*3 bytes)

    # default constructor — 0x0 image, null pointer
    fn __init__(out self):
        self.width = 0
        self.height = 0
        self.data_ptr = UnsafePointer[UInt8, MutExternalOrigin]()

    # constructor with dimensions — zero-initialized pixel buffer
    fn __init__(out self, width: Int, height: Int):
        self.width = width
        self.height = height
        var num_bytes = width * height * 3
        self.data_ptr = alloc[UInt8](num_bytes)
        for i in range(num_bytes):
            (self.data_ptr + i).init_pointee_move(UInt8(0))

    # constructor with dimensions and fill value
    fn __init__(out self, width: Int, height: Int, fill: UInt8):
        self.width = width
        self.height = height
        var num_bytes = width * height * 3
        self.data_ptr = alloc[UInt8](num_bytes)
        for i in range(num_bytes):
            (self.data_ptr + i).init_pointee_move(fill)

    # copy constructor — deep copy of pixel data (O(W*H*3))
    fn __copyinit__(out self, existing: Self):
        self.width = existing.width
        self.height = existing.height
        var num_bytes = self.width * self.height * 3
        if num_bytes > 0:
            self.data_ptr = alloc[UInt8](num_bytes)
            memcpy(dest=self.data_ptr, src=existing.data_ptr, count=num_bytes)
        else:
            self.data_ptr = UnsafePointer[UInt8, MutExternalOrigin]()

    # move constructor — steal pointer (O(1))
    fn __moveinit__(out self, deinit existing: Self):
        self.width = existing.width
        self.height = existing.height
        self.data_ptr = existing.data_ptr

    # destructor — free heap memory
    fn __del__(deinit self):
        if self.data_ptr:
            self.data_ptr.free()

    # total number of bytes in the pixel buffer
    fn num_bytes(self) -> Int:
        return self.width * self.height * 3

    # get pixel value at (x, y) — returns (R, G, B)
    fn get_r(self, x: Int, y: Int) -> UInt8:
        var idx = (y * self.width + x) * 3
        return (self.data_ptr + idx)[]

    fn get_g(self, x: Int, y: Int) -> UInt8:
        var idx = (y * self.width + x) * 3 + 1
        return (self.data_ptr + idx)[]

    fn get_b(self, x: Int, y: Int) -> UInt8:
        var idx = (y * self.width + x) * 3 + 2
        return (self.data_ptr + idx)[]

    # set pixel value at (x, y)
    fn set_pixel(mut self, x: Int, y: Int, r: UInt8, g: UInt8, b: UInt8):
        var idx = (y * self.width + x) * 3
        (self.data_ptr + idx)[] = r
        (self.data_ptr + idx + 1)[] = g
        (self.data_ptr + idx + 2)[] = b

    # set raw byte at a given index
    fn set_byte(mut self, index: Int, value: UInt8):
        (self.data_ptr + index)[] = value

    # get raw byte at a given index
    fn get_byte(self, index: Int) -> UInt8:
        return (self.data_ptr + index)[]

    # compute a simple checksum (sum of all bytes) for validation
    fn checksum(self) -> UInt64:
        var total: UInt64 = 0
        var n = self.num_bytes()
        for i in range(n):
            total += (self.data_ptr + i)[].cast[DType.uint64]()
        return total

    # Writable implementation
    fn write_to[W: Writer](self, mut writer: W):
        writer.write("PPMImage[", self.width, "x", self.height, "]")

    # create a gradient test image (for synthetic tests without file I/O)
    @staticmethod
    fn create_gradient(width: Int, height: Int) -> PPMImage:
        var img = PPMImage(width, height)
        for y in range(height):
            for x in range(width):
                var r = UInt8((x * 255) // max(width - 1, 1))
                var g = UInt8((y * 255) // max(height - 1, 1))
                var b = UInt8(((x + y) * 127) // max(width + height - 2, 1))
                img.set_pixel(x, y, r, g, b)
        return img
