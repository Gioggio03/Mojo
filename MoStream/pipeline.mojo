# MoStream pipeline implementation

from runtime.asyncrt import create_task, TaskGroup
from collections import Optional
from MoStream.communicator import MessageTrait, MessageWrapper, Communicator
from MoStream.stage import StageKind, StageTrait
from MoStream.node import NodeTrait, SeqNode, ParallelNode, seq, parallel
from MoStream.emitter import Emitter
from os import getenv
from sys.ffi import OwnedDLHandle, c_int
from python import Python

# Executor_task, the function that will be run by each task of the pipeline
#    it executes the logic of a stage and communicates with the other stages through the Communicators
async
fn executor_task[NodeT: NodeTrait,
                 In: MessageTrait,
                 Out: MessageTrait, //,
                 idx: Int,
                 len: Int]
                 (mut node: NodeT,
                 inComm: UnsafePointer[mut=True, Communicator[In]],
                 outComm: UnsafePointer[mut=True, Communicator[Out]],
                 libFuncC: OwnedDLHandle,
                 cpu_id: Int):
    try:
        var s = node.make_stage() # create the stage to be executed by this task
        # pinning of the underlying thread if pinning is enabled
        if (cpu_id >= 0):
            r = libFuncC.call["pin_thread_to_cpu_checked", c_int](c_int(cpu_id))
            if (r < 0):
                print("Warning: failed to pin thread of stage", NodeT.StageT.name, "to CPU core", cpu_id)
        @parameter
        if NodeT.StageT.kind == StageKind.SOURCE:
            constrained[idx == 0]() # Source stage must be the first stage of the pipeline
            execute_source[NodeT.StageT, In, Out](s, inComm, outComm)
        elif NodeT.StageT.kind == StageKind.SINK:
            constrained[idx == len - 1]() # Sink stage must be the last stage of the pipeline
            execute_sink[NodeT.StageT, In, Out](s, inComm, outComm)
        elif NodeT.StageT.kind == StageKind.TRANSFORM:
            execute_transform[NodeT.StageT, In, Out](s, inComm, outComm)
        elif NodeT.StageT.kind == StageKind.TRANSFORM_MANY:
            execute_transform_many[NodeT.StageT, In, Out](s, inComm, outComm)
        else:
            raise String("Error: Stage") + String(NodeT.StageT.name) + String("has an undefined kind")
    except e:
        print("Error: executor_task in stage", NodeT.StageT.name, "raised a problem -> ", e)

# Execute_source, the function that will be run by the task of a SOURCE stage of the pipeline
fn execute_source[Stage: StageTrait,
                  In: MessageTrait,
                  Out: MessageTrait]
                  (mut s: Stage,
                  inComm: UnsafePointer[mut=True, Communicator[In]],
                  outComm: UnsafePointer[mut=True, Communicator[Out]]) raises:
    var end_of_stream = False
    while (not end_of_stream):
        output = s.next_element()
        output_1 = rebind[Optional[Out]](output)
        if output_1 == None:
            end_of_stream = True
            outComm[].producer_finished()
            s.received_eos()
        else:
            outComm[].push(MessageWrapper[Out](data = output_1.take(), eos = False))
    # destroy the input communicator
    if (inComm[].check_isDestroyable()):
        inComm.destroy_pointee()
        inComm.free()

# Execute_sink, the function that will be run by the task of a SINK stage of the pipeline
fn execute_sink[Stage: StageTrait,
                In: MessageTrait,
                Out: MessageTrait]
                (mut s: Stage,
                inComm: UnsafePointer[mut=True, Communicator[In]],
                outComm: UnsafePointer[mut=True, Communicator[Out]]) raises:
    var end_of_stream = False
    while (not end_of_stream):
        input = inComm[].pop()
        input_1 = rebind[MessageWrapper[Stage.InType]](input)
        if input_1.eos:
            end_of_stream = True
            s.received_eos()
        else:
            s.consume_element(input_1.data.take())
    # destroy the output and input communicators
    outComm.destroy_pointee()
    outComm.free()
    if (inComm[].check_isDestroyable()):
        inComm.destroy_pointee()
        inComm.free()

# Execute_transform, the function that will be run by the task of a TRANSFORM stage of the pipeline
fn execute_transform[Stage: StageTrait,
                     In: MessageTrait,
                     Out: MessageTrait]
                     (mut s: Stage,
                     inComm: UnsafePointer[mut=True, Communicator[In]],
                     outComm: UnsafePointer[mut=True, Communicator[Out]]) raises:
    var end_of_stream = False
    while (not end_of_stream):
        input = inComm[].pop()
        input_2 = rebind[MessageWrapper[Stage.InType]](input)
        if input_2.eos:
            end_of_stream = True
            outComm[].producer_finished()
            s.received_eos()
        else:
            output = s.compute(input_2.data.take())
            output_2 = rebind[Optional[Out]](output)
            if (output_2 != None):
                outComm[].push(MessageWrapper[Out](data = output_2.take(), eos = False))
    # destroy the input communicator
    if (inComm[].check_isDestroyable()):
        inComm.destroy_pointee()
        inComm.free()

# Execute_transform_many, the function that will be run by the task of a TRANSFORM_MANY stage of the pipeline
fn execute_transform_many[Stage: StageTrait,
                          In: MessageTrait,
                          Out: MessageTrait]
                          (mut s: Stage,
                          inComm: UnsafePointer[mut=True, Communicator[In]],
                          outComm: UnsafePointer[mut=True, Communicator[Out]]) raises:
    var end_of_stream = False
    var e = Emitter(outComm)
    while (not end_of_stream):
        input = inComm[].pop()
        input_2 = rebind[MessageWrapper[Stage.InType]](input)
        if input_2.eos:
            end_of_stream = True
            outComm[].producer_finished()
            s.received_eos()
        else:
            output = s.compute_many(input_2.data.take(), rebind[Emitter[Stage.OutType]](e))
    # destroy the input communicator
    if (inComm[].check_isDestroyable()):
        inComm.destroy_pointee()
        inComm.free()

# Pipeline
struct Pipeline[*Ts: NodeTrait]:
    comptime N = Variadic.size[NodeTrait](Self.Ts)
    var nodes: Tuple[*Self.Ts]
    var cpu_ids: List[Int]
    var num_cpus: Int
    var libFuncC: OwnedDLHandle
    var tg: TaskGroup
    var pinning_enabled: Bool
    var last_assigned_cpu: Int

    # constructor
    fn __init__(out self, var nodes: Tuple[*Self.Ts]) raises:
        self.nodes = nodes^
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
        self.last_assigned_cpu = 0
        mapping_str = getenv("MOSTREAM_PINNING", "")
        self.parse_mapping_string(mapping_str)

    # _run_from
    fn _run_from[idx: Int, length: Int, M: MessageTrait](mut self, in_comm: UnsafePointer[mut=True, Communicator[M]]):
        var np = self.nodes[idx].parallelism() # parallelism of node idx
        var nc = 0 # parallelism of the next node idx+1
        @parameter
        if idx < Self.N-1:
            nc = self.nodes[idx+1].parallelism()
        comm = Communicator[Self.Ts[idx].OutType](np, nc)
        out_comm = alloc[Communicator[Self.Ts[idx].OutType]](1)
        out_comm.init_pointee_move(comm^)
        for i in range(0, np):
            var cpu_id: Int # identifier of the CPU core assigned to the task running this stage
            cpu_id = self.cpu_ids[self.last_assigned_cpu + idx] if self.pinning_enabled else -1
            self.tg.create_task(executor_task[idx, length](self.nodes[idx],
                                                           in_comm,
                                                           out_comm,
                                                           self.libFuncC,
                                                           cpu_id))
        self.last_assigned_cpu = self.last_assigned_cpu + np
        @parameter
        if idx + 1 < Self.N:
            self._run_from[idx + 1, length, Self.Ts[idx].OutType](out_comm)

    # run
    fn run(mut self):
        comm = Communicator[Self.Ts[0].InType](0, self.nodes[0].parallelism())
        first_comm = alloc[Communicator[Self.Ts[0].InType]](1)
        first_comm.init_pointee_move(comm^)
        self._run_from[0, Self.N](first_comm)
        self.tg.wait()

    # parse the cpus list
    fn parse_mapping_string(mut self, s: String) raises:
        if (s == ""):
            for i in range(0, self.num_cpus):
                self.cpu_ids.append(i)
        else:
            # split the string by commas
            var parts = s.split(",")
            for part in parts:
                self.cpu_ids.append(Int(part))

    # enable/disable pinning for the pipeline threads
    fn setPinning(mut self, enabled: Bool):
        self.pinning_enabled = enabled
