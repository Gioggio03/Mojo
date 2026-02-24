# Traits used by a generic stage of the pipeline

from collections import Optional
from pipeline.communicator import MessageTrait

# Types of stages supported by the Pipeline
struct StageKind:
    comptime SOURCE: Int = 0
    comptime TRANSFORM: Int = 1
    comptime SINK: Int = 2
    comptime NOTDEFINED: Int = 3

# Generic trait of stages in the pipeline, with default implementations that raise errors if not overridden
trait StageTrait(ImplicitlyCopyable):
    comptime kind = StageKind.NOTDEFINED
    comptime InType: MessageTrait
    comptime OutType: MessageTrait
    comptime name: String = "No name"

    # next_element (stage SOURCE)
    #    generate the next element of the stream, returns an Optional containing the element if generated successfully, or None if the stream has ended
    fn next_element(mut self) raises -> Optional[Self.OutType]:
        raise String("Error: Stage ") + String(Self.name) + String(" does not implement the next_element() method")

    # compute (stage TRANSFORM)
    #    generate one or zero output elements for the input element
    fn compute(mut self, var input: Self.InType) raises -> Optional[Self.OutType]:
        raise String("Error: Stage ") + String(Self.name) + String(" does not implement the compute() method")

    # consume_element (stage SINK)
    #    consume one input element
    fn consume_element(mut self, var input: Self.InType) raises:
        raise String("Error: Stage ") + String(Self.name) + String(" does not implement the consume_element() method")
