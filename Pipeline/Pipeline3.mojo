# Pipeline3: Orchestratore della pipeline
# Estratto da test_pipe_3.mojo del prof
from runtime.asyncrt import create_task
from runtime.asyncrt import TaskGroup
from collections import Optional
from Communicator3 import MessageTrait, MessageWrapper, Communicator
from Stage3 import StageKind, StageTrait

# executor_task: eseguito come task concorrente
async
fn executor_task[Stage: StageTrait, In: MessageTrait, Out: MessageTrait](index: Int, mut s: Stage, mut inComm: Communicator[In], mut outComm: Communicator[Out]):
    try:
        var end_of_stream = False
        @parameter
        if Stage.kind == StageKind.SOURCE:
            while (not end_of_stream):
                output = s.generate_stream()
                output_1 = rebind[Optional[Out]](output)
                if output_1 == None:
                    end_of_stream = True
                    outComm.push(MessageWrapper[Out](data = Out(), eos = True))
                else:
                    outComm.push(MessageWrapper[Out](data = output_1.value(), eos = False))
        elif Stage.kind == StageKind.SINK:
            while (not end_of_stream):
                input = inComm.pop()
                input_1 = rebind[MessageWrapper[Stage.InType]](input)
                if input_1.eos:
                    end_of_stream = True
                else:
                    s.drain_sink(input_1.data)
        elif Stage.kind == StageKind.TRANSFORM:
            while (not end_of_stream):
                input = inComm.pop()
                input_2 = rebind[MessageWrapper[Stage.InType]](input)
                if input_2.eos:
                    end_of_stream = True
                    outComm.push(MessageWrapper[Out](data = Out(), eos = True))
                else:
                    output = s.compute(input_2.data)
                    output_2 = rebind[Optional[Out]](output)
                    if (output_2 != None):
                        outComm.push(MessageWrapper[Out](data = output_2.value(), eos = False))
        else:
            raise String("Error: Stage ") + String(Stage.name) + String(" has an undefined kind")
    except e:
        print("Executor_task raised a problem -> ", Stage.name , " -> ", e)

# Pipeline
struct Pipeline[*Ts: StageTrait]:
    comptime N = Variadic.size[StageTrait](Self.Ts)
    var stages: Tuple[*Self.Ts]
    var tg: TaskGroup

    # costruttore
    fn __init__(out self, stages: Tuple[*Self.Ts]):
        self.stages = stages
        self.tg = TaskGroup()

    # _run_from
    fn _run_from[idx: Int, M: MessageTrait](mut self, mut in_comm: Communicator[M]):
        comm = Communicator[Self.Ts[idx].OutType]()
        out_comm = alloc[Communicator[Self.Ts[idx].OutType]](1)
        out_comm.init_pointee_move(comm^)
        self.tg.create_task(executor_task(idx, self.stages[idx], in_comm, out_comm[]))
        @parameter
        if idx + 1 < Self.N:
            self._run_from[idx + 1, Self.Ts[idx].OutType](out_comm[])

    # run
    fn run(mut self):
        comm = Communicator[Self.Ts[0].InType]()
        first_comm = alloc[Communicator[Self.Ts[0].InType]](1)
        first_comm.init_pointee_move(comm^)
        self._run_from[0](first_comm[])
        self.tg.wait()
