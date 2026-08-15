import Foundation

/// The last value a `@Sendable` progress callback reported.
///
/// A scanner's progress closure is `@Sendable`, so the count it reports cannot
/// land in a captured `var`: one lock, one `Int`, written from whatever thread
/// the walk runs on and read by the test after the call returns. Hand-written
/// twice — Disk's `ScanFootprintTests` and Duplicates' `WalkFootprintTests`,
/// under a comment calling it «the same box next door» — before it moved here,
/// which is the note CLAUDE.md says such a comment is.
public final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0

    public init() {}

    public func record(_ n: Int) {
        lock.lock()
        stored = n
        lock.unlock()
    }

    public var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}
