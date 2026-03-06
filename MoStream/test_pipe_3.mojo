# Third trivial test of a pipeline with 4 stages:
#   - FirstStage: source, generates numbers from 1 to 1000
#   - SecondStage: forward the received number
#   - ThirdStage: forward the received number
#   - FourthStage: sink, couting the total sum of all received inputs

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
        if self.count >= 1000:
            return None
        else:
            self.count = self.count + 1
            return self.count

# SecondStage - forward the received number
struct SecondStage(StageTrait):
    comptime kind = StageKind.TRANSFORM
    comptime InType = Int
    comptime OutType = Int
    comptime name = "SecondStage"

    # costrutor
    fn __init__ (out self):
        pass

    # compute implementation
    fn compute(mut self, var input: Int) raises -> Int:
        return input

# ThirdStage - forward the received number
struct ThirdStage(StageTrait):
    comptime kind = StageKind.TRANSFORM
    comptime InType = Int
    comptime OutType = Int
    comptime name = "ThirdStage"

    # costrutor
    fn __init__ (out self):
        pass

    # compute implementation
    fn compute(mut self, var input: Int) raises -> Int:
        return input

# FourthStage - prints the input string
struct FourthStage(StageTrait):
    comptime kind = StageKind.SINK
    comptime InType = Int
    comptime OutType = Int
    comptime name = "FourthStage"
    var sum: Int

    # constructor
    fn __init__ (out self):
        self.sum = 0

    # consume_element implementation
    fn consume_element(mut self, var input: Int) raises:
        self.sum = self.sum + input

    # receive_eof implementation
    fn received_eos(mut self):
        print("Total sum: ", self.sum)

# Main
def main():
    # creating the stages
    first_stage = FirstStage()
    second_stage = SecondStage()
    third_stage = ThirdStage()
    fourth_stage = FourthStage()

    # creating the pipeline and running it
    pipeline = Pipeline((seq(first_stage), parallel(second_stage,2), parallel(third_stage,3), seq(fourth_stage)))
    pipeline.setPinning(enabled=False)
    pipeline.run()
    _ = pipeline
