import Foundation
import HelmRuntime

public struct KeepAwakeSettings {
    let store: NamespacedStore
    public init(store: NamespacedStore) { self.store = store }

    /// Every name this module has on disk, written down once, so the page, the
    /// panel tile and the engine cannot drift into showing a switch in one
    /// position while the Mac acts on the other. `MenuBarLook` holds the same
    /// shape for the keys the engine never reads.
    public enum Key {
        public static let autoExternalDisplay = "autoExternalDisplay"
        public static let autoPower = "autoPower"
        static let autoAppRules = "autoAppRules"
        /// The plain bundle-id list older versions wrote. Read, never written.
        static let autoApps = "autoApps"
        static let keepDisplayOn = "keepDisplayOn"
        static let jiggleEnabled = "jiggleEnabled"
        static let jiggleIntervalMinutes = "jiggleIntervalMinutes"
        static let clamshellEnabled = "clamshellEnabled"
        static let batteryGuardEnabled = "batteryGuardEnabled"
        public static let batteryGuardPercent = "batteryGuardPercent"
        static let defaultDurationMinutes = "defaultDurationMinutes"
        static let timerEndsAutomation = "timerEndsAutomation"
        /// Not a preference — a note to the *next launch* that this app turned
        /// system sleep off and may not have turned it back on.
        static let clamshellGuard = "clamshellGuard"
    }

    public var autoExternalDisplay: Bool { store.bool(Key.autoExternalDisplay, default: false) }
    public func setAutoExternalDisplay(_ on: Bool) { store.set(on, for: Key.autoExternalDisplay) }

    public var autoPower: Bool { store.bool(Key.autoPower, default: false) }
    public func setAutoPower(_ on: Bool) { store.set(on, for: Key.autoPower) }

    /// What the file says about the app rules — **once**, for both the rules and
    /// the banner over them.
    ///
    /// Read separately, the two disagree in the migration case: a value of the
    /// wrong type under the rules key would migrate the legacy `autoApps` list
    /// and hold the Mac awake under a banner saying no app could be read.
    ///
    /// So there is one reading, and «unreadable» means no rules: the module fails
    /// toward the Mac sleeping and says so on screen. Absent and empty are not
    /// errors — «no apps chosen» is a legitimate thing for the file to say, and a
    /// banner on every fresh install would be the worse fault — and both migrate,
    /// because that is what an older file looks like.
    enum AppRulesReading {
        /// Something is stored under the rules key and nothing can read it: the
        /// wrong plist type, a string that is not rules, or more rules than this
        /// module will read (`AppTriggerRules.readable`).
        case unreadable
        case rules([AppTrigger])
    }

    var appRulesReading: AppRulesReading {
        guard let value = store.object(Key.autoAppRules) else { return migrated() }
        guard let encoded = value as? String else { return .unreadable }
        guard !encoded.isEmpty else { return migrated() }
        guard let rules = AppTriggerRules.readable(encoded) else { return .unreadable }
        return .rules(rules)
    }

    /// The older key, read only when the current one has nothing to say — this is
    /// on `recompute`'s path, which runs from three observers.
    private func migrated() -> AppRulesReading {
        guard let rules = AppTriggerRules.migrating(from: store.stringArray(Key.autoApps)) else {
            return .unreadable
        }
        return .rules(rules)
    }

    /// Per-app rules. Reads the new encoded form, falling back to the plain
    /// bundle-id list older versions wrote so nobody's apps disappear — and
    /// answering *nothing* for a file the banner is about to disown.
    public var appTriggers: [AppTrigger] {
        switch appRulesReading {
        case .unreadable: []
        case .rules(let rules): rules
        }
    }

    /// True when the file holds something under the rules key that nothing can
    /// read.
    ///
    /// `activate` says so once in the log, so somebody whose rules stopped
    /// holding the Mac awake has something to look at. Not from `appTriggers`
    /// itself: that is read from `recompute`, which runs from three observers.
    public var appRulesUnreadable: Bool {
        switch appRulesReading {
        case .unreadable: true
        case .rules: false
        }
    }

    /// Encoded here, beside the decode above, so the key and the encoding have
    /// one owner.
    public func setAppTriggers(_ triggers: [AppTrigger]) {
        store.set(AppTriggerRules.encode(triggers), for: Key.autoAppRules)
    }

    public var keepDisplayOn: Bool { store.bool(Key.keepDisplayOn, default: false) }
    public func setKeepDisplayOn(_ on: Bool) { store.set(on, for: Key.keepDisplayOn) }

    public var jiggleEnabled: Bool { store.bool(Key.jiggleEnabled, default: false) }
    public func setJiggleEnabled(_ on: Bool) { store.set(on, for: Key.jiggleEnabled) }

    /// Clamped on read, which is where it has to hold: the menu cannot offer
    /// less than a minute, and a plist can say anything — and 0 is a nudge loop
    /// running as fast as the timer can wake up.
    ///
    /// The ceiling is the same rule read the other way. `scheduleJiggle` does
    /// `minutes * 60`, which **traps** in Swift on overflow, so a stored
    /// `Int.max` is not a very long interval but the app terminating the moment
    /// a session with jiggle on starts. A day is the ceiling because a jiggle
    /// further apart than that is indistinguishable from the switch being off,
    /// and the menu's own top is 60.
    public var jiggleIntervalMinutes: Int {
        store.int(Key.jiggleIntervalMinutes, default: 5).clamped(to: 1...TimerPolicy.longestSessionMinutes)
    }
    public func setJiggleIntervalMinutes(_ minutes: Int) {
        store.set(minutes, for: Key.jiggleIntervalMinutes)
    }

    /// **Not sealed.** This is the one setting here that decides whether
    /// `sudo pmset disablesleep 1` runs, so it is exactly the shape the sealing
    /// rule is written for — a stored value steering privileged work nobody is
    /// watching.
    ///
    /// But a seal is read through the keychain, and this getter runs from
    /// `KeepAwakeEngine.init` and from `recompute`, on every display, charger and
    /// application event. **A released bundle is ad-hoc signed** (`package-app.sh`
    /// → `--sign -`, no Team ID; a local build is too unless this Mac names an
    /// identity (`signing-identity.sh` says where)), so its code identity changes
    /// with every build and a keychain ACL written by one build never matches the
    /// next: launch would stop behind a system keychain dialog on every install,
    /// and a person who dismisses it loses the lid feature with nothing on screen
    /// saying why. `AppSettings.disabledScans` seals fine because it is read
    /// rarely and never at launch.
    ///
    /// So it waits for a Developer ID. The mitigation meanwhile: the
    /// administrator dialog needs a gesture — only the lid switch's own, as
    /// `KeepAwakeEngine.lidSwitchTurned` reports it — so a forged value cannot
    /// raise a password prompt by itself. It can engage a grant the person
    /// already gave.
    public var clamshellEnabled: Bool { store.bool(Key.clamshellEnabled, default: false) }
    func setClamshellEnabled(_ on: Bool) { store.set(on, for: Key.clamshellEnabled) }

    /// On by default, because `defaultDurationMinutes` is 0 — "indefinitely" —
    /// and nothing else in the module ever ends that session: the guard is the
    /// only reason an unattended Mac on battery stops being held awake. It can
    /// only ever stop keeping the machine awake, never start it.
    public var batteryGuardEnabled: Bool { store.bool(Key.batteryGuardEnabled, default: true) }
    public func setBatteryGuardEnabled(_ on: Bool) { store.set(on, for: Key.batteryGuardEnabled) }

    /// Clamped to the slider's own range. A stored 0 or a negative leaves
    /// `percent <= threshold` unable to fire, which switches the guard off while
    /// the page still draws it on — and the guard is the only thing that ever
    /// ends an unattended session. A stored 101 ends every session on battery
    /// the moment it starts, which reads as the feature being broken.
    public var batteryGuardPercent: Int {
        store.int(Key.batteryGuardPercent, default: 20).clamped(to: 5...50)
    }
    public func setBatteryGuardPercent(_ percent: Int) {
        store.set(percent, for: Key.batteryGuardPercent)
    }

    /// 0 is "indefinitely" and stays reachable; the ceiling is
    /// `TimerPolicy.longestSessionMinutes`, the one `startSession` clamps to
    /// before it turns minutes into seconds. This is the length the panel's
    /// switch and the global shortcut start.
    public var defaultDurationMinutes: Int {
        store.int(Key.defaultDurationMinutes, default: 0).clamped(to: 0...TimerPolicy.longestSessionMinutes)
    }
    public func setDefaultDurationMinutes(_ minutes: Int) {
        store.set(minutes, for: Key.defaultDurationMinutes)
    }

    /// A timer set on top of an automatic session ends that session too, and
    /// the automation stays suppressed until its condition drops and comes
    /// back.
    ///
    /// Off by default, and deliberately: on by default would change what an
    /// existing timer does at the moment somebody updates, with nothing on
    /// screen having moved.
    ///
    /// Unclamped, unlike its neighbours, because a `Bool` off a plist is one of
    /// two answers whatever the file says — and the one it fails to leaves the
    /// rules alone.
    public var timerEndsAutomation: Bool {
        store.bool(Key.timerEndsAutomation, default: false)
    }
    public func setTimerEndsAutomation(_ on: Bool) {
        store.set(on, for: Key.timerEndsAutomation)
    }
}
