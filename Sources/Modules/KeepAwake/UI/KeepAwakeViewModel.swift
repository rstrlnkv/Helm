import SwiftUI
import HelmRuntime
import Module_KeepAwake_Engine

/// Keep Awake's own view state, and the module's only door to its engine.
///
/// Built with the engine by the descriptor's `makeModule` and held by the host
/// for as long as the module is on: the descriptor, the panel tile and the
/// settings page all draw from this one object. It takes the engine's states
/// from `stream()`, in one task that `stop()` ends, and calls the engine's own
/// methods for everything the person does — on the main actor, which is where
/// the engine's mutable state is written from.
@MainActor public final class KeepAwakeViewModel: ObservableObject {
    @Published public private(set) var isActive = false
    /// The engine's own cases, not the strings they travel as. Held as
    /// `Set<String>`, every view that asked a question about them had to spell
    /// the raw names again — `["externalDisplay", "power", "app"]`, twice —
    /// and `KAStr` switched over five more literals to turn one back into a
    /// word. A name that stops matching is not an error anywhere; the row just
    /// goes quiet.
    @Published public private(set) var activeConditions: Set<ActiveCondition> = []
    @Published public private(set) var clamshellActive = false
    @Published public private(set) var endDate: Date?
    /// Start of the current timed session, for progress rendering.
    @Published public private(set) var startDate: Date?
    /// An automatic condition is true and is being ignored, because a session
    /// was ended by hand or by a timer. Cleared by the engine when the
    /// condition drops, or by `resumeAutomation`.
    @Published public private(set) var suppressed = false
    /// The rules whose triggers are true right now, obeyed or paused. Unlike
    /// `activeConditions`, a suppressed rule is still in here — which is how
    /// a row can say «Paused» rather than «Not applying right now».
    @Published public private(set) var triggeredConditions: Set<ActiveCondition> = []
    /// Bundle ids of the app rules holding the Mac right now, so the hero can
    /// name them instead of saying «App».
    @Published public private(set) var holdingApps: [String] = []
    /// The battery guard has everything stopped, and nothing will run until
    /// the charge comes back or the charger goes in.
    @Published public private(set) var batteryStopped = false
    /// macOS was asked to turn sleep off for the whole Mac and refused. The one
    /// state in which the lid switch says one thing and the machine does another.
    @Published public private(set) var lidRefused = false
    /// The lid option is off and the `/etc/sudoers.d` rule it needed is still
    /// there, because the removal was declined.
    @Published public private(set) var lidGrantRemains = false
    /// Any rule at all — the condition under which Stop silences a rule as
    /// well as ending the session.
    public var ruleHolds: Bool { !triggeredConditions.isEmpty }
    /// What the lid row's note says, from the three facts the engine publishes
    /// about it. The rule is `LidRowNote`'s, out in the engine's logic.
    public var lidRowNote: LidRowNote {
        LidRowNote.of(refused: lidRefused, grantRemains: lidGrantRemains,
                      holding: clamshellActive)
    }

    private let engine: KeepAwakeEngine
    private var eventsTask: Task<Void, Never>?

    /// The stream is taken here, synchronously, before the first suspension:
    /// `stream()` registers the subscriber and replays the latest state in one
    /// step, so the latest state emitted before this line, and every one after it,
    /// reaches `apply` once and in order.
    init(engine: KeepAwakeEngine) {
        self.engine = engine
        let states = engine.stream()
        eventsTask = Task { [weak self] in
            for await state in states {
                guard let self else { break }
                self.apply(state)
            }
        }
    }

    /// Ends the event loop, which unregisters the engine's subscriber. The
    /// host calls it through the descriptor's `stop(_:)` before the engine goes.
    func stop() {
        eventsTask?.cancel()
        eventsTask = nil
    }

    /// The backstop for a model dropped without `stop()`: the loop re-acquires
    /// `self` per state, so it does not keep the model alive.
    deinit { eventsTask?.cancel() }

    private func apply(_ p: KeepAwakeEngine.StatePayload) {
        isActive = p.isActive
        // A name this build does not know is dropped rather than carried as a
        // string nothing can match.
        activeConditions = Set(p.conditions.compactMap(ActiveCondition.init(rawValue:)))
        clamshellActive = p.clamshellActive
        endDate = p.endDate
        startDate = p.startDate
        suppressed = p.suppressed
        triggeredConditions = Set(p.triggeredConditions.compactMap(ActiveCondition.init(rawValue:)))
        holdingApps = p.holdingApps
        batteryStopped = p.batteryStopped
        lidRefused = p.lidRefused
        lidGrantRemains = p.lidGrantRemains
    }

    /// The global shortcut, the panel's switch and the menu-bar item.
    func toggle() { engine.toggleSession() }

    /// Start a session of `minutes` — 0 meaning «no deadline». The engine has
    /// the last word on the number.
    public func start(minutes: Int) { engine.startSession(minutes: minutes) }

    /// The Stop button; which of its two meanings this press has is the engine's.
    func stopSession() { engine.stopSession() }

    /// Lift a suppression the person can see on screen. Not `start`: that would
    /// be a manual session, which outlives the rule that is actually true.
    func resumeAutomation() { engine.resumeAutomation() }

    /// Change a setting and tell the engine to re-read it.
    ///
    /// The pair is the point: the engine keeps what it read, so a write nobody
    /// announces is a setting that starts working at the next launch. The
    /// settings page and the panel tile each carried their own copy of these two
    /// lines.
    func save(in store: NamespacedStore, _ change: (KeepAwakeSettings) -> Void) {
        change(KeepAwakeSettings(store: store))
        engine.settingsChanged()
    }

    /// Tell the engine to re-read settings a view wrote itself.
    func settingsChanged() { engine.settingsChanged() }
}
