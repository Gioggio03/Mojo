# Pipeline parallel pattern
from runtime.asyncrt import create_task
from runtime.asyncrt import TaskGroup
from collections import Optional
from pipeline.communicator import MessageTrait, MessageWrapper, Communicator
from pipeline.stage import StageKind, StageTrait
from sys.terminate import exit

# Executor_task, the function that will be run by each task of the pipeline
#    it executes the logic of each stage and communicates with the other stages through the Communicators
async
fn executor_task[Stage: StageTrait,
                 In: MessageTrait,
                 Out: MessageTrait, //, 
                 idx: Int, 
                 len: Int](mut s: Stage,
                           inComm: UnsafePointer[mut=True, Communicator[In]],
                           outComm: UnsafePointer[mut=True, Communicator[Out]]):
    try:
        var end_of_stream = False
        @parameter
        if Stage.kind == StageKind.SOURCE:
            constrained[idx == 0]() # Source stage must be the first stage of the pipeline
            while (not end_of_stream):
                output = s.next_element()
                output_1 = rebind[Optional[Out]](output)
                if output_1 == None:
                    end_of_stream = True
                    outComm[].push(MessageWrapper[Out](eos = True))
                else:
                    outComm[].push(MessageWrapper[Out](data = output_1.take(), eos = False))
            # destroy the input communicator
            inComm.destroy_pointee()
            inComm.free()
        elif Stage.kind == StageKind.SINK:
            constrained[idx == len - 1]() # Sink stage must be the last stage of the pipeline
            while (not end_of_stream):
                input = inComm[].pop()
                input_1 = rebind[MessageWrapper[Stage.InType]](input)
                if input_1.eos:
                    end_of_stream = True
                else:
                    s.consume_element(input_1.data.take())
            # destroy the output and input communicators
            outComm.destroy_pointee()
            outComm.free()
            inComm.destroy_pointee()
            inComm.free()
        elif Stage.kind == StageKind.TRANSFORM:
            while (not end_of_stream):
                input = inComm[].pop()
                input_2 = rebind[MessageWrapper[Stage.InType]](input)
                if input_2.eos:
                    end_of_stream = True
                    outComm[].push(MessageWrapper[Out](eos = True))
                else:
                    output = s.compute(input_2.data.take())
                    output_2 = rebind[Optional[Out]](output)
                    if (output_2 != None):
                        outComm[].push(MessageWrapper[Out](data = output_2.take(), eos = False))
            # destroy the input communicator
            inComm.destroy_pointee()
            inComm.free()
        else:
            raise String("Error: Stage ") + String(Stage.name) + String(" has an undefined kind")
    except e:
        print("Error: executor_task in stage ", Stage.name, " raised a problem -> ", e)

# Pipeline parallel pattern
struct Pipeline[*Ts: StageTrait]:
    comptime N = Variadic.size[StageTrait](Self.Ts)
    var stages: Tuple[*Self.Ts]
    var tg: TaskGroup

    # constructor
    fn __init__(out self, var stages: Tuple[*Self.Ts]):
        self.stages = stages^
        self.tg = TaskGroup()

    # _run_from
    fn _run_from[idx: Int, len: Int, M: MessageTrait](mut self, in_comm: UnsafePointer[mut=True, Communicator[M]]):
        comm = Communicator[Self.Ts[idx].OutType]()
        out_comm = alloc[Communicator[Self.Ts[idx].OutType]](1)
        out_comm.init_pointee_move(comm^)
        self.tg.create_task(executor_task[idx, len](self.stages[idx], in_comm, out_comm))
        @parameter
        if idx + 1 < Self.N:
            self._run_from[idx + 1, len, Self.Ts[idx].OutType](out_comm)

    # run
    fn run(mut self):
        comm = Communicator[Self.Ts[0].InType]()
        first_comm = alloc[Communicator[Self.Ts[0].InType]](1)
        first_comm.init_pointee_move(comm^)
        self._run_from[0, Self.N](first_comm)
        self.tg.wait()
