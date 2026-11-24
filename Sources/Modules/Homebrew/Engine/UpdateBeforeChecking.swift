import Foundation
import HelmRuntime

/// Whether `brew outdated` may refresh Homebrew's catalogue first: the module's one
/// stored setting (`module.homebrew.updateBeforeChecking`, a Bool).
///
/// ARCHITECTURE.md § The one setting. Read at each query, never cached, so a
/// press on the toggle reaches the next Refresh. Reading writes nothing back.
public final class UpdateBeforeChecking: @unchecked Sendable {
    static let key = "updateBeforeChecking"
    private let store: NamespacedStore

    /// - Parameter store: the module's own namespace. A construction that has no use for
    ///   the stored value (a test of something else) passes `.inMemory`, which starts ON.
    public init(store: NamespacedStore) { self.store = store }

    /// A setting nothing persists, for a construction that is not about it.
    public static var inMemory: UpdateBeforeChecking {
        UpdateBeforeChecking(store: NamespacedStore(namespace: HomebrewEngine.moduleID,
                                                    backing: InMemoryKeyValueStore()))
    }

    public var isOn: Bool {
        get { store.bool(Self.key, default: true) }
        set { store.set(newValue, for: Self.key) }
    }
}
