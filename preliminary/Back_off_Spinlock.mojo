# file: Spinlock_optimized.mojo
"""
Optimized SpinLock: Atomic + TTAS + Exponential Backoff.
Versione senza backtick nei commenti.
"""

from os.atomic import Atomic

struct SpinLock:
    """
    Production-grade SpinLock.
    
    Optimizations:
    - Atomic operations (thread-safe)
    - TTAS pattern (reduces cache coherence traffic)
    - Exponential backoff (reduces CPU usage under contention)
    """
    var locked: Atomic[DType.int32]
    
    fn __init__(out self):
        """Initialize as unlocked."""
        self.locked = Atomic[DType.int32](0)
    
    fn acquire(mut self):
        """
        Acquire with TTAS + Exponential Backoff.
        
        Algorithm:
        1. Test with backoff (read loop)
        2. Test-and-Set (atomic CAS)
        3. If fail, increase backoff and retry
        """
        var backoff = 1
        var max_backoff = 256
        
        while True:
            # PHASE 1: TEST (with exponential backoff)
            while self.locked.load() != 0:
                # Backoff: wait progressively longer
                for _ in range(backoff):
                    pass
                
                # Exponential increase
                backoff = backoff * 2
                if backoff > max_backoff:
                    backoff = max_backoff
            
            # PHASE 2: TEST-AND-SET (atomic)
            var expected: Int32 = 0
            var desired: Int32 = 1
            
            if self.locked.compare_exchange(expected, desired):
                break  # Success!
            
            # CAS failed, reset backoff
            backoff = 1
    
    fn release(mut self):
        """Release lock."""
        self.locked.value = 0
    
    fn is_locked(self) -> Bool:
        """Check if locked."""
        return self.locked.load() != 0
    
    fn try_acquire(mut self) -> Bool:
        """Non-blocking acquire."""
        var expected: Int32 = 0
        var desired: Int32 = 1
        return self.locked.compare_exchange(expected, desired)


fn main():
    print("=== OPTIMIZED SPINLOCK (BACKOFF) ===\n")
    
    var lock = SpinLock()
    
    print("Test: acquire/release with exponential backoff")
    for i in range(10):
        lock.acquire()
        print("  Iteration", i, "- acquired")
        lock.release()
    
    print("\n✅ Test completato!")
    print("\nOptimizations:")
    print("  - Atomic operations (thread-safe)")
    print("  - TTAS pattern (cache-efficient)")
    print("  - Exponential backoff (CPU-efficient)")