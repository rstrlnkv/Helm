import HelmRuntime

public struct KeepAwakeSettings {
    let store: NamespacedStore
    public init(store: NamespacedStore) { self.store = store }
    public var autoExternalDisplay: Bool { store.bool("autoExternalDisplay", default: false) }
    public var autoPower: Bool { store.bool("autoPower", default: false) }
    public var autoApps: [String] { store.stringArray("autoApps") }
    public var keepDisplayOn: Bool { store.bool("keepDisplayOn", default: false) }
    public var jiggleEnabled: Bool { store.bool("jiggleEnabled", default: false) }
    public var jiggleIntervalMinutes: Int { max(1, store.int("jiggleIntervalMinutes", default: 5)) }
    public var clamshellEnabled: Bool { store.bool("clamshellEnabled", default: false) }
    public var batteryGuardEnabled: Bool { store.bool("batteryGuardEnabled", default: false) }
    public var batteryGuardPercent: Int { store.int("batteryGuardPercent", default: 20) }
    public var defaultDurationMinutes: Int { store.int("defaultDurationMinutes", default: 0) }
    public var activeTintColor: String { store.string("activeTintColor", default: "green") }
}
