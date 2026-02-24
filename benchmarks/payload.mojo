# Payload struct with configurable size for benchmarking
# The Size parameter determines the number of bytes in the payload
# Data is heap-allocated via UnsafePointer to enable TRUE move semantics:
#   - copy  -> allocates new memory + copies all bytes   (O(Size))
#   - move  -> just steals the pointer                   (O(1))

# Payload struct
struct Payload[Size: Int](ImplicitlyCopyable, Writable, Defaultable):
    var data_ptr: UnsafePointer[UInt8, MutExternalOrigin]

    # default constructor - zero-initialized
    fn __init__(out self):
        self.data_ptr = alloc[UInt8](Self.Size)
        for i in range(Self.Size):
            (self.data_ptr + i).init_pointee_move(UInt8(0))

    # constructor with a fill value
    fn __init__(out self, fill: UInt8):
        self.data_ptr = alloc[UInt8](Self.Size)
        for i in range(Self.Size):
            (self.data_ptr + i).init_pointee_move(fill)

    # copy constructor - allocates new heap memory and copies all bytes (O(Size))
    fn __copyinit__(out self, existing: Self):
        self.data_ptr = alloc[UInt8](Self.Size)
        for i in range(Self.Size):
            (self.data_ptr + i).init_pointee_copy((existing.data_ptr + i)[])

    # move constructor - just steals the pointer, no data copied (O(1))
    fn __moveinit__(out self, deinit existing: Self):
        self.data_ptr = existing.data_ptr

    # destructor - frees the heap-allocated memory
    fn __del__(deinit self):
        self.data_ptr.free()

    # writable implementation
    fn write_to[W: Writer](self, mut writer: W):
        writer.write("Payload[", String(Self.Size), "B]")
