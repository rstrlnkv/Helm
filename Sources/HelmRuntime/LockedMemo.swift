import Foundation

/// **A table built once per key and kept.** One lock, one dictionary, and the
/// build under the lock.
///
/// There were four of these written by hand — the folder-name tables in
/// `SystemFolderNames`, the `.lproj` tables in `L10n`, the number formatters in
/// `HelmBytes` and the keyboard-layout tables in Layout's `SystemPorts` — three
/// of them under one name, and they had already stopped being the same thing:
/// two held the lock across the build and two let go of it to build and took it
/// again to store, so two threads asking for one key both did the work.
/// Idempotent tables, so nobody paid for it in wrong answers; it is here because
/// three copies of «the same thing» that are not the same thing is how the two
/// byte formatters started.
///
/// **The lock is held across the build on purpose.** The alternative saves
/// nothing worth having: every build here is a `.strings` file, a
/// `NumberFormatter` or fifty Carbon calls, all of them microseconds and none of
/// them re-entrant into this memo. Holding it makes «built once» a fact rather
/// than a likelihood, which is the difference the callers' comments all claimed
/// and only some of them had.
///
/// It is a `class` and not an `actor` because every caller is synchronous —
/// `Bytes(_:)` is called from a view body — and an actor would make each of them
/// `async` all the way up.
public final class LockedMemo<Key: Hashable, Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Key: Value] = [:]

    public init() {}

    /// The value for `key`, building it if this is the first ask.
    public func value(for key: Key, build: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        if let existing = stored[key] { return existing }
        let built = build()
        stored[key] = built
        return built
    }

    /// The same, for a build that can come back with nothing — **and nothing is
    /// not remembered.**
    ///
    /// A keyboard layout the system has not published yet is a port answering
    /// «not now», not «never»: storing that would make the first miss the answer
    /// for the life of the process, with no channel to say otherwise (CLAUDE.md
    /// § Anything that can stop being true on its own owns a channel to say so).
    public func valueOrNothing(for key: Key, build: () -> Value?) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        if let existing = stored[key] { return existing }
        guard let built = build() else { return nil }
        stored[key] = built
        return built
    }
}
