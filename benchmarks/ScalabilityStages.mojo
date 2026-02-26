# Scalability benchmark stages with simulated computation (sleep).
# Each stage sleeps for SleepMs milliseconds per element to simulate work.
# This way we can measure the pipeline overhead (queues, async tasks)
# isolated from actual computation.

from collections import Optional
from Communicator import MessageTrait
from Stage import StageKind, StageTrait
from Payload import Payload
from time import sleep

# Number of messages processed per benchmark run
comptime NUM_MESSAGES: Int = 50

# Source that generates NUM_MESSAGES payloads, sleeping SleepMs for each one
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
        # simulate computation with a sleep
        sleep(Self.SleepMs / 1000.0)
        return Payload[Self.Size](fill=1)

# Transform that receives a payload, sleeps SleepMs, and forwards it unchanged
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
        # simulate computation with a sleep
        sleep(Self.SleepMs / 1000.0)
        return input

# Sink that receives a payload, sleeps SleepMs, and discards it
struct SleepSink[Size: Int, SleepMs: Int](StageTrait):
    comptime kind = StageKind.SINK
    comptime InType = Payload[Self.Size]
    comptime OutType = Payload[Self.Size]
    comptime name = "SleepSink"

    # constructor
    fn __init__(out self):
        pass

    # cons
    fn consume_element(mut self, var input: Payload[Self.Size]):
        # simulate computation with a sleep
        sleep(Self.SleepMs / 1000.0)
