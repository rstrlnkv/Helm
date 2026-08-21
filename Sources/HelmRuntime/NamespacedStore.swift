import Foundation

public protocol KeyValueStore: AnyObject {
    func object(forKey: String) -> Any?
    func set(_ value: Any?, forKey: String)
}

/// `UserDefaults` without the disk, for tests and for a module that has no
/// business persisting anything.
///
/// **Without the disk, not without the plist.** `UserDefaults` writes to a file
/// and reads it back, so every number it hands over is an `NSNumber` whatever
/// Swift type went in — and an `NSNumber` casts by value rather than by
/// declaration. `<integer>1</integer>` under a `Bool` key is `true` in
/// production; `<real>5.0</real>` under an `Int` key is `5`. Holding Swift
/// natives, this answered the module's *default* for both, which made every
/// wrong-type test in the suite a test of the fake: they proved a value was
/// refused that production accepts.
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
        set { lock.withLock { values = newValue.mapValues(Self.asAFileWouldHoldIt) } }
    }
    public init() {}
    public func object(forKey k: String) -> Any? { lock.withLock { values[k] } }
    public func set(_ v: Any?, forKey k: String) {
        lock.withLock { values[k] = v.map(Self.asAFileWouldHoldIt) }
    }

    /// The value a plist would give back, which is what the casts above this
    /// class are written against. Numbers become `NSNumber` — including the ones
    /// inside a list or a table, since a table of flags is written
    /// `<integer>1</integer>` too — and everything else is already itself.
    private static func asAFileWouldHoldIt(_ value: Any) -> Any {
        switch value {
        case let number as NSNumber: number
        case let list as [Any]: list.map(asAFileWouldHoldIt)
        case let table as [String: Any]: table.mapValues(asAFileWouldHoldIt)
        default: value
        }
    }
}

extension UserDefaults: KeyValueStore {}

public extension Notification.Name {
    /// Posted after any `NamespacedStore` write; `object` is the full namespaced
    /// key ("module.<id>.<key>"). Views that mirror stored values into `@State`
    /// observe this to stay in sync with other windows.
    static let helmStoreChanged = Notification.Name("helmStoreChanged")
}

public final class NamespacedStore {
    private let namespace: String
    private let prefix: String
    private let backing: KeyValueStore
    public init(namespace: String, backing: KeyValueStore) {
        self.namespace = namespace
        self.prefix = "module.\(namespace)."
        self.backing = backing
    }

    /// The same namespace over a different store.
    ///
    /// A migration needs both halves — this view to read and write its own keys,
    /// and the raw store `ObsoleteDefaults.purge` walks by full key — so it is
    /// handed the raw one and asks for this. Written here rather than as a second
    /// `NamespacedStore(namespace:)` at the call site: that would be the prefix
    /// spelled twice, and two spellings drifting is a migration writing where
    /// nothing reads. It is also the only way a test can point the app's own
    /// namespaced view at a store of its own.
    public func over(_ other: KeyValueStore) -> NamespacedStore {
        NamespacedStore(namespace: namespace, backing: other)
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
