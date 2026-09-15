import Foundation

/// What one call *asked* the allocator for, on the calling thread alone.
///
/// `AllocatorBooks.allocatedBytes()` answers for the whole process and counts
/// what malloc is holding at that instant, so a high-water sampled over it is
/// two things at once: what the call asked for, and what the process and the
/// sampler happened to be doing while it ran. Measured on
/// `OutdatedQueryAllocationBenchmark`'s own payload, same code: the sampled
/// high-water reads 50–51 MB where that case is the only one in the process and
/// 58–63 MB where 235 other cases ran first — and it moves 5 MB between rounds
/// of the same process whose requests were identical to the byte.
///
/// So this counts the requests instead: every `malloc`, `calloc` and `realloc`
/// made on this thread while the body runs, by the size the *caller* asked for.
/// A second copy of a payload is a request for the payload's bytes, and a
/// request is the same request whatever the heap was doing beforehand —
/// measured identical to the byte across rounds in both of those processes.
///
/// What it does not see: another thread's work (hand the measurement to the
/// thread that does the work), memory the kernel gives out directly through
/// `vm_allocate` or a mapped file, and the difference between a byte asked for
/// and a byte kept — a call that asks for a copy and frees it again reads the
/// same as one that holds it, which is what makes this a guard on *cost* rather
/// than on residency.
///
/// The hook is libmalloc's `malloc_logger`, the slot MallocStackLogging
/// installs into. It is not a declared interface, so `during` throws rather
/// than answering zero when the slot cannot be found, and throws again rather
/// than measure two calls at once through one set of counters: a benchmark
/// reading "nothing was allocated" over a call nobody measured is a guard that
/// cannot fail.
public enum ThreadAllocations {

    /// One call's requests, in bytes.
    public struct Reading: Sendable {
        /// Every byte asked for during the call, kept or freed. A buffer grown
        /// by doubling counts each size it passed through — this is what the
        /// call cost the allocator, not what it was holding at any instant.
        public let requested: Int
        /// How many requests were made.
        public let requests: Int
        /// The largest single request.
        public let largestRequest: Int
        /// Bytes asked for in requests of `blockFloor` or more — the part of
        /// the total a whole-payload copy has to land in, with the per-item
        /// small change of a decode left out.
        public let requestedInBlocks: Int
        /// How many requests were that large.
        public let blocks: Int
        /// The size a request has to reach to count as a block here.
        public let blockFloor: Int
    }

    /// Why a reading could not be taken. Never folded into a zero reading —
    /// see the note on the hook above.
    public enum Unmeasurable: Error, CustomStringConvertible {
        /// libmalloc's undeclared `malloc_logger` slot was not where it has
        /// always been.
        case noHook
        /// A measurement was already running: one set of counters cannot
        /// answer for two calls, and the second would silently take the first's.
        case alreadyMeasuring

        public var description: String {
            switch self {
            case .noHook:
                return "libmalloc's malloc_logger slot could not be found, so nothing "
                     + "here can be measured"
            case .alreadyMeasuring:
                return "a ThreadAllocations measurement is already running; these "
                     + "counters answer for one call at a time"
            }
        }
    }

    /// Runs `body` with the calling thread's requests counted.
    ///
    /// Synchronous by construction: the count belongs to the thread that calls
    /// this, so work the body hands to a queue or another thread is not in the
    /// reading.
    public static func during<T>(countingBlocksOfAtLeast blockFloor: Int,
                                 _ body: () -> T) throws -> (result: T, reading: Reading) {
        guard let slot = loggerSlot() else { throw Unmeasurable.noHook }
        try entry.lock()
        defer { entry.unlock() }
        let previous = slot.pointee
        floor = blockFloor
        requested = 0
        requests = 0
        largest = 0
        blockBytes = 0
        blockCount = 0
        target = pthread_self()
        slot.pointee = record
        let result = body()
        slot.pointee = previous
        target = nil
        return (result, Reading(requested: requested,
                                requests: requests,
                                largestRequest: largest,
                                requestedInBlocks: blockBytes,
                                blocks: blockCount,
                                blockFloor: blockFloor))
    }

    // MARK: - The hook

    /// `malloc_logger_t`: type, arg1, arg2, arg3, result, frames-to-skip.
    private typealias Logger = @convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void

    /// libmalloc's own type bits: 2 marks an allocation and 4 a deallocation,
    /// and a `realloc` carries both — which is why the size has to be read from
    /// a different argument when both are set.
    private static let allocated: UInt32 = 2
    private static let deallocated: UInt32 = 4

    // Only the measuring thread writes these; every other thread leaves at the
    // first guard in `record`. `nonisolated(unsafe)` because a C hook takes no
    // context to carry them in.
    /// One measurement at a time, and the second asks rather than waits.
    private static let entry = SingleMeasurement()

    private final class SingleMeasurement: @unchecked Sendable {
        private let mutex = NSLock()
        private var busy = false
        func lock() throws {
            mutex.lock()
            defer { mutex.unlock() }
            guard !busy else { throw Unmeasurable.alreadyMeasuring }
            busy = true
        }
        func unlock() {
            mutex.lock()
            busy = false
            mutex.unlock()
        }
    }

    private nonisolated(unsafe) static var target: pthread_t?
    private nonisolated(unsafe) static var floor = 0
    private nonisolated(unsafe) static var requested = 0
    private nonisolated(unsafe) static var requests = 0
    private nonisolated(unsafe) static var largest = 0
    private nonisolated(unsafe) static var blockBytes = 0
    private nonisolated(unsafe) static var blockCount = 0

    /// Allocates nothing itself: libmalloc calls this from inside `malloc`, and
    /// an allocation here would be that same call again.
    private static let record: Logger = { type, _, arg2, arg3, _, _ in
        guard let mine = target, pthread_equal(pthread_self(), mine) != 0 else { return }
        guard (type & ThreadAllocations.allocated) != 0 else { return }
        // A `realloc` spells its arguments old-pointer-then-new-size; a plain
        // allocation carries its size where the pointer would be.
        let isReallocation = (type & ThreadAllocations.deallocated) != 0
        let size = Int(bitPattern: isReallocation ? arg3 : arg2)
        guard size > 0 else { return }
        ThreadAllocations.requested += size
        ThreadAllocations.requests += 1
        if size > ThreadAllocations.largest { ThreadAllocations.largest = size }
        if size >= ThreadAllocations.floor {
            ThreadAllocations.blockBytes += size
            ThreadAllocations.blockCount += 1
        }
    }

    /// The address of libmalloc's `malloc_logger` variable, or nil.
    private static func loggerSlot() -> UnsafeMutablePointer<Logger?>? {
        // RTLD_DEFAULT: the symbol is exported by libsystem_malloc, which is in
        // every process already.
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc_logger")
        else { return nil }
        return symbol.assumingMemoryBound(to: Logger?.self)
    }
}
