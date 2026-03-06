# Traits used by a generic node of the pipeline

from MoStream.stage import StageTrait
from MoStream.communicator import MessageTrait

# A pipeline node is either a single stage or a parallel stage
trait NodeTrait(ImplicitlyCopyable):
    comptime StageT: StageTrait
    comptime InType: MessageTrait
    comptime OutType: MessageTrait

    # return the parallelism of this node (number of replicas)
    fn parallelism(self) -> Int:
        ...

    # return a copy of the stage instance
    fn make_stage(self) -> Self.StageT:
        ...

# SeqNode is a node with parallelism 1
@fieldwise_init
struct SeqNode[st: StageTrait](NodeTrait):
    comptime StageT = Self.st
    comptime InType = Self.StageT.InType
    comptime OutType = Self.StageT.OutType
    var stage: Self.StageT

    # return the parallelism of this node (number of replicas)
    fn parallelism(self) -> Int:
        return 1

    # return a copy of the stage instance
    fn make_stage(self) -> Self.StageT:
        return self.stage

# ParallelNode is a node with parallelism > 1
@fieldwise_init
struct ParallelNode[st: StageTrait](NodeTrait):
    comptime StageT = Self.st
    comptime InType = Self.StageT.InType
    comptime OutType = Self.StageT.OutType
    var stage: Self.st
    var parDegree: Int

    # return the parallelism of this node (number of replicas)
    fn parallelism(self) -> Int:
        return self.parDegree

    # return a copy of the stage instance
    fn make_stage(self) -> Self.StageT:
        return self.stage

# Helper function to create a SeqNode
fn seq[StageT: StageTrait](stage: StageT) -> SeqNode[StageT]:
    return SeqNode[StageT](stage=stage)

# Helper function to create a ParallelNode
fn parallel[StageT: StageTrait](stage: StageT, parDegree: Int) -> ParallelNode[StageT]:
    return ParallelNode[StageT](stage=stage, parDegree=parDegree)
