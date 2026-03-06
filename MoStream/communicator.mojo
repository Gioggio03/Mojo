# Communicator using a MPMC queue

# from MoStream.MPMC_naif import MPMCQueue # MPMC naif with locking
# from MoStream.MPMC import MPMCQueue # MPMC by Dmitry Vyukov
# from MoStream.MPMC_padding import MPMCQueue # MPMC by Dmitry Vyukov with padding
# from MoStream.MPMC_padding_optional import MPMCQueue # MPMC by Dmitry Vyukov with padding and optional as data field
from MoStream.MPMC_padding_optional_v2 import MPMCQueue # MPMC by Dmitry Vyukov with padding, optional as data field and move-enabled push semantics
from collections import Optional
from sys.info import size_of
from os.atomic import Atomic

# Trait of messages that can be sent through the Communicator
comptime MessageTrait = ImplicitlyCopyable & Writable

# Wrapper of messages to include an end-of-stream flag
struct MessageWrapper[T: MessageTrait](ImplicitlyCopyable, Defaultable):
    var data: Optional[Self.T] # the actual message data within an Optional
    var eos: Bool # end of stream

    # constructor I
    fn __init__(out self):
        self.data = None
        self.eos = False

    # constructor II
    fn __init__(out self, var data: Self.T, eos: Bool):
        self.data = Optional(data^)
        self.eos = eos

    # constructor III
    fn __init__(out self, eos: Bool):
        self.data = None
        self.eos = eos

# Communicator that uses a lock-free MPMC queue to send messages between threads
struct Communicator[T: MessageTrait](Movable):
    var queue: UnsafePointer[MPMCQueue[MessageWrapper[Self.T]], MutExternalOrigin]
    var prodNum: Int # number of producers
    var consNum: Int # number of consumers
    var destroyCount: Atomic[DType.uint64] # counter to coordinate the destruction of the Communicator
    var finishedProducerCount: Atomic[DType.uint64] # counter to coordinate the sending of end-of-stream messages by producers

    # constructor
    fn __init__(out self, pN: Int, cN: Int):
        self.queue = alloc[MPMCQueue[MessageWrapper[Self.T]]](1)
        q = MPMCQueue[MessageWrapper[Self.T]](size=1024)
        self.queue.init_pointee_move(q^)
        self.prodNum = pN
        self.consNum = cN
        self.destroyCount = Atomic[DType.uint64](cN)
        self.finishedProducerCount = Atomic[DType.uint64](pN)

    # destructor
    fn __del__(deinit self):
        self.queue.destroy_pointee()
        self.queue.free()

    # move constructor
    fn __moveinit__(out self, deinit existing: Self):
        # NOTE -> Mojo will not call the destructor of existing
        self.queue = existing.queue
        self.prodNum = existing.prodNum
        self.consNum = existing.consNum
        self.destroyCount = Atomic[DType.uint64](self.consNum)
        self.finishedProducerCount = Atomic[DType.uint64](self.prodNum)        

    # signaling that a producer has finished sending messages (to coordinate the sending of end-of-stream messages)
    fn producer_finished(mut self):
        old_count = self.finishedProducerCount.fetch_sub(1)
        if old_count == 1: # this was the last producer to finish
            for i in range(0, self.consNum):
                self.push(MessageWrapper[Self.T](eos = True))

    # check whether the Communicator can be safely destroyed
    fn check_isDestroyable(mut self) -> Bool:
        old_count = self.destroyCount.fetch_sub(1)
        if old_count == 1: # this was the last consumer to check for destroyability
            return True
        else:
            return False

    # pop (continuous retry until a message is available)
    fn pop(mut self) -> MessageWrapper[Self.T]:
        while True:
            result = self.queue[].pop()
            if result:
                return result.take()

### [PUSH_V2]
    fn push(mut self, var msg: MessageWrapper[Self.T]):
        _ = self.queue[].push(msg^)

### [PUSH_UNIVERSAL]
    # fn push(mut self, msg: MessageWrapper[Self.T]):
    #     while not self.queue[].push(msg):
    #         pass
