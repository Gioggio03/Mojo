# Stages used in benchmark_pipe

from collections import Optional
from MoStream.communicator import MessageTrait
from MoStream.stage import StageKind, StageTrait
from payload import Payload

comptime NUM_MESSAGES: Int = 1000

# BenchSource (Synthetic Source)
struct BenchSource[Size: Int](StageTrait):
    comptime kind = StageKind.SOURCE
    comptime InType = Payload[Self.Size]
    comptime OutType = Payload[Self.Size]
    comptime name = "BenchSource"
    var count: Int

    # constructor
    fn __init__(out self):
        self.count = 0

    # next_element produces NUM_MESSAGES messages of type Payload[Size]
    fn next_element(mut self) -> Optional[Payload[Self.Size]]:
        if self.count >= NUM_MESSAGES:
            return None
        self.count += 1
        return Payload[Self.Size](fill=1)

# BenchTransform (Synthetic Transform)
struct BenchTransform[Size: Int](StageTrait):
    comptime kind = StageKind.TRANSFORM
    comptime InType = Payload[Self.Size]
    comptime OutType = Payload[Self.Size]
    comptime name = "BenchTransform"

    # constructor
    fn __init__(out self):
        pass

    # compute just passes the payload through without modification
    fn compute(mut self, var input: Payload[Self.Size]) -> Optional[Payload[Self.Size]]:
        return input

# BenchSink (Synthetic Sink)
struct BenchSink[Size: Int](StageTrait):
    comptime kind = StageKind.SINK
    comptime InType = Payload[Self.Size]
    comptime OutType = Payload[Self.Size]
    comptime name = "BenchSink"

    # constructor
    fn __init__(out self):
        pass

    # consume_element just consumes the payload without doing anything
    fn consume_element(mut self, var input: Payload[Self.Size]):
        pass
