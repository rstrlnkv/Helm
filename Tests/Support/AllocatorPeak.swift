import Foundation

/// The allocator's high-water mark across a call, for the benchmarks that
/// measure a *transient* cost — the copy that lives only while a parse runs.
///
/// `AllocatorBooks.allocatedBytes()` before and after a call both read the same
/// when the waste is freed on return, which is exactly what makes a transient
/// invisible to a two-point measurement. A sampling thread reads the books
/// while the body runs; the peak minus the start is what the call held at its
/// worst. The sampler's own footprint is two fixed-size values and no
/// allocation in the loop.
public enum AllocatorPeak {

    public static func during<T>(_ body: () -> T) -> (result: T, peakOverStart: Int) {
        let start = AllocatorBooks.allocatedBytes()
        let box = PeakBox()
        let thread = Thread {
            while box.running {
                box.observe(AllocatorBooks.allocatedBytes())
                usleep(200)
            }
        }
        thread.qualityOfService = .userInteractive
        thread.start()
        let result = body()
        // The end state is a sample too: a body that returns faster than the
        // first tick must not read as free.
        box.observe(AllocatorBooks.allocatedBytes())
        box.stop()
        return (result, box.peak - start)
    }

    private final class PeakBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _peak = 0
        private var _running = true
        var running: Bool { lock.lock(); defer { lock.unlock() }; return _running }
        var peak: Int { lock.lock(); defer { lock.unlock() }; return _peak }
        func observe(_ bytes: Int) { lock.lock(); if bytes > _peak { _peak = bytes }; lock.unlock() }
        func stop() { lock.lock(); _running = false; lock.unlock() }
    }
}
