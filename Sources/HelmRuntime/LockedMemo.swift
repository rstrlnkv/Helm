import Foundation

/// **A table built once per key and kept.** One lock, one dictionary, and the
/// build under the lock.
///
/// Shared by the folder-name tables in `SystemFolderNames`, the number
/// formatters in `HelmBytes` and the keyboard-layout tables in Layout's
/// `SystemPorts`, so they cannot drift into different things under one name.
///
/// **The lock is held across the build on purpose.** Every build here is small
/// (a `NumberFormatter`, an image, one `.strings` file, a few Carbon calls) and
/// none re-enters this memo, so holding it makes «built once» a fact rather
/// than a likelihood.
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
    /// for the life of the process, with no channel to say otherwise (Architecture/ModulePattern.md
    /// § Ports and logic).
    public func valueOrNothing(for key: Key, build: () -> Value?) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        if let existing = stored[key] { return existing }
        guard let built = build() else { return nil }
        stored[key] = built
        return built
    }
}
