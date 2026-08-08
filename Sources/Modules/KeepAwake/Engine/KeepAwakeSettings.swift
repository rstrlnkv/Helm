import HelmRuntime

public struct KeepAwakeSettings {
    let store: NamespacedStore
    public init(store: NamespacedStore) { self.store = store }

    /// Every name this module has on disk, written down once.
    ///
    /// Seven of them were spelled again in the settings page and once more in the
    /// panel tile — with their defaults, and with the jiggle clamp below — so the
    /// module carried three copies of each in three targets. A drift in any one
    /// showed the person a switch in one position while the Mac acted on the
    /// other, and nothing in the build would have said so. `MenuBarLook` holds
    /// the same shape for the six keys the engine never reads.
    public enum Key {
        public static let autoExternalDisplay = "autoExternalDisplay"
        public static let autoPower = "autoPower"
        public static let autoAppRules = "autoAppRules"
        /// The plain bundle-id list older versions wrote. Read, never written.
        public static let autoApps = "autoApps"
        public static let keepDisplayOn = "keepDisplayOn"
        public static let jiggleEnabled = "jiggleEnabled"
        public static let jiggleIntervalMinutes = "jiggleIntervalMinutes"
        public static let clamshellEnabled = "clamshellEnabled"
        public static let batteryGuardEnabled = "batteryGuardEnabled"
        public static let batteryGuardPercent = "batteryGuardPercent"
        public static let defaultDurationMinutes = "defaultDurationMinutes"
    }

    public var autoExternalDisplay: Bool { store.bool(Key.autoExternalDisplay, default: false) }
    public func setAutoExternalDisplay(_ on: Bool) { store.set(on, for: Key.autoExternalDisplay) }

    public var autoPower: Bool { store.bool(Key.autoPower, default: false) }
    public func setAutoPower(_ on: Bool) { store.set(on, for: Key.autoPower) }

    /// Per-app rules. Reads the new encoded form, falling back to the plain
    /// bundle-id list older versions wrote so nobody's apps disappear.
    public var appTriggers: [AppTrigger] {
        let encoded = store.string(Key.autoAppRules, default: "")
        if !encoded.isEmpty { return AppTriggerRules.decode(encoded) }
        return AppTriggerRules.migrating(from: store.stringArray(Key.autoApps))
    }
    /// Encoded here, beside the decode above: the page used to spell the key and
    /// call `encode` itself, one target away from the only reader.
    public func setAppTriggers(_ triggers: [AppTrigger]) {
        store.set(AppTriggerRules.encode(triggers), for: Key.autoAppRules)
    }

    public var keepDisplayOn: Bool { store.bool(Key.keepDisplayOn, default: false) }
    public func setKeepDisplayOn(_ on: Bool) { store.set(on, for: Key.keepDisplayOn) }

    public var jiggleEnabled: Bool { store.bool(Key.jiggleEnabled, default: false) }
    public func setJiggleEnabled(_ on: Bool) { store.set(on, for: Key.jiggleEnabled) }

    /// Clamped on read, which is where it has to hold: the stepper cannot offer
    /// less than a minute, and a plist can say anything — and 0 is a nudge loop
    /// running as fast as the timer can wake up.
    public var jiggleIntervalMinutes: Int { max(1, store.int(Key.jiggleIntervalMinutes, default: 5)) }
    public func setJiggleIntervalMinutes(_ minutes: Int) {
        store.set(minutes, for: Key.jiggleIntervalMinutes)
    }

    public var clamshellEnabled: Bool { store.bool(Key.clamshellEnabled, default: false) }
    public func setClamshellEnabled(_ on: Bool) { store.set(on, for: Key.clamshellEnabled) }

    /// On by default, because `defaultDurationMinutes` is 0 — "indefinitely" —
    /// and nothing else in the module ever ends that session: the guard is the
    /// only reason an unattended Mac on battery stops being held awake. It can
    /// only ever stop keeping the machine awake, never start it.
    public var batteryGuardEnabled: Bool { store.bool(Key.batteryGuardEnabled, default: true) }
    public func setBatteryGuardEnabled(_ on: Bool) { store.set(on, for: Key.batteryGuardEnabled) }

    public var batteryGuardPercent: Int { store.int(Key.batteryGuardPercent, default: 20) }
    public func setBatteryGuardPercent(_ percent: Int) {
        store.set(percent, for: Key.batteryGuardPercent)
    }

    public var defaultDurationMinutes: Int { store.int(Key.defaultDurationMinutes, default: 0) }
    public func setDefaultDurationMinutes(_ minutes: Int) {
        store.set(minutes, for: Key.defaultDurationMinutes)
    }
}
