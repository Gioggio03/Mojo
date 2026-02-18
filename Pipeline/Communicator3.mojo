# Communicator3: Comunicatore con coda MPMC lock-free
# Estratto e modificato da test_pipe_3.mojo del prof
from MPMC import MPMCQueue
from collections import Optional
from memory import memset_zero
from sys.info import size_of

# Trait dei messaggi scambiati tra stage
comptime MessageTrait = ImplicitlyCopyable & Writable & Defaultable

# Wrapper di un messaggio scambiato tra stage (usato nei communicator)
@fieldwise_init
struct MessageWrapper[T: MessageTrait](ImplicitlyCopyable, Movable, Defaultable):
    var data: Self.T
    var eos: Bool # end of stream

    # Serve a prescindere perchè è richiesto da MPMCQueue
    fn __init__(out self):
        self.data = Self.T()
        self.eos = False

# Comunicatore basato su coda MPMC lock-free
# La MPMCQueue è allocata sull'heap tramite puntatore, così il Communicator è Movable
struct Communicator[T: MessageTrait](Movable):
    var queue: UnsafePointer[MPMCQueue[MessageWrapper[Self.T]], MutExternalOrigin]

    # costruttore: alloca la MPMCQueue sull'heap
    fn __init__(out self):
        self.queue = alloc[MPMCQueue[MessageWrapper[Self.T]]](1)
        # MPMCQueue non è Movable, quindi costruiamo direttamente sull'heap
        memset_zero(self.queue.bitcast[UInt8](), size_of[MPMCQueue[MessageWrapper[Self.T]]]())
        self.queue[] = MPMCQueue[MessageWrapper[Self.T]](size=1024)

    # distruttore: libera la MPMCQueue
    fn __del__(deinit self):
        self.queue.destroy_pointee()
        self.queue.free()
        print("Destroying communicator")

    # move constructor: copia l'indirizzo del puntatore (non la coda)
    fn __moveinit__(out self, deinit existing: Self):
        self.queue = existing.queue

    # pop: attende finché un elemento non è disponibile
    fn pop(mut self) -> MessageWrapper[Self.T]:
        while True:
            result = self.queue[].pop()
            if result:
                return result.value()

    # push: riprova finché non riesce (coda piena)
    fn push(mut self, msg: MessageWrapper[Self.T]):
        while not self.queue[].push(msg):
            pass  # riprova se la coda è piena
