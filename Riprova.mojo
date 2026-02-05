from os.atomic import Atomic, Consistency
from time import sleep

struct Cell[T: Movable & Copyable & Defaultable](Movable): # Sostituisce CollectionElement
    var sequence: Atomic[DType.int64]
    var data: Self.T

    fn __init__(out self, seq: Int):
        """Inizializzazione con 'out self' per memoria non allocata."""
        self.sequence = Atomic[DType.int64](seq)
        self.data = Self.T()

    fn __moveinit__(out self, deinit existing: Self):
        # 1. Carichiamo il valore numerico dall'atomico esistente
        var val = existing.sequence.load()
        
        # 2. Inizializziamo un NUOVO atomico con quel valore
        self.sequence = Atomic[DType.int64](val)
        
        # 3. Il dato T invece può essere spostato normalmente
        self.data = existing.data^

struct MPMCQueue[T: Movable & Copyable & Defaultable]: 
    #comptime CellPointer = UnsafePointer[mut=True, Cell[Self.T], Origin[True].external]

    comptime CellPointer = UnsafePointer[mut=True, Cell[T],Origin[True].external]

    var buffer: Self.CellPointer
    var size: Int
    var mask: Int
    var enqueue_pos: Atomic[DType.int64]
    var dequeue_pos: Atomic[DType.int64]

    fn __init__(out self, size: Int):
        """
        Inizializza la coda MPMC. 
        'size' deve essere una potenza di 2 per permettere il mascheramento bitwise.
        """
        self.size = size
        self.mask = size - 1
        self.buffer = alloc[Cell[Self.T]](self.size)
        self.enqueue_pos = Atomic[DType.int64](0)
        self.dequeue_pos = Atomic[DType.int64](0)
        for i in range(self.size):
            (self.buffer + i).init_pointee_move(Cell[Self.T](i))

    fn push(mut self, item: T) -> Bool:
        var pw: Int = 0
        var seq: Int = 0
        var bk: Int = 1

        while True:
            
            pw = Int(self.enqueue_pos.load[ordering=Consistency.MONOTONIC]())
            var cell_ptr = self.buffer + (pw & self.mask)
            
            
            seq = Int(cell_ptr[].sequence.load[ordering=Consistency.ACQUIRE]())

            if pw == seq:
                
                if Atomic[DType.int64].compare_exchange(self.enqueue_pos, pw, pw + 1):
                    cell_ptr[].data = item.copy()
                    
                    
                    cell_ptr[].sequence.store[ordering=Consistency.RELEASE](pw + 1)
                    return True
                
                # Backoff per gestire la contesa (contention)
                for i in range(bk): pass
                bk = (bk << 1) if (bk << 1) < 1024 else 1024
                
            elif pw > seq:
                return False # Coda Piena

    fn pop(mut self) -> T:
        var pr: Int = 0
        var seq: Int = 0
        var bk: Int = 1
        var bk_max: Int = 1024

        while True:
            # Caricamento della posizione di lettura con ordinamento MONOTONIC
            pr = Int(self.dequeue_pos.load[ordering=Consistency.MONOTONIC]())
            var cell_ptr = self.buffer + (pr & self.mask)
            
            # Caricamento della sequenza con ACQUIRE per sincronizzare con la push
            seq = Int(cell_ptr[].sequence.load[ordering=Consistency.ACQUIRE]())

            var diff = seq - (pr + 1)

            if diff == 0:
                
                if Atomic[DType.int64].compare_exchange(self.dequeue_pos, pr, pr + 1):
                    # Estrazione del dato
                    var item = cell_ptr[].data.copy()
                    
                    
                    var seq_ptr = UnsafePointer(to=cell_ptr[].sequence.value)
                   
                    cell_ptr[].sequence.store[ordering=Consistency.RELEASE](pr + self.mask + 1)
                    
                    return item^ # Move del dato all'esterno
                
                # Gestione contesa tra consumatori (backoff)
                for i in range(bk): pass
                bk = (bk << 1) if (bk << 1) < bk_max else bk_max

            elif diff < 0:
                pass
    fn __del__(deinit self):
        """
        Distruttore della coda. 
        Libera la memoria manuale e distrugge gli elementi rimanenti.
        """
        for i in range(self.size):
            (self.buffer + i).destroy_pointee()

        self.buffer.free()
        print("Memoria della coda liberata correttamente.")

fn test_streaming():
    var queue = MPMCQueue[Int](size=1024)
    var data_to_send: Int = 42

    queue.push(data_to_send) 
    var received_data = queue.pop()
    
    if received_data == 42:
        print("Successo! Dato trasferito.")

# --- PUNTO D'INGRESSO ---
fn main():
    test_streaming()
