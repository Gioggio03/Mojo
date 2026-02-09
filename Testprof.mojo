from runtime.asyncrt import TaskGroup
from os.atomic import Atomic
from time import perf_counter_ns
from sys.terminate import exit
#import Coda as MPMC
import MPMC_Queue as MPMC
#import MPMC_Queue_Padding as MPMC

# Puntatori per contatori atomici condivisi tra thread
comptime ScalarU64Pointer = UnsafePointer[Scalar[DType.uint64], MutExternalOrigin]
comptime ScalarI64Pointer = UnsafePointer[Scalar[DType.int64], MutExternalOrigin]

# Configurazione del test
comptime NUM_PRODUCERS = 4
comptime NUM_CONSUMERS = 4
comptime ITEMS_PER_PRODUCER = 2500
comptime THRESHOLD = NUM_PRODUCERS * ITEMS_PER_PRODUCER  # 10000 messaggi totali
comptime QUEUE_SIZE = 128

async fn producer(
    mut queue: MPMC.MPMCQueue[Int],
    producer_id: Int,
    items_to_produce: Int,
    start_value: Int):
    # Ogni produttore produce valori nel range [start_value, start_value + items_to_produce)
    for i in range(items_to_produce):
        var val = start_value + i
        while not queue.push(val):
            pass  # Riprova se la coda è piena
    print("Producer", producer_id, " completato: ", items_to_produce, " elementi prodotti")

async fn consumer(
    mut queue: MPMC.MPMCQueue[Int],
    results_ptr: ScalarI64Pointer, # Array dove results[x] = quante volte abbiamo ricevuto x
    consumed_ptr: ScalarU64Pointer, # Contatore globale messaggi consumati
    threshold: UInt64,
    consumer_id: Int):
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
            else:
                print("Errore di ricezione messaggio")
                exit(1)
            _ = Atomic[DType.uint64].fetch_add(consumed_ptr, 1)
            consumed += 1
    print("Consumer ", consumer_id, " completato: ", consumed, " elementi consumati")

fn run_concurrent_mpmc_test():
    print("\n" + "="*60)
    print("TEST CONCORRENTE MPMC - N PRODUTTORI / M CONSUMATORI")
    print("="*60)
    print("Produttori: ", NUM_PRODUCERS, " x ", ITEMS_PER_PRODUCER, " elementi ciascuno")
    print("Consumatori: ", NUM_CONSUMERS)
    print("Totale messaggi: ", THRESHOLD)
    print("Dimensione coda: ", QUEUE_SIZE)
    print("="*60)

    var queue = MPMC.MPMCQueue[Int](size=QUEUE_SIZE)

    # Contatore atomico dei messaggi consumati (condiviso tra tutti i consumer)
    var consumed_ptr: ScalarU64Pointer = alloc[Scalar[DType.uint64]](1)
    consumed_ptr[] = 0

    # Array results: results[i] = quante volte il messaggio i è stato ricevuto
    # Alla fine deve essere 1 per ogni i (nessun messaggio perso o duplicato)
    var results_ptr: ScalarI64Pointer = alloc[Scalar[DType.int64]](THRESHOLD)
    for i in range(THRESHOLD):
        results_ptr[i] = 0

    print("\nAvvio del test...")
    var start_time = perf_counter_ns()

    var tg = TaskGroup()

    # Avvia i produttori - ogni produttore produce un range distinto di valori
    for i in range(NUM_PRODUCERS):
        var start_val = i * ITEMS_PER_PRODUCER
        tg.create_task(producer(queue, i, ITEMS_PER_PRODUCER, start_val))

    # Avvia i consumatori - condividono la coda e i contatori atomici
    for i in range(NUM_CONSUMERS):
        tg.create_task(consumer(queue, results_ptr, consumed_ptr, THRESHOLD, i))

    print("Attendo completamento di tutti i task...")
    tg.wait()
    print("Tutti i task completati!")

    var end_time = perf_counter_ns()
    var duration_ms = Float64(end_time - start_time) / 1_000_000.0

    # Verifica: ogni results[i] deve essere esattamente 1
    print("\n" + "--------------------------------")
    print("VERIFICA DEI RISULTATI")
    print("--------------------------------")

    for i in range(THRESHOLD):
        var val = results_ptr[i]
        if val !=1:
            print("ERRORE: RESULTS[", i, "], Test fallito")
            exit(1)

    print("TEST SUPERATO CON SUCCESSO!")

    print("\n" + "--------------------------------")
    print("RIEPILOGO")
    print("--------------------------------")
    print("Durata: ", duration_ms, " ms")
    print("Throughput: ", Float64(THRESHOLD) / (duration_ms / 1000.0), " msg/sec")
    print("Messaggi consumati: ", Atomic[DType.uint64].load(consumed_ptr))

    consumed_ptr.free()
    results_ptr.free()

fn main():
    print("--------------------------------")
    print("TEST SUITE PER MPMC QUEUE - VERIFICA CONCORRENZA")
    print("--------------------------------")

    run_concurrent_mpmc_test()

    print("\n" + "--------------------------------")
    print("TEST COMPLETATO")
    print("--------------------------------")
