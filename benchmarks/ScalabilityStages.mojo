# Stage per il benchmark di scalabilità della pipeline.
# Ogni stage simula un calcolo dormendo per SleepMs millisecondi per ogni elemento.
# In questo modo possiamo misurare l'overhead della pipeline (code, task async)
# isolandolo dal calcolo reale.

from collections import Optional
from Communicator import MessageTrait
from Stage import StageKind, StageTrait
from Payload import Payload
from time import sleep

# Numero di messaggi processati per ogni run del benchmark
comptime NUM_MESSAGES: Int = 50


# Source che genera NUM_MESSAGES payload, dormendo SleepMs per ognuno
struct SleepSource[Size: Int, SleepMs: Int](StageTrait):
    comptime kind = StageKind.SOURCE
    comptime InType = Payload[Self.Size]
    comptime OutType = Payload[Self.Size]
    comptime name = "SleepSource"
    var count: Int

    fn __init__(out self):
        self.count = 0

    fn next_element(mut self) -> Optional[Payload[Self.Size]]:
        if self.count >= NUM_MESSAGES:
            return None
        self.count += 1
        # simula il calcolo con una sleep
        sleep(Self.SleepMs / 1000.0)
        return Payload[Self.Size](fill=1)


# Transform che riceve un payload, dorme SleepMs, e lo inoltra invariato
struct SleepTransform[Size: Int, SleepMs: Int](StageTrait):
    comptime kind = StageKind.TRANSFORM
    comptime InType = Payload[Self.Size]
    comptime OutType = Payload[Self.Size]
    comptime name = "SleepTransform"

    fn __init__(out self):
        pass

    fn compute(mut self, var input: Payload[Self.Size]) -> Optional[Payload[Self.Size]]:
        # simula il calcolo con una sleep
        sleep(Self.SleepMs / 1000.0)
        return input


# Sink che riceve un payload, dorme SleepMs, e lo scarta
struct SleepSink[Size: Int, SleepMs: Int](StageTrait):
    comptime kind = StageKind.SINK
    comptime InType = Payload[Self.Size]
    comptime OutType = Payload[Self.Size]
    comptime name = "SleepSink"

    fn __init__(out self):
        pass

    fn consume_element(mut self, var input: Payload[Self.Size]):
        # simula il calcolo con una sleep
        sleep(Self.SleepMs / 1000.0)
