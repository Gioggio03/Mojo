from runtime.asyncrt import TaskGroup
from os.atomic import Atomic
from time import perf_counter_ns
from sys import argv
import MPMC

# Puntatori per contatori atomici condivisi tra thread
comptime ScalarU64Pointer = UnsafePointer[Scalar[DType.uint64], MutExternalOrigin]
comptime ScalarI64Pointer = UnsafePointer[Scalar[DType.int64], MutExternalOrigin]

# Dimensione coda fissa (comptime perché richiesto dalla struttura MPMC)
comptime QUEUE_SIZE = 1024


async fn producer(
    mut queue: MPMC.MPMCQueue[Int],
    producer_id: Int,
    items_to_produce: Int,
    start_value: Int
):
    # Ogni produttore produce valori nel range [start_value, start_value + items_to_produce)
    for i in range(items_to_produce):
        var val = start_value + i
        while not queue.push(val):
            pass  # Riprova se la coda è piena
    print("Producer", producer_id, "completato:", items_to_produce, "elementi")


async fn consumer(
    mut queue: MPMC.MPMCQueue[Int],
    results_ptr: ScalarI64Pointer,   # Array dove results[x] = quante volte abbiamo ricevuto x
    consumed_ptr: ScalarU64Pointer,  # Contatore globale messaggi consumati
    threshold: UInt64,
    consumer_id: Int
):
    var consumed = 0
    
    while True:
        # Termina quando tutti i messaggi sono stati consumati
        var total_consumed = Atomic[DType.uint64].load(consumed_ptr)
        if total_consumed >= threshold:
            break
        
        var val = queue.pop()
        if val:
            var x = val.value()
            if x >= 0 and x < Int(threshold):
                # Incrementa atomicamente results[x] per tracciare la ricezione
                _ = Atomic[DType.int64].fetch_add(results_ptr + x, 1)
            _ = Atomic[DType.uint64].fetch_add(consumed_ptr, 1)
            consumed += 1
    
    print("Consumer", consumer_id, "completato:", consumed, "elementi consumati")


fn run_concurrent_mpmc_test(num_producers: Int, num_consumers: Int, items_per_producer: Int):
    var threshold = num_producers * items_per_producer

    print("\n" + "="*60)
    print("TEST CONCORRENTE MPMC - N PRODUTTORI / M CONSUMATORI")
    print("="*60)
    print("Produttori:", num_producers, "x", items_per_producer, "elementi ciascuno")
    print("Consumatori:", num_consumers)
    print("Totale messaggi:", threshold)
    print("Dimensione coda:", QUEUE_SIZE)
    print("="*60)
    
    var queue = MPMC.MPMCQueue[Int](size=QUEUE_SIZE)
    
    # Contatore atomico dei messaggi consumati (condiviso tra tutti i consumer)
    var consumed_ptr: ScalarU64Pointer = alloc[Scalar[DType.uint64]](1)
    consumed_ptr[] = 0
    
    # Array results: results[i] = quante volte il messaggio i è stato ricevuto
    # Alla fine deve essere 1 per ogni i (nessun messaggio perso o duplicato)
    var results_ptr: ScalarI64Pointer = alloc[Scalar[DType.int64]](threshold)
    for i in range(threshold):
        results_ptr[i] = 0
    
    print("\nAvvio del test...")
    var start_time = perf_counter_ns()
    
    var tg = TaskGroup()
    
    # Avvia i produttori - ogni produttore produce un range distinto di valori
    for i in range(num_producers):
        var start_val = i * items_per_producer
        tg.create_task(producer(queue, i, items_per_producer, start_val))
    
    # Avvia i consumatori - condividono la coda e i contatori atomici
    for i in range(num_consumers):
        tg.create_task(consumer(queue, results_ptr, consumed_ptr, threshold, i))
    
    print("Attendo completamento di tutti i task...")
    tg.wait()
    print("Tutti i task completati!")
    
    var end_time = perf_counter_ns()
    var duration_ms = Float64(end_time - start_time) / 1_000_000.0
    
    # Verifica: ogni results[i] deve essere esattamente 1
    print("\n" + "--------------------------------")
    print("VERIFICA DEI RISULTATI")
    print("--------------------------------")
    
    
    for i in range(threshold):
        var val = results_ptr[i]
        if val !=1:
            print("ERRORE: RESULTS[", i, "], Test fallito")
            
    
    print("\n" + "--------------------------------")
    print("RIEPILOGO")
    print("--------------------------------")
    print("Durata:", duration_ms, "ms")
    print("Throughput:", Float64(threshold) / (duration_ms / 1000.0), "msg/sec")
    print("Messaggi consumati:", Atomic[DType.uint64].load(consumed_ptr))


    consumed_ptr.free()
    results_ptr.free()


fn main():
    # Parsing degli argomenti da riga di comando
    # Uso: mojo run Testprof.mojo <num_produttori> <num_consumatori> <elementi_per_produttore>
    # Default: 4 produttori, 4 consumatori, 2500 elementi per produttore
    var args = argv()

    var num_producers = 4
    var num_consumers = 4
    var items_per_producer = 2500

    try:
        if len(args) >= 2:
            num_producers = atol(args[1])
        if len(args) >= 3:
            num_consumers = atol(args[2])
        if len(args) >= 4:
            items_per_producer = atol(args[3])
    except:
        print("Errore nel parsing degli argomenti, uso valori di default")

    print("--------------------------------")
    print("TEST SUITE PER MPMC QUEUE - VERIFICA CONCORRENZA")
    print("--------------------------------")
    print("Uso: mojo run Testprof.mojo [num_produttori] [num_consumatori] [elementi_per_produttore]")
    print("Valori utilizzati:", num_producers, "produttori,", num_consumers, "consumatori,", items_per_producer, "elementi/produttore")
    
    run_concurrent_mpmc_test(num_producers, num_consumers, items_per_producer)
    
    print("\n" + "--------------------------------")
    print("TEST COMPLETATO")
    print("--------------------------------")
