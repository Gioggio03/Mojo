# Payload struct with configurable size for benchmarking
# The Size parameter determines the number of bytes in the payload

struct Payload[Size: Int](ImplicitlyCopyable, Writable, Defaultable):
    var data: InlineArray[UInt8, Self.Size]

    # default constructor - zero-initialized
    fn __init__(out self):
        self.data = InlineArray[UInt8, Self.Size](fill=0)

    # constructor with a fill value
    fn __init__(out self, fill: UInt8):
        self.data = InlineArray[UInt8, Self.Size](fill=fill)

    # implicit copy constructor (required by ImplicitlyCopyable)
    fn __copyinit__(out self, existing: Self):
        self.data = existing.data.copy()

    # Writable implementation
    fn write_to[W: Writer](self, mut writer: W):
        writer.write("Payload[", String(Self.Size), "B]")
