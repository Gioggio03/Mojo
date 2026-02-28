# Scalability benchmark stages with simulated computation (busy-wait via perf_counter_ns).
# Each stage busy-waits for SleepNs nanoseconds per element to simulate work.
# This way we can measure the pipeline overhead (queues, async tasks)
# isolated from actual computation.

from collections import Optional
from MoStream.communicator import MessageTrait
from MoStream.stage import StageKind, StageTrait
from payload import Payload
from time import perf_counter_ns

# Number of messages processed per benchmark run
comptime NUM_MESSAGES: Int = 50

# Helper function: busy-wait for exactly `ns` nanoseconds using perf_counter_ns
@always_inline
fn busy_wait[ns: Int]():
    var start = perf_counter_ns()
    while perf_counter_ns() - start < ns:
        pass

# Source that generates NUM_MESSAGES payloads, busy-waiting SleepNs ns for each one
struct SleepSource[Size: Int, SleepNs: Int](StageTrait):
    comptime kind = StageKind.SOURCE
    comptime InType = Payload[Self.Size]
    comptime OutType = Payload[Self.Size]
    comptime name = "SleepSource"
    var count: Int

    # constructor
    fn __init__(out self):
        self.count = 0

    # next_element
    fn next_element(mut self) -> Optional[Payload[Self.Size]]:
        if self.count >= NUM_MESSAGES:
            return None
        self.count += 1
        # simulate computation with a busy-wait
        busy_wait[Self.SleepNs]()
        return Payload[Self.Size](fill=1)

# Transform that receives a payload, busy-waits SleepNs ns, and forwards it unchanged
struct SleepTransform[Size: Int, SleepNs: Int](StageTrait):
    comptime kind = StageKind.TRANSFORM
    comptime InType = Payload[Self.Size]
    comptime OutType = Payload[Self.Size]
    comptime name = "SleepTransform"

    # constructor
    fn __init__(out self):
        pass

    # compute
    fn compute(mut self, var input: Payload[Self.Size]) -> Optional[Payload[Self.Size]]:
        # simulate computation with a busy-wait
        busy_wait[Self.SleepNs]()
        return input

# Sink that receives a payload, busy-waits SleepNs ns, and discards it
struct SleepSink[Size: Int, SleepNs: Int](StageTrait):
    comptime kind = StageKind.SINK
    comptime InType = Payload[Self.Size]
    comptime OutType = Payload[Self.Size]
    comptime name = "SleepSink"

    # constructor
    fn __init__(out self):
        pass

    # consume_element
    fn consume_element(mut self, var input: Payload[Self.Size]):
        # simulate computation with a busy-wait
        busy_wait[Self.SleepNs]()
