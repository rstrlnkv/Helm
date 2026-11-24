import Foundation

/// The allocator's own books, for the tests that measure a per-object cost.
///
/// `size_in_use` from `malloc_zone_statistics` is what malloc has handed out
/// and not been given back — the number that moves when a loop keeps what it
/// only meant to look at. `MemoryFootprint.current()` is `phys_footprint`, what
/// the *process* costs the machine, and it can read flat across a fill that
/// really did allocate (Architecture/DiagnosticsLog.md § The memory trail).
public enum AllocatorBooks {

    /// Bytes malloc has out right now, across all zones of this process.
    public static func allocatedBytes() -> Int {
        var stats = malloc_statistics_t()
        malloc_zone_statistics(nil, &stats)
        return Int(stats.size_in_use)
    }
}
