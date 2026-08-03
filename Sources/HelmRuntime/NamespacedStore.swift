import Foundation

public protocol KeyValueStore: AnyObject {
    func object(forKey: String) -> Any?
    func set(_ value: Any?, forKey: String)
}

/// `UserDefaults` without the disk, for tests and for a module that has no
/// business persisting anything.
///
/// Locked, because the thing it stands in for is safe to touch from any thread
/// and the engines handed one are not single-threaded: they read their own state
/// from their own queues while the test that owns them writes from its. A bare
/// `Dictionary` under two threads is undefined behaviour rather than a race with
/// a bad answer — it took the Autopilot bundle down with no assertion and no
/// message, about once in thirty runs under load, until the thread sanitizer
/// named it.
public final class InMemoryKeyValueStore: KeyValueStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any] = [:]
    /// The whole map, which tests plant into and read back. `raw[k] = v` is a
    /// read and a write of this property, so it is two critical sections rather
    /// than one — enough to keep the dictionary intact, which is what is at
    /// stake here.
    public var raw: [String: Any] {
        get { lock.withLock { values } }
        set { lock.withLock { values = newValue } }
    }
    public init() {}
    public func object(forKey k: String) -> Any? { lock.withLock { values[k] } }
    public func set(_ v: Any?, forKey k: String) { lock.withLock { values[k] = v } }
}

extension UserDefaults: KeyValueStore {}

public extension Notification.Name {
    /// Posted after any `NamespacedStore` write; `object` is the full namespaced
    /// key ("module.<id>.<key>"). Views that mirror stored values into `@State`
    /// observe this to stay in sync with other windows.
    static let helmStoreChanged = Notification.Name("helmStoreChanged")
}

public final class NamespacedStore {
    private let prefix: String
    private let backing: KeyValueStore
    public init(namespace: String, backing: KeyValueStore) {
        self.prefix = "module.\(namespace)."
        self.backing = backing
    }
    private func k(_ key: String) -> String { prefix + key }
    public func set(_ value: Any?, for key: String) {
        backing.set(value, forKey: k(key))
        // Observers mirror values into SwiftUI @State, so the announcement must
        // arrive on the main thread regardless of who wrote (e.g. the clamshell
        // sudoers callback writes from a background queue).
        let key = k(key)
        if Thread.isMainThread {
            NotificationCenter.default.post(name: .helmStoreChanged, object: key)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .helmStoreChanged, object: key)
            }
        }
    }

    /// True when `note` announces a change to `key` in this store.
    public func changed(_ note: Notification, is key: String) -> Bool {
        (note.object as? String) == k(key)
    }
    public func bool(_ key: String, default d: Bool) -> Bool { backing.object(forKey: k(key)) as? Bool ?? d }
    public func int(_ key: String, default d: Int) -> Int { backing.object(forKey: k(key)) as? Int ?? d }
    public func string(_ key: String, default d: String) -> String { backing.object(forKey: k(key)) as? String ?? d }
    /// For a stored `Date`, which is a `Double` and not an `Int`. Rounding an
    /// epoch to the second makes a restored deadline differ from the one that was
    /// written — a session that comes back a fraction of a second off is a session
    /// whose stored end is no longer its real end.
    public func double(_ key: String, default d: Double) -> Double {
        backing.object(forKey: k(key)) as? Double ?? d
    }
    public func stringArray(_ key: String) -> [String] { backing.object(forKey: k(key)) as? [String] ?? [] }
    /// A structure too shaped to be a plist: rules, with their conditions and
    /// actions, kept as JSON in one value rather than flattened into keys.
    public func data(_ key: String) -> Data? { backing.object(forKey: k(key)) as? Data }

    /// A per-app decision table: bundle id →
    /// yes/no, with absent meaning "no opinion".
    /// The raw value, for the one question the typed accessors cannot answer:
    /// **has this key ever been written?** They all take a default, so "never
    /// set" and "set to the default" arrive the same — and a list whose empty
    /// state is meaningful (nothing switched off) needs to tell those apart from
    /// its own first launch.
    public func object(_ key: String) -> Any? { backing.object(forKey: k(key)) }

    /// A keyed table of numbers, beside `boolTable` and for the same reason:
    /// per-scan bookkeeping is one entry per module, and a key per module would
    /// be a namespace nobody can enumerate.
    public func doubleTable(_ key: String) -> [String: Double] {
        backing.object(forKey: k(key)) as? [String: Double] ?? [:]
    }

    public func intTable(_ key: String) -> [String: Int] {
        backing.object(forKey: k(key)) as? [String: Int] ?? [:]
    }

    public func boolTable(_ key: String) -> [String: Bool] {
        backing.object(forKey: k(key)) as? [String: Bool] ?? [:]
    }
}

public extension Notification.Name {
    /// Posted when the user reorders modules, so the panel rebuilds.
    static let helmModuleOrderChanged = Notification.Name("helmModuleOrderChanged")
}
