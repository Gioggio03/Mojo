# Second trivial test of a pipeline with 3 stages:
#   - FirstStage: source generating numbers from 1 to 1000
#   - SecondStage: stage producing two strings for each input number: "Valore <number+1>" and "Valore <(number+1)*2>"
#   - ThirdStage: sink printing each input string received

from collections import Optional
from MoStream.communicator import MessageTrait
from MoStream.stage import StageKind, StageTrait
from MoStream.node import NodeTrait, SeqNode, ParallelNode, seq, parallel
from MoStream.emitter import Emitter
from MoStream.pipeline import Pipeline

# FirstStage - Source: generetes numbers from 1 to 1000
struct FirstStage(StageTrait):
    comptime kind = StageKind.SOURCE
    comptime InType = Int
    comptime OutType = Int
    comptime name = "FirstStage"
    var count: Int

    # costructor
    fn __init__ (out self):
        self.count = 0

    # next_element implementation
    fn next_element(mut self) raises -> Optional[Int]:
        if self.count > 1000:
            return None
        else:
            self.count = self.count + 1
            return self.count

# SecondStage - increaments the input and converts it to a string
struct SecondStage(StageTrait):
    comptime kind = StageKind.TRANSFORM_MANY
    comptime InType = Int
    comptime OutType = String
    comptime name = "SecondStage"

    # costrutor
    fn __init__ (out self):
        pass

    # compute implementation
    fn compute_many(mut self, var input: Int, mut emitter: Emitter[String]) raises:
        input = input + 1
        emitter.emit(String("Valore " + String(input)))
        emitter.emit(String("Valore " + String(input * 2)))

# ThirdStage - prints the input string
struct ThirdStage(StageTrait):
    comptime kind = StageKind.SINK
    comptime InType = String
    comptime OutType = String
    comptime name = "ThirdStage"

    # constructor
    fn __init__ (out self):
        pass

    # consume_element implementation
    fn consume_element(mut self, var input: String) raises:
        print(input)

# Main
def main():
    # creating the stages
    first_stage = FirstStage()
    second_stage = SecondStage()
    third_stage = ThirdStage()

    # creating the pipeline and running it
    pipeline = Pipeline((seq(first_stage), seq(second_stage), seq(third_stage)))
    pipeline.setPinning(enabled=False)
    pipeline.run()
    _ = pipeline
