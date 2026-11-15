import HelmRuntime

extension NamespacedStore {
    /// In memory, not `UserDefaults.standard`: a test that writes into the real domain rearranges the sidebar,
    /// the panel or the shortcuts of whoever runs it. `values` are stored under the keys the namespace spells.
    static func scratch(_ values: [String: Any] = [:]) -> NamespacedStore {
        let backing = InMemoryKeyValueStore()
        for (key, value) in values { backing.set(value, forKey: "module.test.\(key)") }
        return NamespacedStore(namespace: "test", backing: backing)
    }
}
