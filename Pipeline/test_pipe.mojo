# Trivial test of the pipeline with 3 stages:
#   - FirstStage: source, generates numbers from 1 to 1000
#   - SecondStage: transform, increments each input and converts it to a string
#   - ThirdStage: sink, prints the input string
from collections import Optional
from Communicator import MessageTrait
from Stage import StageKind, StageTrait
from Pipeline import Pipeline

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
    fn next_element(mut self) -> Optional[Int]:
        if self.count > 1000:
            return None
        else:
            self.count = self.count + 1
            return self.count

# SecondStage - increaments the input and converts it to a string
struct SecondStage(StageTrait):
    comptime kind = StageKind.TRANSFORM
    comptime InType = Int
    comptime OutType = String
    comptime name = "SecondStage"

    # costrutor
    fn __init__ (out self):
        pass

    # compute implementation
    fn compute(mut self, var input: Int) -> Optional[String]:
        input = input + 1
        return String("Valore " + String(input))

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
    fn consume_element(mut self, var input: Self.InType):
        print(input)

# main
def main():
    # creating the stages
    first_stage = FirstStage()
    second_stage = SecondStage()
    third_stage = ThirdStage()

    # creating the pipeline and running it
    pipeline = Pipeline((first_stage, second_stage, third_stage))
    pipeline.run()
    _ = pipeline
