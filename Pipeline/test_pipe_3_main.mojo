# Test della pipeline con stage concreti
# Usa la libreria divisa in Communicator3, Stage3, Pipeline3
from collections import Optional
from Communicator3 import MessageTrait
from Stage3 import StageKind, StageTrait
from Pipeline3 import Pipeline

# FirstStage - Source: genera numeri da 1 a 1000
struct FirstStage(StageTrait):
    comptime kind = StageKind.SOURCE
    comptime InType = Int
    comptime OutType = Int
    comptime name = "FirstStage"
    var count: Int

    # costruttore
    fn __init__ (out self):
        self.count = 0

    # implementazione concreta di generate_stream
    fn generate_stream(mut self) -> Optional[Int]:
        if self.count > 1000:
            return None
        else:
            self.count = self.count + 1
            return self.count

# SecondStage - Transform: incrementa e converte in stringa
struct SecondStage(StageTrait):
    comptime kind = StageKind.TRANSFORM
    comptime InType = Int
    comptime OutType = String
    comptime name = "SecondStage"

    # costruttore
    fn __init__ (out self):
        pass

    # implementazione concreta di compute
    fn compute(mut self, mut input: Int) -> Optional[String]:
        input = input + 1
        return String("Valore " + String(input))

# ThirdStage - Sink: stampa il risultato
struct ThirdStage(StageTrait):
    comptime kind = StageKind.SINK
    comptime InType = String
    comptime OutType = String
    comptime name = "ThirdStage"

    # costruttore
    fn __init__ (out self):
        pass

    # implementazione concreta di drain_sink
    fn drain_sink(mut self, mut input: Self.InType) raises:
        print(input)

# main
def main():
    # crea gli stage
    first_stage = FirstStage()
    second_stage = SecondStage()
    third_stage = ThirdStage()

    # crea e avvia la pipeline
    pipeline = Pipeline((first_stage, second_stage, third_stage))
    pipeline.run()
    _ = pipeline
