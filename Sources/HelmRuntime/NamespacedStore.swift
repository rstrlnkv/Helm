import Foundation

public protocol KeyValueStore: AnyObject {
    func object(forKey: String) -> Any?
    func set(_ value: Any?, forKey: String)
}

public final class InMemoryKeyValueStore: KeyValueStore {
    public var raw: [String: Any] = [:]
    public init() {}
    public func object(forKey k: String) -> Any? { raw[k] }
    public func set(_ v: Any?, forKey k: String) { raw[k] = v }
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
    public func stringArray(_ key: String) -> [String] { backing.object(forKey: k(key)) as? [String] ?? [] }
    /// A structure too shaped to be a plist: rules, with their conditions and
    /// actions, kept as JSON in one value rather than flattened into keys.
    public func data(_ key: String) -> Data? { backing.object(forKey: k(key)) as? Data }

    /// A per-app decision table: bundle id →
    /// yes/no, with absent meaning "no opinion".
    public func boolTable(_ key: String) -> [String: Bool] {
        backing.object(forKey: k(key)) as? [String: Bool] ?? [:]
    }
}

public extension Notification.Name {
    /// Posted when the user reorders modules, so the panel rebuilds.
    static let helmModuleOrderChanged = Notification.Name("helmModuleOrderChanged")
}
