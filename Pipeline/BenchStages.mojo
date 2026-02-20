# Benchmark stages per test

from collections import Optional
from Communicator import MessageTrait
from Stage import StageKind, StageTrait
from Payload import Payload


comptime NUM_MESSAGES: Int = 1000


struct BenchSource[Size: Int](StageTrait):
    comptime kind = StageKind.SOURCE
    comptime InType = Payload[Self.Size]
    comptime OutType = Payload[Self.Size]
    comptime name = "BenchSource"
    var count: Int

    fn __init__(out self):
        self.count = 0

    fn next_element(mut self) -> Optional[Payload[Self.Size]]:
        if self.count >= NUM_MESSAGES:
            return None
        self.count += 1
        return Payload[Self.Size](fill=1)

struct BenchTransform[Size: Int](StageTrait):
    comptime kind = StageKind.TRANSFORM
    comptime InType = Payload[Self.Size]
    comptime OutType = Payload[Self.Size]
    comptime name = "BenchTransform"

    fn __init__(out self):
        pass

    fn compute(mut self, var input: Payload[Self.Size]) -> Optional[Payload[Self.Size]]:
        return input

struct BenchSink[Size: Int](StageTrait):
    comptime kind = StageKind.SINK
    comptime InType = Payload[Self.Size]
    comptime OutType = Payload[Self.Size]
    comptime name = "BenchSink"

    fn __init__(out self):
        pass

    fn consume_element(mut self, var input: Payload[Self.Size]):
        pass
