# file: ConcurrentQueue.mojo
"""
Thread-safe concurrent queue implementation.
"""

from collections import List
from Spinlock import SpinLock

struct ConcurrentQueue[T: AnyType & Copyable & Movable]:
    """
    Thread-safe FIFO queue using SpinLock.
    """
    var data: List[T]
    var lock: SpinLock
    var closed: Bool
    
    fn __init__(out self):
        """Initialize empty queue."""
        self.data = List[T]()
        self.lock = SpinLock()
        self.closed = False
    
    fn push(mut self, item: T) -> Bool:
        """
        Push item to queue (thread-safe).
        
        Args:
            item: Item to add (will be copied)
        
        Returns:
            True if successful, False if closed
        """
        self.lock.acquire()
        
        if self.closed:
            self.lock.release()
            return False
        
        # FIX: Usa .copy() esplicito
        self.data.append(item.copy())
        
        self.lock.release()
        return True
    
    fn try_pop(mut self) -> Optional[T]:
        """
        Pop item from queue (thread-safe).
        
        Returns:
            Item if available, None if empty
        """
        self.lock.acquire()
        
        if len(self.data) == 0:
            self.lock.release()
            return None
        
        # FIX: Usa .copy() esplicito
        var item = self.data[0].copy()
        _ = self.data.pop(0)
        
        self.lock.release()
        return item.copy()
    
    fn close(mut self):
        """Close queue (no more pushes allowed)."""
        self.lock.acquire()
        self.closed = True
        self.lock.release()
    
    fn is_closed(mut self) -> Bool:
        """Check if closed (thread-safe)."""
        self.lock.acquire()
        var result = self.closed
        self.lock.release()
        return result
    
    fn size(mut self) -> Int:
        """Get queue size (thread-safe)."""
        self.lock.acquire()
        var s = len(self.data)
        self.lock.release()
        return s
    
    fn is_empty(mut self) -> Bool:
        """Check if empty (thread-safe)."""
        return self.size() == 0