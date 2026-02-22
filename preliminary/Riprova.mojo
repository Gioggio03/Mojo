from os.atomic import Atomic, Consistency
from time import sleep
from builtin.simd import Scalar

struct Cell[T: Movable & Copyable & Defaultable](Movable):
    var sequence: Atomic[DType.int64]
    var data: Self.T

    fn __init__(out self, seq: Int):
        self.sequence = Atomic[DType.int64](seq)
        self.data = Self.T()

    fn __moveinit__(out self, deinit existing: Self):
        var val = existing.sequence.load()
        self.sequence = Atomic[DType.int64](val)
        self.data = existing.data^

struct MPMCQueue[T: Movable & Copyable & Defaultable]:
    comptime CellPointer = UnsafePointer[Cell[Self.T], MutExternalOrigin]

    var buffer: Self.CellPointer
    var size: Int
    var mask: Int
    var enqueue_pos: Atomic[DType.int64]
    var dequeue_pos: Atomic[DType.int64]

    fn __init__(out self, size: Int):
        self.size = size
        self.mask = size - 1
        self.buffer = alloc[Cell[Self.T]](self.size)
        self.enqueue_pos = Atomic[DType.int64](0)
        self.dequeue_pos = Atomic[DType.int64](0)
        for i in range(self.size):
            (self.buffer + i).init_pointee_move(Cell[Self.T](i))

    fn push(mut self, item: Self.T) -> Bool:
        var pw: Int
        var seq: Int
        var bk: Int = 1

        while True:
            pw = Int(self.enqueue_pos.load())
            var cell_ptr = self.buffer + (pw & self.mask)
            seq = Int(cell_ptr[].sequence.load())

            if pw == seq:
                var expected = Scalar[DType.int64](pw)
                var desired = Scalar[DType.int64](pw + 1)
                if self.enqueue_pos.compare_exchange(expected, desired):
                    cell_ptr[].data = item.copy()
                    Atomic[DType.int64].store(UnsafePointer(to=cell_ptr[].sequence.value), pw + 1)
                    return True
                for _ in range(bk): pass
                bk = (bk << 1) if (bk << 1) < 1024 else 1024
            elif pw > seq:
                return False

    fn pop(mut self) -> Self.T:
        var pr: Int
        var seq: Int
        var bk: Int = 1
        var bk_max: Int = 1024

        while True:
            pr = Int(self.dequeue_pos.load())
            var cell_ptr = self.buffer + (pr & self.mask)
            seq = Int(cell_ptr[].sequence.load())

            var diff = seq - (pr + 1)

            if diff == 0:
                var expected = Scalar[DType.int64](pr)
                var desired = Scalar[DType.int64](pr + 1)
                if self.dequeue_pos.compare_exchange(expected, desired):
                    var item = cell_ptr[].data.copy()
                    Atomic[DType.int64].store(UnsafePointer(to=cell_ptr[].sequence.value), pr + self.size)
                    return item^
                for _ in range(bk): pass
                bk = (bk << 1) if (bk << 1) < bk_max else bk_max
            elif diff < 0:
                pass

    fn __del__(deinit self):
        for i in range(self.size):
            (self.buffer + i).destroy_pointee()
        self.buffer.free()
        print("Memoria della coda liberata correttamente.")

fn test_streaming():
    var queue = MPMCQueue[Int](size=1024)
    _ = queue.push(42)

    var received_data = queue.pop()
    if received_data == 42:
        print("Successo! Dato trasferito.")

fn main():
    test_streaming()
