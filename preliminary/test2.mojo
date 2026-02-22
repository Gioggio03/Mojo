# file: test_queue_multi_producer.mojo
"""
Multi-Producer test: N producer, 1 consumer.
Verifica: no data loss, no duplicates.
"""

from ConcurrentQueue import ConcurrentQueue
from runtime.asyncrt import TaskGroup

async fn producer(
    mut queue: ConcurrentQueue[Int], 
    producer_id: Int, 
    items_per_producer: Int
):
    """Producer che inserisce items_per_producer elementi."""
    print("[Producer", producer_id, "] Starting")
    
    var start_value = producer_id * items_per_producer
    var count = 0
    
    for i in range(items_per_producer):
        var value = start_value + i
        _ = queue.push(value)
        count += 1
    
    print("[Producer", producer_id, "] Produced", count, "items")


async fn multi_producer_consumer(
    mut queue: ConcurrentQueue[Int],
    num_producers: Int,
    items_per_producer: Int
):
    """Consumer che verifica tutti gli items."""
    var expected_total = num_producers * items_per_producer
    print("[Consumer] Expecting", expected_total, "items from", num_producers, "producers")
    
    var received = List[Bool]()
    for _ in range(expected_total):
        received.append(False)
    
    var count = 0
    var duplicates = 0
    
    # Aspetta che tutti i producer chiudano
    while count < expected_total:
        var item = queue.try_pop()
        
        if item:
            var val = item.value()
            count += 1
            
            # Check duplicates
            if val < len(received):
                if received[val]:
                    duplicates += 1
                    print("[Consumer] DUPLICATE:", val)
                else:
                    received[val] = True
    
    # Conta missing items
    var missing = 0
    for i in range(len(received)):
        if not received[i]:
            missing += 1
            if missing <= 10:  # Stampa primi 10
                print("[Consumer] MISSING:", i)
    
    print("\n[Consumer] Results:")
    print("  Items received:", count)
    print("  Expected:", expected_total)
    print("  Duplicates:", duplicates)
    print("  Missing:", missing)
    
    if count == expected_total and duplicates == 0 and missing == 0:
        print("  ✅ All items received correctly!")
    else:
        print("  ❌ Data integrity FAILED!")


fn test_multi_producer(num_producers: Int, items_per_producer: Int):
    """Test con N producer."""
    print("\n╔════════════════════════════════════════╗")
    print("║  MULTI-PRODUCER:", num_producers, "producers,", items_per_producer, "items each")
    print("╚════════════════════════════════════════╝\n")
    
    var queue = ConcurrentQueue[Int]()
    var tg = TaskGroup()
    
    # Launch producers
    for i in range(num_producers):
        tg.create_task(producer(queue, i, items_per_producer))
    
    # Launch consumer (non aspetta close, conta items)
    tg.create_task(multi_producer_consumer(queue, num_producers, items_per_producer))
    
    tg.wait()


fn main():
    print("╔════════════════════════════════════════╗")
    print("║   MULTI-PRODUCER TESTS                ║")
    print("╚════════════════════════════════════════╝")
    
    test_multi_producer(2, 1000)   # 2 producer
    test_multi_producer(4, 500)    # 4 producer
    test_multi_producer(8, 250)    # 8 producer
    
    print("\n╔════════════════════════════════════════╗")
    print("║   MULTI-PRODUCER TESTS COMPLETED ✅   ║")
    print("╚════════════════════════════════════════╝")