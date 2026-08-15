import Foundation

/// The allocator's own books, for the tests that measure a per-object cost.
///
/// `size_in_use` from `malloc_zone_statistics` is what malloc has handed out
/// and not been given back — the number that moves when a loop keeps what it
/// only meant to look at. `MemoryFootprint.current()` is `phys_footprint`, what
/// the *process* costs the machine, and it can read flat across a fill that
/// really did allocate: measured at 145 bytes an entry alone, 0 KB in its own
/// class, and it passed with a kilobyte of ballast per entry added (CLAUDE.md
/// § A per-object memory cost). Three benchmarks had written this five-liner
/// privately before it moved here, which is the note such a spread is.
public enum AllocatorBooks {

    /// Bytes malloc has out right now, across all zones of this process.
    public static func allocatedBytes() -> Int {
        var stats = malloc_statistics_t()
        malloc_zone_statistics(nil, &stats)
        return Int(stats.size_in_use)
    }
}
