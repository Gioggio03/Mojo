# Naif MPMC queue with locking
from collections import List
from utils.lock import BlockingSpinLock, BlockingScopedLock

# MPMC queue naif implementation
struct MPMCQueue[T: Movable & Copyable & Defaultable](Movable):
    var queue: List[Self.T]
    var lock: BlockingSpinLock
    var size: Int

    # constructor
    fn __init__(out self, size: Int):
        self.queue = List[Self.T]()
        self.lock = BlockingSpinLock()
        self.size = size

    # move constructor
    fn __moveinit__(out self, deinit existing: Self):
        self.queue = existing.queue^
        self.lock = BlockingSpinLock()
        self.size = existing.size

    # destructor
    fn __del__(deinit self):
        pass
        # print("MPMCQueue destroyed!")

    # push method for producers, returns True if the item was pushed successfully, False if the queue is full
    fn push(mut self, item: Self.T) -> Bool:
        with BlockingScopedLock(self.lock):
            if (len(self.queue) < self.size):
                self.queue.append(item.copy())
                return True
        return False

    # pop method for consumers, returns an Optional containing the item if popped successfully, or None if the queue is empty
    fn pop(mut self) -> Optional[Self.T]:
        with BlockingScopedLock(self.lock):
            if len(self.queue) > 0:
                item = self.queue[0].copy()
                _ = self.queue.pop(0)
                return item^
            else:
                return None
