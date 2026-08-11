import Foundation
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
        public static let timerEndsAutomation = "timerEndsAutomation"
        /// Not a preference — a note to the *next launch* that this app turned
        /// system sleep off and may not have turned it back on. It was spelled
        /// as a literal at four sites inside the very file whose doc comment is
        /// about not spelling a key twice.
        public static let clamshellGuard = "clamshellGuard"
    }

    public var autoExternalDisplay: Bool { store.bool(Key.autoExternalDisplay, default: false) }
    public func setAutoExternalDisplay(_ on: Bool) { store.set(on, for: Key.autoExternalDisplay) }

    public var autoPower: Bool { store.bool(Key.autoPower, default: false) }
    public func setAutoPower(_ on: Bool) { store.set(on, for: Key.autoPower) }

    /// What the file says about the app rules — **once**, for both the rules and
    /// the banner over them.
    ///
    /// The two used to be read separately and disagreed in the migration case.
    /// `appTriggers` asked `store.string`, an `as? String`, so a value of the
    /// wrong type came back as the empty string, read as «nothing was ever
    /// written», and fell through to migrating the older `autoApps` list;
    /// `appRulesUnreadable` asked `store.object`, saw something that was not a
    /// string, and said so. A plist with an *array* under the rules key on a Mac
    /// that still has the legacy list therefore held the Mac awake on two rules
    /// under a banner saying no app could be read — and that file is one plist
    /// type away from ordinary, since `autoApps` *is* a `[String]`.
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
        .rules(AppTriggerRules.migrating(from: store.stringArray(Key.autoApps)))
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
    /// Somebody whose rules stopped holding the Mac awake had nothing to look at,
    /// so `activate` says so once. Not from `appTriggers` itself: that is read
    /// from `recompute`, which runs from three observers.
    public var appRulesUnreadable: Bool {
        switch appRulesReading {
        case .unreadable: true
        case .rules: false
        }
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
    ///
    /// The ceiling is the same rule read the other way. `scheduleJiggle` does
    /// `minutes * 60`, which **traps** in Swift on overflow, so a stored
    /// `Int.max` is not a very long interval but the app terminating the moment
    /// a session with jiggle on starts. A day is the ceiling because a jiggle
    /// further apart than that is indistinguishable from the switch being off,
    /// and the stepper's own top is 60.
    public var jiggleIntervalMinutes: Int {
        store.int(Key.jiggleIntervalMinutes, default: 5).clamped(to: 1...TimerPolicy.longestSessionMinutes)
    }
    public func setJiggleIntervalMinutes(_ minutes: Int) {
        store.set(minutes, for: Key.jiggleIntervalMinutes)
    }

    /// **Not sealed, and that was tried.** This is the one setting here that
    /// decides whether `sudo pmset disablesleep 1` runs, so it is exactly the
    /// shape the sealing rule is written for — a stored value steering
    /// privileged work nobody is watching.
    ///
    /// A `SettingGuard` over it was written, tested and then taken out, because
    /// on this app it cannot be read. Measured with `sample` on a real launch:
    /// the main thread sat in `SecItemCopyMatching` → `SecKeychainItemCopyContent`,
    /// called from this getter, called from `KeepAwakeEngine.init` — the app
    /// stopped at «enable keep-awake» and went no further, behind a system
    /// keychain dialog. **The bundle is ad-hoc signed** (`package-app.sh` →
    /// `--sign -`, no Team ID), so its code identity changes with every build
    /// and a keychain ACL written by one build never matches the next; that
    /// dialog is not a one-off, it is every install. And a person who dismisses
    /// it loses the lid feature with nothing on screen saying why.
    ///
    /// `AppSettings.disabledScans` seals fine because it is read rarely and
    /// never at launch. This one is read from `recompute`, which runs on every
    /// display, charger and application event.
    ///
    /// So it waits for a Developer ID — the same purchase CLAUDE.md says is
    /// blocking `NEVPNManager`, an `SMAppService` helper, notarization and TCC
    /// grants surviving an install. Until then the plist is what it is, and the
    /// mitigation that *did* ship is the one that matters most: the
    /// administrator dialog needs a gesture, so a forged value cannot summon a
    /// password prompt — it can only engage a grant the person already gave.
    public var clamshellEnabled: Bool { store.bool(Key.clamshellEnabled, default: false) }
    public func setClamshellEnabled(_ on: Bool) { store.set(on, for: Key.clamshellEnabled) }

    /// On by default, because `defaultDurationMinutes` is 0 — "indefinitely" —
    /// and nothing else in the module ever ends that session: the guard is the
    /// only reason an unattended Mac on battery stops being held awake. It can
    /// only ever stop keeping the machine awake, never start it.
    public var batteryGuardEnabled: Bool { store.bool(Key.batteryGuardEnabled, default: true) }
    public func setBatteryGuardEnabled(_ on: Bool) { store.set(on, for: Key.batteryGuardEnabled) }

    /// Clamped to the stepper's own range. A stored 0 or a negative leaves
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

    /// 0 is "indefinitely" and stays reachable; the ceiling is `jiggleInterval`'s
    /// reason one field over — `startSession` turns these minutes into seconds
    /// with the same trapping multiply, and it is reached from the panel tile's
    /// main button.
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
    /// screen having moved. The changelog invites it instead.
    ///
    /// Unclamped, unlike its neighbours, because a `Bool` off a plist is one of
    /// two answers whatever the file says — and the answer this setting fails
    /// to is the one that keeps today's behaviour.
    public var timerEndsAutomation: Bool {
        store.bool(Key.timerEndsAutomation, default: false)
    }
    public func setTimerEndsAutomation(_ on: Bool) {
        store.set(on, for: Key.timerEndsAutomation)
    }
}
