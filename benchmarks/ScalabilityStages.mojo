# Stage for the pipeline scalability benchmark.
# Each stage simulates computation by sleeping for SleepMs milliseconds for each element.
# In this way, we can measure the pipeline overhead (queues, async tasks)
# while isolating it from the actual computation.

from collections import Optional
from Communicator import MessageTrait
from Stage import StageKind, StageTrait
from Payload import Payload
from time import sleep

# Number of messages to process in the benchmark
comptime NUM_MESSAGES: Int = 50

# Source generating NUM_MESSAGES payloads of size Size, sleeping SleepMs milliseconds for each message
struct SleepSource[Size: Int, SleepMs: Int](StageTrait):
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
        sleep(Self.SleepMs / 1000.0)
        return Payload[Self.Size](fill=1)

# Transform that receives a payload, sleeps SleepMs milliseconds, and forwards it unchanged
struct SleepTransform[Size: Int, SleepMs: Int](StageTrait):
    comptime kind = StageKind.TRANSFORM
    comptime InType = Payload[Self.Size]
    comptime OutType = Payload[Self.Size]
    comptime name = "SleepTransform"

    # constructor
    fn __init__(out self):
        pass

    # compute
    fn compute(mut self, var input: Payload[Self.Size]) -> Optional[Payload[Self.Size]]:
        sleep(Self.SleepMs / 1000.0)
        return input

# Sink that receives a payload, sleeps SleepMs milliseconds, and discards it
struct SleepSink[Size: Int, SleepMs: Int](StageTrait):
    comptime kind = StageKind.SINK
    comptime InType = Payload[Self.Size]
    comptime OutType = Payload[Self.Size]
    comptime name = "SleepSink"

    # constructor
    fn __init__(out self):
        pass

    # consume_element
    fn consume_element(mut self, var input: Payload[Self.Size]):
        sleep(Self.SleepMs / 1000.0)
