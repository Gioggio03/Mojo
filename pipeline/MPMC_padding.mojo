# MPMC queue by Dmitry Vyukov with padding

from os.atomic import Atomic, Consistency, fence
from time import sleep
from sys.info import size_of
from sys.terminate import exit

# Struct to add padding to an atomic variable to avoid false sharing between producer and consumer
struct PaddedAtomicU64:
    comptime CACHE_LINE_SIZE_BYTES = 64
    comptime PAD_BYTES = Self.CACHE_LINE_SIZE_BYTES - size_of[Atomic[DType.uint64]]()
    var atomicVal: Atomic[DType.uint64]
    var pad: InlineArray[UInt8, Self.PAD_BYTES]

    # constructor
    fn __init__(out self, initial: UInt64):
        self.atomicVal = Atomic[DType.uint64](initial)
        self.pad = InlineArray[UInt8, Self.PAD_BYTES](uninitialized=True)

# Cell struct used in the MPMC queue, containing a sequence number and the actual data (one slot of the queue)
struct Cell[T: Copyable & Defaultable](Movable):
    var sequence: Atomic[DType.uint64]
    var data: Self.T

    # constructor
    fn __init__(out self, seq: UInt64):
        self.sequence = Atomic[DType.uint64](seq)
        self.data = Self.T()

    # move constructor
    fn __moveinit__(out self, deinit existing: Self):
        var val = existing.sequence.load()
        self.sequence = Atomic[DType.uint64](val)
        self.data = existing.data^

# MPMC queue implementation based the algorithm by Dmitry Vyukov
#    (https://www.1024cores.net/home/lock-free-algorithms/queues/bounded-mpmc-queue)
struct MPMCQueue[T: Copyable & Defaultable](Movable):
    comptime CellPointer = UnsafePointer[Cell[Self.T], MutExternalOrigin]
    comptime BACKOFF_MIN = 128
    comptime BACKOFF_MAX = 1024
    var buffer: Self.CellPointer
    var size: Int
    var mask: Int
    var enqueue_pos: PaddedAtomicU64
    var dequeue_pos: PaddedAtomicU64

    # constructor
    fn __init__(out self, size: Int):
        if not ((size >= 2) and (size & (size - 1)) == 0):
            print("Error: MPMC queues need size to be a power of 2 and at least 2.")
            exit(1)
        self.size = size
        self.mask = size - 1
        self.buffer = alloc[Cell[Self.T]](self.size)
        self.enqueue_pos = PaddedAtomicU64(0)
        self.dequeue_pos = PaddedAtomicU64(0)
        for i in range(self.size):
            (self.buffer + i).init_pointee_move(Cell[Self.T](i))

    # move constructor
    fn __moveinit__(out self, deinit existing: Self):
        self.buffer = existing.buffer
        self.size = existing.size
        self.mask = existing.mask
        self.enqueue_pos = PaddedAtomicU64(0)
        self.dequeue_pos = PaddedAtomicU64(0)

    # destructor
    fn __del__(deinit self):
        for i in range(self.size):
            (self.buffer + i).destroy_pointee()
        self.buffer.free()
        # print("MPMCQueue destroyed!")

    # push method for producers, returns True if the item was pushed successfully, False if the queue is full
    fn push(mut self, item: Self.T) -> Bool:
        var pw: UInt64
        var seq: UInt64
        var bk: UInt64 = Self.BACKOFF_MIN
        while True:
            pw = self.enqueue_pos.atomicVal.load[ordering=Consistency.MONOTONIC]()
            var cell_ptr = self.buffer + (pw & self.mask)
            seq = cell_ptr[].sequence.load[ordering=Consistency.ACQUIRE]()
            if pw == seq:
                if self.enqueue_pos.atomicVal.compare_exchange[failure_ordering=Consistency.MONOTONIC, success_ordering=Consistency.MONOTONIC](pw, pw + 1):
                    cell_ptr[].data = item.copy()
                    Atomic[DType.uint64].store[ordering=Consistency.RELEASE](UnsafePointer(to=cell_ptr[].sequence.value), pw + 1)
                    return True
                for _ in range(bk):
                    #fence[ordering=Consistency.SEQUENTIAL]() # I am not sure of this, I suppose however that this for loop is compiled out
                    pass
                bk <<= 1
                bk &= Self.BACKOFF_MAX
            elif pw > seq:
                return False

    # pop method for consumers, returns an Optional containing the item if popped successfully, or None if the queue is empty
    fn pop(mut self) -> Optional[Self.T]:
        var pr: UInt64
        var seq: UInt64
        var bk: UInt64 = Self.BACKOFF_MIN
        while True:
            pr = self.dequeue_pos.atomicVal.load[ordering=Consistency.MONOTONIC]()
            var cell_ptr = self.buffer + (pr & self.mask)
            seq = cell_ptr[].sequence.load[ordering=Consistency.ACQUIRE]()
            var expected_seq = pr + 1
            if seq == expected_seq:
                # element is ready to be consumed, try to claim it by incrementing pr
                if self.dequeue_pos.atomicVal.compare_exchange[failure_ordering=Consistency.MONOTONIC, success_ordering=Consistency.MONOTONIC](pr, pr + 1):
                    var item = cell_ptr[].data.copy()
                    Atomic[DType.uint64].store[ordering=Consistency.RELEASE](UnsafePointer(to=cell_ptr[].sequence.value), pr + self.mask + 1)
                    return Optional(item^)
                # CAS failed, another consumer might have claimed this item, retry
                for _ in range(bk):
                    #fence[ordering=Consistency.SEQUENTIAL]() # I am not sure of this, I suppose however that this for loop is compiled out
                    pass
                bk <<= 1
                bk &= Self.BACKOFF_MAX
            elif seq < expected_seq:
                # empty slot, the producer has not yet written the item, return None
                return Optional[Self.T](None)

# Test function to verify the basic functionality of the MPMCQueue
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
        print("Success! Data transferred")
    else:
        print("Failure! Data mismatch")

# Main
fn main():
    test_streaming()
