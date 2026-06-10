/// Stack-allocated, fixed-capacity byte buffer.
/// Zero heap allocations — for building protocol messages.
#[derive(Clone)]
pub struct Buffer<const N: usize> {
    data: [u8; N],
    len: usize,
}

#[allow(dead_code)]
impl<const N: usize> Buffer<N> {
    #[inline]
    pub const fn new() -> Self {
        Self {
            data: [0u8; N],
            len: 0,
        }
    }

    #[inline]
    pub fn as_slice(&self) -> &[u8] {
        &self.data[..self.len]
    }

    #[inline]
    pub fn len(&self) -> usize {
        self.len
    }

    #[inline]
    pub fn is_empty(&self) -> bool {
        self.len == 0
    }

    #[inline]
    pub fn push(&mut self, byte: u8) {
        debug_assert!(self.len < N, "Buffer overflow: push beyond N={N}");
        self.data[self.len] = byte;
        self.len += 1;
    }

    #[inline]
    pub fn push_slice(&mut self, src: &[u8]) {
        let n = src.len();
        debug_assert!(
            self.len + n <= N,
            "Buffer overflow: push_slice {n} beyond N={N}"
        );
        self.data[self.len..self.len + n].copy_from_slice(src);
        self.len += n;
    }

    /// Fill `count` bytes with `byte`. Returns actual bytes written.
    #[inline]
    pub fn fill(&mut self, byte: u8, count: usize) -> usize {
        let n = count.min(N - self.len);
        self.data[self.len..self.len + n].fill(byte);
        self.len += n;
        n
    }

    #[inline]
    pub fn clear(&mut self) {
        self.len = 0;
    }

    /// Write a big-endian u16 at the current position.
    #[inline]
    pub fn push_u16_be(&mut self, v: u16) {
        self.push_slice(&v.to_be_bytes());
    }

    /// Write a big-endian u64 at the current position.
    #[inline]
    pub fn push_u64_be(&mut self, v: u64) {
        self.push_slice(&v.to_be_bytes());
    }
}

/// Fixed-capacity ring buffer for SPSC (single-producer, single-consumer)
/// communication. Zero allocations after construction. Thread-safe.
///
/// N must be a power of two.
pub struct Ring<T, const N: usize> {
    buf: [std::cell::UnsafeCell<std::mem::MaybeUninit<T>>; N],
    read_idx: std::sync::atomic::AtomicUsize,
    write_idx: std::sync::atomic::AtomicUsize,
}

// Safety: only one thread writes and one thread reads. The atomic counters
// provide happens-before ordering between producer and consumer.
unsafe impl<T: Send, const N: usize> Sync for Ring<T, N> {}

#[allow(dead_code)]
impl<T, const N: usize> Ring<T, N> {
    /// Create an empty ring. N must be a power of two (asserted at runtime
    /// in debug builds).
    pub fn new() -> Self {
        debug_assert!(N.is_power_of_two(), "Ring capacity must be power of two");
        Self {
            // SAFETY: MaybeUninit<[MaybeUninit<T>; N]> can be zeroed.
            buf: unsafe { std::mem::MaybeUninit::zeroed().assume_init() },
            read_idx: std::sync::atomic::AtomicUsize::new(0),
            write_idx: std::sync::atomic::AtomicUsize::new(0),
        }
    }

    /// Producer: try to enqueue an item. Returns `true` on success.
    #[inline]
    pub fn try_push(&self, item: T) -> Result<(), T> {
        use std::sync::atomic::Ordering;
        let write = self.write_idx.load(Ordering::Relaxed);
        let next = (write + 1) & (N - 1);
        if next == self.read_idx.load(Ordering::Acquire) {
            // Full: consumer hasn't caught up.
            return Err(item);
        }
        unsafe {
            (*self.buf[write].get()).write(item);
        }
        self.write_idx.store(next, Ordering::Release);
        Ok(())
    }

    /// Push, spinning until a slot is free. Use sparingly.
    #[inline]
    pub fn push(&self, mut item: T) {
        loop {
            match self.try_push(item) {
                Ok(()) => break,
                Err(returned_item) => {
                    item = returned_item;
                    std::hint::spin_loop();
                }
            }
        }
    }

    /// Consumer: try to dequeue an item. Returns `None` if empty.
    #[inline]
    pub fn try_pop(&self) -> Option<T> {
        use std::sync::atomic::Ordering;
        let read = self.read_idx.load(Ordering::Relaxed);
        if read == self.write_idx.load(Ordering::Acquire) {
            return None; // empty
        }
        let item = unsafe { (*self.buf[read].get()).assume_init_read() };
        self.read_idx.store((read + 1) & (N - 1), Ordering::Release);
        Some(item)
    }

    /// Pop, spinning until an item is available.
    #[inline]
    pub fn pop(&self) -> T {
        loop {
            if let Some(item) = self.try_pop() {
                return item;
            }
            std::hint::spin_loop();
        }
    }
}
