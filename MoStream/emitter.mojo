# Emitter implementation used by TRANSFORM_MANY stages

from MoStream.communicator import MessageTrait, MessageWrapper, Communicator

# Emitter, used by TRANSFORM_MANY stages to emit output elements for the current input element being processed
@fieldwise_init
struct Emitter[Out: MessageTrait]:
    var outComm: UnsafePointer[Communicator[Self.Out], MutAnyOrigin]

    # produce a new output element for the current input element being processed
    #   by a TRANSFORM_MANY stage, by pushing it to the output communicator
    fn emit(mut self, var output: Self.Out) raises:
        self.outComm[].push(MessageWrapper[Self.Out](data = output^, eos = False))
