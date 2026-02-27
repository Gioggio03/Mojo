# MoStream pipeline implementation

from runtime.asyncrt import create_task, TaskGroup
from collections import Optional
from MoStream.communicator import MessageTrait, MessageWrapper, Communicator
from MoStream.stage import StageKind, StageTrait
from os import getenv
from sys.ffi import OwnedDLHandle, c_int
from python import Python

# Executor_task, the function that will be run by each task of the pipeline
#    it executes the logic of a stage and communicates with the other stages through the Communicators
async
fn executor_task[Stage: StageTrait,
                 In: MessageTrait,
                 Out: MessageTrait, //,
                 idx: Int,
                 len: Int]
                 (mut s: Stage,
                 inComm: UnsafePointer[mut=True, Communicator[In]],
                 outComm: UnsafePointer[mut=True, Communicator[Out]],
                 libFuncC: OwnedDLHandle,
                 cpu_id: Int):
    try:
        var end_of_stream = False
        # pinning of the underlying thread if pinning isenabled
        if (cpu_id >= 0):
            r = libFuncC.call["pin_thread_to_cpu_checked", c_int](c_int(cpu_id))
            if (r < 0):
                print("Warning: failed to pin thread of stage", Stage.name, "to CPU core", cpu_id)
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
            raise String("Error: Stage") + String(Stage.name) + String("has an undefined kind")
    except e:
        print("Error: executor_task in stage", Stage.name, "raised a problem -> ", e)

# Pipeline
struct Pipeline[*Ts: StageTrait]:
    comptime N = Variadic.size[StageTrait](Self.Ts)
    var stages: Tuple[*Self.Ts]
    var cpu_ids: List[Int]
    var num_cpus: Int
    var libFuncC: OwnedDLHandle
    var tg: TaskGroup
    var pinning_enabled: Bool

    # constructor
    fn __init__(out self, var stages: Tuple[*Self.Ts]) raises:
        self.stages = stages^
        self.cpu_ids = List[Int]()
        mp = Python.import_module("multiprocessing")
        self.num_cpus = Int(py=mp.cpu_count())
        path_lib = getenv("MOSTREAM_HOME", ".")
        if path_lib == ".":
            print("Warning: MOSTREAM_HOME environment variable not set, using current directory as default")
        path_lib += "/MoStream/lib/libFuncC.so"
        self.libFuncC = OwnedDLHandle(path_lib)
        if not self.libFuncC.check_symbol("pin_thread_to_cpu_checked"):
            raise "Error: symbol pin_thread_to_cpu_checked not found in libFuncC.so"
        self.tg = TaskGroup()
        self.pinning_enabled = False
        mapping_str = getenv("MOSTREAM_PINNING", "")
        self.parse_mapping_string(mapping_str)

    # _run_from
    fn _run_from[idx: Int, length: Int, M: MessageTrait](mut self, in_comm: UnsafePointer[mut=True, Communicator[M]]):
        comm = Communicator[Self.Ts[idx].OutType]()
        out_comm = alloc[Communicator[Self.Ts[idx].OutType]](1)
        out_comm.init_pointee_move(comm^)
        var cpu_id: Int # identifier of the CPU core assigned to the task running this stage
        cpu_id = self.cpu_ids[idx % len(self.cpu_ids)] if self.pinning_enabled else -1
        self.tg.create_task(executor_task[idx, length](self.stages[idx], in_comm, out_comm, self.libFuncC, cpu_id))
        @parameter
        if idx + 1 < Self.N:
            self._run_from[idx + 1, length, Self.Ts[idx].OutType](out_comm)

    # run
    fn run(mut self):
        comm = Communicator[Self.Ts[0].InType]()
        first_comm = alloc[Communicator[Self.Ts[0].InType]](1)
        first_comm.init_pointee_move(comm^)
        self._run_from[0, Self.N](first_comm)
        self.tg.wait()

    # Method to parse the cpus list
    fn parse_mapping_string(mut self, s: String) raises:
        if (s == ""):
            for i in range(0, self.num_cpus):
                self.cpu_ids.append(i)
        else:
            # split the string by commas
            var parts = s.split(",")
            for part in parts:
                self.cpu_ids.append(Int(part))

    # Method to enable/disable pinning for the pipeline threads
    fn setPinning(mut self, enabled: Bool):
        self.pinning_enabled = enabled
