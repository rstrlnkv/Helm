// Removed after the design review and before the next release, with
// `-HelmKeepAwakeSample` and the branch in `KeepAwakeDescriptor.makeEngine`:
// the argument exists so each state of this module can be put on screen and
// photographed before and after the page is redrawn.
//
// A sample is a picture, not a state the Mac is in. It builds no `KeepAwakeEngine`
// and no port, so no assertion, `pmset` or sudoers rule is reachable; it writes only
// the in-memory store it is handed. Its engine says `standsIn`, so the host refuses
// to switch the module off or reset everything while it is live: either would write
// the real `enabled` flag and skip the hand-back. A sample's name is matched against
// `rawValue`s and never drawn: every visible word is a shipped string the real view
// picks from the data. App names come from the system (the sample rules use Apple's
// own bundle ids), except that `worst` has one row with `com.apple.sample.not-installed`,
// which no app answers to, so that row draws the bundle id itself, on purpose.

import Foundation
import HelmContract
import HelmRuntime
import Module_KeepAwake_Engine

enum KeepAwakeSample: String, CaseIterable {
    case idleNoRules = "idle-no-rules", idleWaiting = "idle-waiting", timedLong = "timed-long"
    case timedThenHeld = "timed-then-held", indefinite, automaticApps = "automatic-apps"
    case stopTwoStep = "stop-two-step", suppressed, batteryVeto = "battery-veto"
    case lidRefused = "lid-refused", leftBehind = "left-behind", worst

    static let argument = "-HelmKeepAwakeSample"
    static let key = "HelmKeepAwakeSample"

    enum Verdict: Equatable { case none, show(KeepAwakeSample), unknown(String), noName }

    /// Read from the argument domain only: `string(forKey:)` falls through to the
    /// persistent domain, so a `defaults write` of the key would turn samples on
    /// at every launch.
    static func verdict(argumentDomain: [String: Any], argv: [String]) -> Verdict {
        guard let name = argumentDomain[key] as? String else {
            return argv.contains(argument) ? .noName : .none
        }
        return KeepAwakeSample(rawValue: name).map(Verdict.show) ?? .unknown(name)
    }

    private static let safari = "com.apple.Safari", notes = "com.apple.Notes"
    private static let terminal = "com.apple.Terminal", textEdit = "com.apple.TextEdit"
    private static let preview = "com.apple.Preview", music = "com.apple.Music"
    private static let mail = "com.apple.mail"
    /// Names nothing installed, so one rule row shows an app the Mac does not have.
    private static let absent = "com.apple.sample.not-installed"

    private var rules: [AppTrigger] {
        switch self {
        case .automaticApps:
            [AppTrigger(bundleID: Self.safari), AppTrigger(bundleID: Self.notes, needsPower: true),
             AppTrigger(bundleID: Self.terminal, needsExternalDisplay: true)]
        case .worst:
            [AppTrigger(bundleID: Self.safari), AppTrigger(bundleID: Self.notes, needsPower: true),
             AppTrigger(bundleID: Self.terminal, needsExternalDisplay: true),
             AppTrigger(bundleID: Self.textEdit, needsExternalDisplay: true, needsPower: true),
             AppTrigger(bundleID: Self.preview), AppTrigger(bundleID: Self.music, needsPower: true),
             AppTrigger(bundleID: Self.mail), AppTrigger(bundleID: Self.absent)]
        default: []
        }
    }

    func payload(now: Date) -> KeepAwakeEngine.StatePayload {
        func minutes(_ m: Int) -> (end: Date, start: Date) { (now.addingTimeInterval(Double(m) * 60), now) }
        switch self {
        case .idleNoRules, .idleWaiting, .leftBehind:
            return .init(isActive: false, conditions: [], clamshellActive: false,
                         endDate: nil, startDate: nil, suppressed: false,
                         lidGrantRemains: self == .leftBehind)
        case .timedLong:
            let end = now.addingTimeInterval(Double(TimerPolicy.longestSessionMinutes * 60 - 1))
            return .init(isActive: true, conditions: ["manual", "timer"], clamshellActive: false,
                         endDate: end, startDate: now, suppressed: false)
        case .timedThenHeld:
            let t = minutes(47)
            return .init(isActive: true, conditions: ["manual", "power", "timer"], clamshellActive: false,
                         endDate: t.end, startDate: t.start, suppressed: false,
                         triggeredConditions: ["power"])
        case .indefinite:
            return .init(isActive: true, conditions: ["manual"], clamshellActive: false,
                         endDate: nil, startDate: nil, suppressed: false)
        case .automaticApps:
            return .init(isActive: true, conditions: ["app", "power"], clamshellActive: false,
                         endDate: nil, startDate: nil, suppressed: false,
                         triggeredConditions: ["app", "power"],
                         holdingApps: [Self.safari, Self.notes])
        case .stopTwoStep:
            let t = minutes(30)
            return .init(isActive: true, conditions: ["manual", "power", "timer"], clamshellActive: false,
                         endDate: t.end, startDate: t.start, suppressed: false,
                         triggeredConditions: ["power"])
        case .suppressed:
            return .init(isActive: false, conditions: [], clamshellActive: false,
                         endDate: nil, startDate: nil, suppressed: true,
                         triggeredConditions: ["power"])
        case .batteryVeto:
            return .init(isActive: false, conditions: [], clamshellActive: false,
                         endDate: nil, startDate: nil, suppressed: true,
                         triggeredConditions: ["power"], batteryStopped: true)
        case .lidRefused:
            return .init(isActive: true, conditions: ["manual"], clamshellActive: false,
                         endDate: nil, startDate: nil, suppressed: false, lidRefused: true)
        case .worst:
            return .init(isActive: true, conditions: ["app", "externalDisplay", "power"],
                         clamshellActive: true, endDate: nil, startDate: nil, suppressed: false,
                         triggeredConditions: ["app", "externalDisplay", "power"],
                         holdingApps: [Self.safari, Self.notes, Self.terminal, Self.textEdit])
        }
    }

    /// Only through `KeepAwakeSettings`' setters and `MenuBarLook`'s keys, onto the
    /// store it is given, which is never the host's; `left-behind` adds one raw value
    /// under `KeepAwakeSettings.Key.autoAppRules` that no setter can write.
    func seed(_ store: NamespacedStore) {
        let settings = KeepAwakeSettings(store: store)
        switch self {
        case .idleNoRules, .indefinite: break
        case .idleWaiting:
            settings.setAutoPower(true); settings.setAutoExternalDisplay(true)
        case .timedLong:
            store.set(true, for: MenuBarLook.Key.showTimerText)
        case .timedThenHeld:
            settings.setAutoPower(true)
        case .automaticApps:
            settings.setAppTriggers(rules)
        case .stopTwoStep:
            settings.setAutoPower(true); settings.setTimerEndsAutomation(true)
        case .suppressed:
            settings.setAutoPower(true)
        case .batteryVeto:
            settings.setAutoPower(true); settings.setBatteryGuardEnabled(true)
            settings.setBatteryGuardPercent(50)
        case .lidRefused:
            settings.setClamshellEnabled(true)
        case .leftBehind:
            // Not text: what the rules key holds when nothing can read it.
            settings.setClamshellEnabled(false)
            store.set(1234, for: KeepAwakeSettings.Key.autoAppRules)
        case .worst:
            settings.setAutoPower(true); settings.setAutoExternalDisplay(true)
            settings.setAppTriggers(rules)
            settings.setTimerEndsAutomation(true)
            settings.setBatteryGuardEnabled(true); settings.setBatteryGuardPercent(50)
            settings.setClamshellEnabled(true); settings.setJiggleEnabled(true)
            settings.setJiggleIntervalMinutes(TimerPolicy.longestSessionMinutes)
            settings.setDefaultDurationMinutes(TimerPolicy.longestSessionMinutes)
            store.set(true, for: MenuBarLook.Key.showTimerText)
        }
    }
}

/// An engine with no ports: it says one thing on its wire and does nothing else.
final class KeepAwakeSampleEngine: ModuleEngine {
    private let local = LocalTransport()
    var transport: EngineTransport { local }
    private let payload: KeepAwakeEngine.StatePayload?

    init(payload: KeepAwakeEngine.StatePayload?) {
        self.payload = payload
        local.setHandler { _ in Data() }
    }

    func activate() {
        if let payload { local.emit(KeepAwakeEvent.state, encoding: payload) }
    }
    func deactivate() {}
    var standsIn: Bool { true }
}
