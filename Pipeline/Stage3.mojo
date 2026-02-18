# Stage3: Trait e tipi per gli stage della pipeline
from collections import Optional
from Communicator3 import MessageTrait

# Tipi di stage (Source, Transform, Sink)
struct StageKind:
    comptime SOURCE: Int = 0
    comptime TRANSFORM: Int = 1
    comptime SINK: Int = 2
    comptime NOTDEFINED: Int = 3

# Trait di uno stage generico
trait StageTrait(ImplicitlyCopyable):
    comptime kind = StageKind.NOTDEFINED
    comptime InType: MessageTrait
    comptime OutType: MessageTrait
    comptime name: String = "No name"

    # generate_stream (stage SOURCE)
    fn generate_stream(mut self) raises -> Optional[Self.OutType]:
        raise String("Error: Stage ") + String(Self.name) + String(" does not implement the generate_stream() method")

    # compute (stage TRANSFORM)
    fn compute(mut self, mut input: Self.InType) raises -> Optional[Self.OutType]:
        raise String("Error: Stage ") + String(Self.name) + String(" does not implement the compute() method")

    # drain_sink (stage SINK)
    fn drain_sink(mut self, mut input: Self.InType) raises:
        raise String("Error: Stage ") + String(Self.name) + String(" does not implement the drain_sink() method")
