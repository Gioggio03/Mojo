from os.atomic import Atomic, Consistency
from time import sleep


struct Cell[T: Movable & Copyable](Movable): # Sostituisce CollectionElement
    var sequence: Atomic[DType.int64]
    var data: T

    fn __init__(out self, seq: Int):
        """Inizializzazione con 'out self' per memoria non allocata."""
        # Costruisce l'atomico con valore iniziale
        self.sequence = Atomic[DType.int64](seq)
        
        # Inizializza data con un valore di default.
        # Nello streaming reale, useremo init_pointee_move per sovrascriverlo.
        #self.data = T()

    fn __moveinit__(out self, deinit existing: Self):
        # 1. Carichiamo il valore numerico dall'atomico esistente
        var val = existing.sequence.load()
        
        # 2. Inizializziamo un NUOVO atomico con quel valore
        self.sequence = Atomic[DType.int64](val)
        
        # 3. Il dato T invece può essere spostato normalmente
        self.data = existing.data^

struct MPMCQueue[T: Movable & Copyable]: # Requisiti per il trasferimento
    # Cambia questa riga nella struct MPMCQueue
    # Usiamo i nomi dei parametri per evitare errori di ordine
    # Proviamo l'ordine posizionale puro: Tipo, Origine, Indirizzo, Mutabilità
    # Usiamo AddressSpace() per creare il valore corretto richiesto dal compilatore
    # Usiamo i nomi dei parametri per superare il limite dei 2 parametri posizionali
    # Ordine: mut, type, origin, address_space
    # Mettiamo il Tipo per primo e il mut nominato per evitare l'errore AnyType
    # Rispettiamo la nuova struttura: mut è posizionale, gli altri sono nominati
    # Torniamo alla sintassi stabile usando il tipo Legacy
    # Usiamo mut=True come primo parametro nominato per sbloccare il Legacy
    comptime CellPointer = LegacyUnsafePointer[mut=True, type=Cell[T], origin=Origin[True].external]
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
    
        # 1. Allochiamo il blocco di memoria per le celle
        # La memoria restituita è 'allocated, uninitialized'
        # Usiamo la funzione globale alloc specifica per il tipo Cell[T]
        self.buffer = alloc[Cell[T]](self.size)
        
        # 2. Inizializziamo i cursori atomici a 0
        self.enqueue_pos = Atomic[DType.int64](0)
        self.dequeue_pos = Atomic[DType.int64](0)
        
        # 3. Prepariamo ogni singola cella (i "cartelli" di Vyukov)
        for i in range(self.size):
            # Usiamo l'aritmetica dei puntatori per accedere alla i-esima cella
            # Chiamiamo init_pointee_copy per creare la Cell nello stato 'initialized'
            (self.buffer + i).init_pointee_move(Cell[T](i))
    
    fn push(mut self, item: T):
        """
        Inserisce un elemento nella coda trasferendone la proprietà.
        Implementa l'attesa attiva (spin-lock) se la coda è piena.
        """
        # 1. 'Prenotiamo' una posizione globale incrementando il cursore dei produttori
        var pos = self.enqueue_pos.fetch_add(1)
        
        # Calcoliamo l'indice fisico nel buffer usando la maschera
        var index = Int(pos & self.mask)
        var cell_ptr = self.buffer + index

        # 2. Spin-lock: Aspettiamo che il 'cartello' (sequence) sia pronto per noi
        # Il produttore può scrivere solo se sequence == pos
        while True:
            var seq = cell_ptr[].sequence.load()
            if seq == pos:
                break
            # Qui potremmo inserire un micro-delay per ridurre il consumo di CPU
        
        # 3. Trasferimento del dato nella cella
        # Usiamo il trasferimento per spostare 'item' senza copiarlo
        cell_ptr[].data = item.copy()
        var seq_ptr = UnsafePointer(to=cell_ptr[].sequence)
        # Specifichiamo il tipo [DType.int64] (o quello che usi per T) per aiutare il compilatore
        # Specifichiamo sia il tipo che l'address space per non lasciare dubbi al compilatore
        Atomic[DType.int64].store(seq_ptr, pos + 1)
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
        

        # 4. Preleva il dato con trasferimento di proprietà (sigillo ^)
        var item = cell_ptr[].data.copy()

        # 5. Libera lo slot per il prossimo giro (imposta sequence per il produttore)var seq_ptr = cell_ptr.get_field_ptr["sequence"]()# Usiamo lo store statico passando il puntatore calcolato
        # Applichiamo la stessa logica del costruttore
        var seq_ptr = UnsafePointer(to=cell_ptr[].sequence)
        # Applichiamo la stessa logica qui
        Atomic[DType.int64].store(seq_ptr, pos + self.size)
        return item^
    fn __del__(deinit self):
        """
        Distruttore della coda. 
        Libera la memoria manuale e distrugge gli elementi rimanenti.
        """
        # 1. Distruzione degli elementi (opzionale ma pulito)
        # Se ci sono ancora oggetti nella coda, dovremmo chiamare destroy_pointee()
        # su ogni cella inizializzata per evitare leak dei dati interni a T.
        for i in range(self.size):
            (self.buffer + i).destroy_pointee()

        # 2. Liberazione del buffer
        # Chiamiamo free() per restituire la memoria al sistema
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
