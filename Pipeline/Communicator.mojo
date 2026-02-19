# Implementaton of the Communicator using a lock-free MPMC queue
from MPMC import MPMCQueue
from collections import Optional
from sys.info import size_of

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

    # constructor
    fn __init__(out self):
        self.queue = alloc[MPMCQueue[MessageWrapper[Self.T]]](1)
        q = MPMCQueue[MessageWrapper[Self.T]](size=1024)
        self.queue.init_pointee_move(q^)

    # destructor
    fn __del__(deinit self):
        self.queue.destroy_pointee()
        self.queue.free()
        print("Communicator destroyed!")

    # move constructor
    fn __moveinit__(out self, deinit existing: Self):
        # NOTE -> Mojo will not call the destructor of existing
        self.queue = existing.queue

    # pop (continuous retry until a message is available)
    fn pop(mut self) -> MessageWrapper[Self.T]:
        while True:
            result = self.queue[].pop()
            if result:
                return result.take()

    # push (continuous retry until the message is pushed)
    fn push(mut self, msg: MessageWrapper[Self.T]):
        while not self.queue[].push(msg):
            pass
