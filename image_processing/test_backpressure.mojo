from runtime.asyncrt import TaskGroup
from time import sleep, perf_counter_ns
from collections import Optional
from MoStream.MPMC_padding_optional_v2 import MPMCQueue

struct Producer:
    var id: Int
    var q_ptr: UnsafePointer[mut=True, MPMCQueue[Int]]
    fn __call__(mut self):
        print("Producer", self.id, "started")
        for i in range(100):
            _ = self.q_ptr[].push(self.id * 1000 + i)
        print("Producer", self.id, "done")

struct Consumer:
    var id: Int
    var q_ptr: UnsafePointer[mut=True, MPMCQueue[Int]]
    fn __call__(mut self):
        print("Consumer", self.id, "started")
        for i in range(100):
            sleep(0.001) 
            var item: Optional[Int] = None
            while True:
                item = self.q_ptr[].pop()
                if item != None:
                    break
        print("Consumer", self.id, "done")

fn test_backpressure() raises:
    var q = MPMCQueue[Int](size=16) # Small queue to force backpressure quickly
    var q_ptr = alloc[MPMCQueue[Int]](1)
    q_ptr.init_pointee_move(q^)

    var tg = TaskGroup()
    print("Launching tasks...")
    tg.create_task(Producer(0, q_ptr))
    tg.create_task(Producer(1, q_ptr))
    tg.create_task(Consumer(0, q_ptr))
    tg.create_task(Consumer(1, q_ptr))
    tg.wait()

    q_ptr.destroy_pointee()
    q_ptr.free()
    print("Test finished successfully!")

fn main() raises:
    test_backpressure()
