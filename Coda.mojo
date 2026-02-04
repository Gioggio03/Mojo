from os.atomic import Atomic, Consistency
from time import sleep


struct Cell[T: Movable & Copyable](Movable): # Sostituisce CollectionElement
    var sequence: Atomic[DType.int64]
    var data: T

    fn __init__(out self, seq: Int):
        """Inizializzazione con 'out self' per memoria non allocata."""
       
        self.sequence = Atomic[DType.int64](seq)
        

    fn __moveinit__(out self, deinit existing: Self):
        # 1. Carichiamo il valore numerico dall'atomico esistente
        var val = existing.sequence.load()
        
        # 2. Inizializziamo un NUOVO atomico con quel valore
        self.sequence = Atomic[DType.int64](val)
        
        # 3. Il dato T invece può essere spostato normalmente
        self.data = existing.data^

struct MPMCQueue[T: Movable & Copyable]: 
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
    
        
        self.buffer = alloc[Cell[T]](self.size)
        
       
        self.enqueue_pos = Atomic[DType.int64](0)
        self.dequeue_pos = Atomic[DType.int64](0)
        
        
        for i in range(self.size):
            (self.buffer + i).init_pointee_move(Cell[T](i))
    
    fn push(mut self, item: T):
        """
        Inserisce un elemento nella coda trasferendone la proprietà.
        Implementa l'attesa attiva (spin-lock) se la coda è piena.
        """
       
        var pos = self.enqueue_pos.fetch_add(1)
        
       
        var index = Int(pos & self.mask)
        var cell_ptr = self.buffer + index

        while True:
            var seq = cell_ptr[].sequence.load()
            if seq == pos:
                break
            # Qui potremmo inserire un micro-delay per ridurre il consumo di CPU
        
        
        cell_ptr[].data = item.copy()
        var seq_ptr = UnsafePointer(to=cell_ptr[].sequence)
        # Sia in push e pop mi da problemi con lo store, ho provaot anche diversi metodi
        Atomic[DType.int64].store(UnsafePointer(to=cell_ptr[].sequence), pos + 1)
    fn pop(mut self) -> T:
        """Estrae un dato trasferendone la proprietà al consumatore."""
        # 1. Prenota la posizione
        var pos = self.dequeue_pos.fetch_add(1)
        
        # 2. Calcola l'indice (usando il cast corretto per evitare l'errore to_int)
        var index = Int(pos & self.mask)
        var cell_ptr = self.buffer + index

        # 3. Spin-lock: Aspetta che il dato sia pronto (sequence == pos + 1)
        while cell_ptr[].sequence.load() != pos + 1:
            pass
        
        var item = cell_ptr[].data.copy()

        var seq_ptr = UnsafePointer(to=cell_ptr[].sequence)
        # Applichiamo la stessa logica qui
        Atomic[DType.int64].store(seq_ptr, pos + self.size)
        return item^
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
