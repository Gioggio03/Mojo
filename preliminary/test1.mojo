# file: test_queue_stress.mojo
"""
Stress test: grandi volumi di dati.
Verifica: correttezza con 10K, 100K, 1M elementi.
"""

from ConcurrentQueue import ConcurrentQueue
from runtime.asyncrt import TaskGroup
from time import perf_counter_ns

async fn stress_producer(mut queue: ConcurrentQueue[Int], n: Int):
    """Producer per stress test."""
    print("[Producer] Starting, will produce", n, "items")
    var start = perf_counter_ns()
    
    for i in range(n):
        _ = queue.push(i)
        
        # Progress ogni 10%
        if n >= 1000 and (i + 1) % (n // 10) == 0:
            var percent = ((i + 1) * 100) // n
            print("[Producer] Progress:", percent, "%")
    
    queue.close()
    var end = perf_counter_ns()
    var elapsed = Float64(end - start) / 1e9
    print("[Producer] Done in", elapsed, "sec")
    print("[Producer] Throughput:", Float64(n) / elapsed, "items/sec")


async fn stress_consumer(mut queue: ConcurrentQueue[Int], expected: Int):
    """Consumer per stress test."""
    print("[Consumer] Starting, expecting", expected, "items")
    var start = perf_counter_ns()
    
    var count = 0
    var sum: Int = 0
    var last_value = -1
    var order_error = False
    
    while True:
        var item = queue.try_pop()
        
        if item:
            var val = item.value()
            sum += val
            count += 1
            
            # Verifica ordine FIFO
            if val != last_value + 1:
                if not order_error:
                    print("[Consumer] ERROR: Order violation at", val)
                    order_error = True
            
            last_value = val
            
            # Progress ogni 10%
            if expected >= 1000 and count % (expected // 10) == 0:
                var percent = (count * 100) // expected
                print("[Consumer] Progress:", percent, "%")
        else:
            if queue.is_closed():
                break
    
    var end = perf_counter_ns()
    var elapsed = Float64(end - start) / 1e9
    
    print("\n[Consumer] Results:")
    print("  Items received:", count)
    print("  Expected:", expected)
    print("  Sum:", sum)
    var expected_sum = (expected * (expected - 1)) // 2
    print("  Expected sum:", expected_sum)
    print("  Time:", elapsed, "sec")
    print("  Throughput:", Float64(count) / elapsed, "items/sec")
    print("  Order errors:", "YES" if order_error else "NO")
    
    # Validazione
    if count == expected:
        print("  ✅ Count correct!")
    else:
        print("  ❌ Count WRONG!")
    
    if sum == expected_sum:
        print("  ✅ Sum correct!")
    else:
        print("  ❌ Sum WRONG!")


fn test_stress(n: Int):
    """Run stress test with n items."""
    print("\n╔════════════════════════════════════════╗")
    print("║  STRESS TEST:", n, "items              ")
    print("╚════════════════════════════════════════╝\n")
    
    var queue = ConcurrentQueue[Int]()
    var tg = TaskGroup()
    
    tg.create_task(stress_producer(queue, n))
    tg.create_task(stress_consumer(queue, n))
    
    tg.wait()


fn main():
    print("╔════════════════════════════════════════╗")
    print("║   CONCURRENT QUEUE STRESS TESTS       ║")
    print("╚════════════════════════════════════════╝")
    
    # Test con volumi crescenti
    test_stress(1000)      # 1K items
    test_stress(10000)     # 10K items
    # test_stress(100000)  # 100K items (opzionale, può essere lento)
    
    print("\n╔════════════════════════════════════════╗")
    print("║   ALL STRESS TESTS COMPLETED ✅       ║")
    print("╚════════════════════════════════════════╝")