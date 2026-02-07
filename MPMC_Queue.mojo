from os.atomic import Atomic, Consistency, fence
from time import sleep
from builtin.simd import Scalar
from sys.terminate import exit

struct Cell[T: Movable & Copyable & Defaultable](Movable):
    var sequence: Atomic[DType.uint64]
    var data: Self.T

    fn __init__(out self, seq: UInt64):
        self.sequence = Atomic[DType.uint64](seq)
        self.data = Self.T()

    fn __moveinit__(out self, deinit existing: Self):
        var val = existing.sequence.load()
        self.sequence = Atomic[DType.uint64](val)
        self.data = existing.data^

struct MPMCQueue[T: Movable & Copyable & Defaultable]:
    comptime CellPointer = UnsafePointer[Cell[Self.T], MutExternalOrigin]
    comptime BACKOFF_MAX = 1024
    comptime BACKOFF_MIN = 128

    var buffer: Self.CellPointer
    var size: Int
    var mask: Int
    var enqueue_pos: Atomic[DType.uint64]
    var dequeue_pos: Atomic[DType.uint64]

    fn __init__(out self, size: Int):
        if not ((size >= 2) and (size & (size - 1)) == 0):
            print("MPMC queue needs size to be a power of 2 and at least 2.")
            exit(1)
        self.size = size
        self.mask = size - 1
        self.buffer = alloc[Cell[Self.T]](self.size)
        self.enqueue_pos = Atomic[DType.uint64](0)
        self.dequeue_pos = Atomic[DType.uint64](0)
        for i in range(self.size):
            (self.buffer + i).init_pointee_move(Cell[Self.T](i))

    fn push(mut self, var item: Self.T) -> Bool:
        var pw: UInt64
        var seq: UInt64
        var bk: UInt64 = Self.BACKOFF_MIN

        while True:
            pw = self.enqueue_pos.load[ordering=Consistency.MONOTONIC]()
            var cell_ptr = self.buffer + (pw & self.mask)
            seq = cell_ptr[].sequence.load[ordering=Consistency.ACQUIRE]()

            if pw == seq:
                if self.enqueue_pos.compare_exchange[failure_ordering=Consistency.MONOTONIC, success_ordering=Consistency.MONOTONIC](pw, pw + 1):
                    cell_ptr[].data = item^
                    Atomic[DType.uint64].store[ordering=Consistency.RELEASE](UnsafePointer(to=cell_ptr[].sequence.value), pw + 1)
                    return True
                for _ in range(bk):
                    #fence[ordering=Consistency.SEQUENTIAL]() # I am not sure of this, I suppose however that this for loop is compiled out
                    pass
                bk <<= 1
                bk &= Self.BACKOFF_MAX
                # bk = (bk << 1) if (bk << 1) < Self.BACKOFF_MAX else Self.BACKOFF_MAX
            elif pw > seq:
                return False

    fn pop(mut self) -> Optional[Self.T]:
        var pr: UInt64
        var seq: UInt64
        var bk: UInt64 = Self.BACKOFF_MIN

        while True:
            pr = self.dequeue_pos.load[ordering=Consistency.MONOTONIC]()
            var cell_ptr = self.buffer + (pr & self.mask)
            seq = cell_ptr[].sequence.load[ordering=Consistency.ACQUIRE]()
            var diff = seq - (pr + 1)
            if diff == 0:
                if self.dequeue_pos.compare_exchange[failure_ordering=Consistency.MONOTONIC, success_ordering=Consistency.MONOTONIC](pr, pr + 1):
                    var item = cell_ptr[].data.copy()
                    Atomic[DType.uint64].store[ordering=Consistency.RELEASE](UnsafePointer(to=cell_ptr[].sequence.value), pr + self.mask + 1)
                    return Optional(item^)
                for _ in range(bk):
                    #fence[ordering=Consistency.SEQUENTIAL]() # I am not sure of this, I suppose however that this for loop is compiled out
                    return Optional[Self.T](None)
                bk <<= 1
                bk &= Self.BACKOFF_MAX
            elif diff < 0:
                pass

    fn __del__(deinit self):
        for i in range(self.size):
            (self.buffer + i).destroy_pointee()
        self.buffer.free()
        print("MPMCQueue deallocated correctly!")

fn test_streaming():
    var queue = MPMCQueue[Int](size=1024)
    resultPop = queue.push(42)
    if not resultPop:
        print("Failed to push data into the queue: the queue seems full!")
        return

    var received_data = queue.pop()
    if (not received_data):
        print("Failed to pop data from the queue: the queue seems empty!")
        return
    if received_data.value() == 42:
        print("Success! Data transferred.")
    else:
        print("Failure! Data mismatch.")

fn main():
    test_streaming()
