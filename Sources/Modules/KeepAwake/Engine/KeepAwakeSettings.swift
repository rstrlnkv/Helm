import HelmRuntime

public struct KeepAwakeSettings {
    let store: NamespacedStore
    public init(store: NamespacedStore) { self.store = store }
    public var autoExternalDisplay: Bool { store.bool("autoExternalDisplay", default: false) }
    public var autoPower: Bool { store.bool("autoPower", default: false) }
    /// Per-app rules. Reads the new encoded form, falling back to the plain
    /// bundle-id list older versions wrote so nobody's apps disappear.
    public var appTriggers: [AppTrigger] {
        let encoded = store.string("autoAppRules", default: "")
        if !encoded.isEmpty { return AppTriggerRules.decode(encoded) }
        return AppTriggerRules.migrating(from: store.stringArray("autoApps"))
    }
    public var keepDisplayOn: Bool { store.bool("keepDisplayOn", default: false) }
    public var jiggleEnabled: Bool { store.bool("jiggleEnabled", default: false) }
    public var jiggleIntervalMinutes: Int { max(1, store.int("jiggleIntervalMinutes", default: 5)) }
    public var clamshellEnabled: Bool { store.bool("clamshellEnabled", default: false) }
    /// On by default, because `defaultDurationMinutes` is 0 — "indefinitely" —
    /// and nothing else in the module ever ends that session: the guard is the
    /// only reason an unattended Mac on battery stops being held awake. It can
    /// only ever stop keeping the machine awake, never start it.
    public var batteryGuardEnabled: Bool { store.bool("batteryGuardEnabled", default: true) }
    public var batteryGuardPercent: Int { store.int("batteryGuardPercent", default: 20) }
    public var defaultDurationMinutes: Int { store.int("defaultDurationMinutes", default: 0) }
}
