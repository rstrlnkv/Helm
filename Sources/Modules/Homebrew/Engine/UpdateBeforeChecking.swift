import Foundation
import HelmRuntime

/// Whether `brew outdated` may refresh Homebrew's catalogue first: the module's one
/// stored setting (`module.homebrew.updateBeforeChecking`, a Bool).
///
/// **ON is today's behaviour** and what a store with no key, or a value that is not
/// a Bool, reads as: the query runs with no environment and brew refreshes as it
/// always did. OFF runs it with `HomebrewEngine.queryEnvironment`, so an answer comes
/// from the catalogue brew already holds. Read at each query, never cached, so a press
/// on the toggle reaches the next Refresh. Reading writes nothing back.
///
/// Not sealed: `outdated` has no caller that runs unattended (only a person's view of
/// the Updates tab asks it), so there is no unattended work for a seal to protect.
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
