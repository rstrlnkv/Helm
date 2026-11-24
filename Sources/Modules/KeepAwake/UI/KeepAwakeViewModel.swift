import SwiftUI
import HelmRuntime
import HelmUI
import Module_KeepAwake_Engine

/// What the slot under the presets says: the battery guard first, then a
/// sleep assertion macOS refused, then a paused rule.
enum KeepAwakeNotice: Equatable {
    case none, battery, assertionRefused, paused

    /// The battery wins: the facts can all be true, and of them only the guard
    /// explains why nothing at all is happening. A refusal comes before a pause
    /// because it says the Mac is not held while a pause says only that a rule waits.
    static func of(batteryStopped: Bool, assertionRefused: Bool,
                   suppressed: Bool) -> KeepAwakeNotice {
        if batteryStopped { return .battery }
        if assertionRefused { return .assertionRefused }
        return suppressed ? .paused : .none
    }
}

/// The slot under the presets, drawn: one `HelmBanner` per notice, for the hero
/// and the panel alike.
///
/// `notice` has the battery first, and the battery has no button: «Resume»
/// would be a control that cannot do what it says while the guard is in force,
/// and the notice goes by itself when the charger goes in. A refusal has none
/// either. Only a paused rule carries the way back.
///
/// `compact` is the panel: the short sentences (the hero says «— plug in»
/// after the battery one, which is the way out; in a 320 pt card there is no
/// room for a second clause beside a symbol, and the long pause sentence wraps
/// to four lines beside a button), the compact banner, and a small button. The
/// panel's battery banner needs no button: the presets going grey above it say
/// the panel cannot help.
/// The hero's banner does not fill the width; the panel's does.
struct KeepAwakeNoticeBanner: View {
    let notice: KeepAwakeNotice
    let batteryFloor: Int
    let compact: Bool
    let resume: () -> Void

    var body: some View {
        switch notice {
        case .battery:
            HelmBanner(compact ? KAStr.stoppedByBatteryShort(batteryFloor)
                               : KAStr.stoppedByBattery(batteryFloor),
                       symbol: "battery.25", fillsWidth: compact, compact: compact) { EmptyView() }
        case .assertionRefused:
            HelmBanner(KAStr.assertionRefused, symbol: "exclamationmark.triangle.fill",
                       fillsWidth: compact, compact: compact) { EmptyView() }
        case .paused, .none:
            HelmBanner(compact ? KAStr.automationPausedShort : KAStr.automationPaused,
                       symbol: "pause.circle.fill", fillsWidth: compact, compact: compact) {
                if compact {
                    Button(KAStr.resume, action: resume)
                        .controlSize(.small)
                        .fixedSize()
                } else {
                    Button(KAStr.resume, action: resume)
                }
            }
        }
    }
}

/// Keep Awake's own view state, and the module's only door to its engine.
///
/// Built with the engine by the descriptor's `makeModule` and held by the host
/// for as long as the module is on: the descriptor, the panel tile and the
/// settings page all draw from this one object. It takes the engine's states
/// from `stream()`, in one task that `stop()` ends, and calls the engine's own
/// methods for everything the person does — on the main actor, which is where
/// the engine's mutable state is written from.
@MainActor public final class KeepAwakeViewModel: ObservableObject {
    @Published private(set) var isActive = false
    /// The engine's own cases, not the strings they travel as. Held as
    /// `Set<String>`, every view that asked a question about them had to spell
    /// the raw names again — `["externalDisplay", "power", "app"]`, twice —
    /// and `KAStr` switched over five more literals to turn one back into a
    /// word. A name that stops matching is not an error anywhere; the row just
    /// goes quiet.
    @Published private(set) var activeConditions: Set<ActiveCondition> = []
    @Published private(set) var clamshellActive = false
    @Published private(set) var endDate: Date?
    /// Start of the current timed session, for progress rendering.
    @Published private(set) var startDate: Date?
    /// An automatic condition is true and is being ignored, because a session
    /// was ended by hand or by a timer. Cleared by the engine when the
    /// condition drops, or by `resumeAutomation`.
    @Published private(set) var suppressed = false
    /// The rules whose triggers are true right now, obeyed or paused. Unlike
    /// `activeConditions`, a suppressed rule is still in here — which is how
    /// a row can say «Paused» rather than «Not applying right now».
    @Published private(set) var triggeredConditions: Set<ActiveCondition> = []
    /// Bundle ids of the app rules holding the Mac right now, so the hero can
    /// name them instead of saying «App».
    @Published private(set) var holdingApps: [String] = []
    /// The battery guard has everything stopped, and nothing will run until
    /// the charge comes back or the charger goes in.
    @Published private(set) var batteryStopped = false
    /// macOS refused the sleep assertion the session asked for; the engine clears
    /// it with the session.
    @Published private(set) var assertionRefused = false
    /// macOS was asked to turn sleep off for the whole Mac and refused. The one
    /// state in which the lid switch says one thing and the machine does another.
    @Published private(set) var lidRefused = false
    /// The lid option is off and the `/etc/sudoers.d` rule it needed is still
    /// there, because the removal was declined.
    @Published private(set) var lidGrantRemains = false
    /// Any rule at all — the input `StopPress` weighs when it decides whether
    /// Stop silences a rule as well as ending the session.
    var ruleHolds: Bool { !triggeredConditions.isEmpty }
    /// What the lid row's note says, from the three facts the engine publishes
    /// about it. The rule is `LidRowNote`'s, out in the engine's logic.
    var lidRowNote: LidRowNote {
        LidRowNote.of(refused: lidRefused, grantRemains: lidGrantRemains,
                      holding: clamshellActive)
    }

    /// The one thing the slot under the buttons says, from the three facts that
    /// can fill it.
    var notice: KeepAwakeNotice {
        KeepAwakeNotice.of(batteryStopped: batteryStopped,
                           assertionRefused: assertionRefused, suppressed: suppressed)
    }

    private let engine: KeepAwakeEngine
    private var events: StreamFollower?

    init(engine: KeepAwakeEngine) {
        self.engine = engine
        events = StreamFollower(engine.stream(), owner: self) { $0.apply($1) }
    }

    /// Ends the event loop, which unregisters the engine's subscriber. The
    /// host calls it through the descriptor's `stop(_:)` before the engine goes.
    func stop() {
        events?.cancel()
    }

    private func apply(_ p: KeepAwakeEngine.StatePayload) {
        isActive = p.isActive
        activeConditions = p.conditions
        clamshellActive = p.clamshellActive
        endDate = p.endDate
        startDate = p.startDate
        suppressed = p.suppressed
        triggeredConditions = p.triggeredConditions
        holdingApps = p.holdingApps
        batteryStopped = p.batteryStopped
        assertionRefused = p.assertionRefused
        lidRefused = p.lidRefused
        lidGrantRemains = p.lidGrantRemains
    }

    /// The global shortcut, the panel's switch and the menu-bar item.
    func toggle() { engine.toggleSession() }

    /// Start a session of `minutes` — 0 meaning «no deadline». The engine has
    /// the last word on the number.
    func start(minutes: Int) { engine.startSession(minutes: minutes) }

    /// The Stop button; which of its two meanings this press has is the engine's.
    func stopSession() { engine.stopSession() }

    /// Lift a suppression the person can see on screen. Not `start`: that would
    /// be a manual session, which outlives the rule that is actually true.
    func resumeAutomation() { engine.resumeAutomation() }

    /// Change a setting and tell the engine it changed.
    ///
    /// The pair is the point: the settings are read at every access, but the
    /// engine re-applies a running session's assertion, lid and jiggle only when
    /// `settingsChanged` is called. The settings page and the panel tile each
    /// carried their own copy of these two lines.
    func save(in store: NamespacedStore, _ change: (KeepAwakeSettings) -> Void) {
        change(KeepAwakeSettings(store: store))
        engine.settingsChanged()
    }

    /// The person's gesture on the lid switch; the engine writes the option and
    /// applies it (`KeepAwakeEngine.lidSwitchTurned`).
    func lidSwitchTurned(_ on: Bool) { engine.lidSwitchTurned(on) }

    /// Tell the engine that a view wrote settings itself.
    func settingsChanged() { engine.settingsChanged() }
}
