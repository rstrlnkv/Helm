import Foundation
import HelmContract
import HelmRuntime

/// Orchestrates the pure KeepAwake logic units (Conditions/ExternalDisplaySupport/
/// BatteryGuard/TimerPolicy/JiggleTarget/ClamshellRecovery) against the
/// side-effecting ports. `activate()`/`deactivate()` are the MODULE lifecycle
/// (host enables/disables the module); the keep-awake session itself is controlled
/// independently via `startSession`/`stopSession`/`toggleSession`.
public final class KeepAwakeEngine: ModuleEngine, @unchecked Sendable {
    private let settings: KeepAwakeSettings
    private let store: NamespacedStore
    private let assertions: SleepAssertions
    private let displayInfo: DisplayInfoPort
    private let displayObserver: DisplayObserverPort
    private let power: PowerInfoPort
    private let apps: AppRunningPort
    private let pointer: PointerPort
    private let clamshell: ClamshellPort
    private let clock: Clock
    private let localTransport: LocalTransport
    public let transport: EngineTransport

    public private(set) var isActive = false
    public private(set) var activeConditions: Set<ActiveCondition> = []
    public private(set) var clamshellActive = false
    public private(set) var endDate: Date?
    /// When the current timed session began (nil when there is no timer).
    public private(set) var startDate: Date?

    private var manualOn = false
    private var suppressed = false
    /// An admin password prompt is on screen and has not been answered.
    ///
    /// Nothing else can stand for this. `isSudoersInstalled()` asks the
    /// filesystem, and the file appears only when the person types their
    /// password — so for the whole life of the prompt, which is seconds to
    /// minutes, the answer is the same "no" that started it.
    private var sudoersInstallInFlight = false

    private var expiryToken: AnyObject?
    private var jiggleToken: AnyObject?
    private var batteryToken: AnyObject?

    public init(settings: KeepAwakeSettings,
                store: NamespacedStore,
                assertions: SleepAssertions,
                displayInfo: DisplayInfoPort,
                displayObserver: DisplayObserverPort,
                power: PowerInfoPort,
                apps: AppRunningPort,
                pointer: PointerPort,
                clamshell: ClamshellPort,
                clock: Clock,
                transport: LocalTransport = LocalTransport()) {
        self.settings = settings
        self.store = store
        self.assertions = assertions
        self.displayInfo = displayInfo
        self.displayObserver = displayObserver
        self.power = power
        self.apps = apps
        self.pointer = pointer
        self.clamshell = clamshell
        self.clock = clock
        self.localTransport = transport
        self.transport = transport
        wireTransport()
    }

    // MARK: - ModuleEngine (module enabled/disabled)

    public func activate() {
        // Only shell out to pmset when we actually recorded disabling sleep;
        // Swift evaluates both call arguments, so short-circuit with the flag.
        if store.bool("clamshellGuard", default: false),
           ClamshellRecovery.sleepDisabled(inPmsetOutput: clamshell.pmsetReport()) {
            _ = clamshell.setDisableSleep(false)
            store.set(false, for: "clamshellGuard")
        }
        displayObserver.startObserving { [weak self] in self?.recompute() }
        power.startObserving { [weak self] in
            self?.batteryCheck()
            self?.recompute()
        }
        apps.startObserving { [weak self] in self?.recompute() }
        recompute()
    }

    public func deactivate() {
        // Before anything else: the module can be switched off from Settings,
        // and what that drops is this engine and everything it owns. An
        // observer left armed is a pointer into freed memory the next time the
        // charger moves.
        power.stopObserving()
        if isActive { assertions.release() }
        if clamshellActive { disengageClamshell() }
        cancelTimers()
        expiryToken = nil
        isActive = false
        manualOn = false
        suppressed = false
        endDate = nil
        startDate = nil
        activeConditions = []
        emitState()
    }

    // MARK: - Session control (keep-awake on/off)

    public func toggleSession() {
        if isActive {
            stopSession()
        } else {
            startSession(minutes: settings.defaultDurationMinutes)
        }
    }

    public func startSession(minutes: Int) {
        manualOn = true
        suppressed = false
        expiryToken = nil
        if minutes > 0 {
            startDate = clock.now()
            endDate = clock.now().addingTimeInterval(TimeInterval(minutes * 60))
            scheduleExpiry(minutes: minutes)
        } else {
            startDate = nil
            endDate = nil
        }
        recompute()
    }

    public func stopSession() {
        if currentAutoConditionHolds() {
            suppressed = true
        }
        manualOn = false
        endDate = nil
        startDate = nil
        expiryToken = nil
        recompute()
    }

    // MARK: - Core recompute

    private func recompute() {
        let ext = externalDisplayCondition()
        let pwr = powerCondition()
        let appR = appCondition()

        if suppressed && !(ext || pwr || appR) {
            suppressed = false
        }

        var inputs = Conditions.Inputs()
        inputs.manual = manualOn
        inputs.timerRunning = (endDate != nil && endDate! > clock.now())
        inputs.externalDisplay = ext
        inputs.onPower = pwr
        inputs.appRunning = appR
        inputs.suppressed = suppressed

        let r = Conditions.resolve(inputs)

        if r.isActive && !isActive {
            isActive = true
            assertions.preventSleep(display: settings.keepDisplayOn)
            if settings.clamshellEnabled { engageClamshell() }
            if settings.jiggleEnabled { scheduleJiggle() }
            scheduleBatteryWatch()
        } else if !r.isActive && isActive {
            assertions.release()
            if clamshellActive { disengageClamshell() }
            cancelTimers()
            isActive = false
        }
        activeConditions = r.conditions
        emitState()
    }

    /// Re-apply live-tunable side effects to current settings while a session is
    /// active, so toggling keepDisplayOn / clamshell / jiggle takes effect now
    /// (not only on the next session).
    private func reconcileActiveSettings() {
        guard isActive else { return }
        assertions.release()
        assertions.preventSleep(display: settings.keepDisplayOn)
        if settings.clamshellEnabled, !clamshellActive {
            engageClamshell()
        } else if !settings.clamshellEnabled, clamshellActive {
            disengageClamshell()
        }
        if settings.jiggleEnabled, jiggleToken == nil {
            scheduleJiggle()
        } else if !settings.jiggleEnabled {
            jiggleToken = nil
        }
        emitState()
    }

    private func externalDisplayCondition() -> Bool {
        settings.autoExternalDisplay && ExternalDisplaySupport.hasExternal(builtInFlags: displayInfo.builtInFlags())
    }
    private func powerCondition() -> Bool {
        settings.autoPower && (power.snapshot().map { !$0.onBattery } ?? false)
    }
    private func appCondition() -> Bool {
        let rules = settings.appTriggers
        guard !rules.isEmpty else { return false }
        // A rule may be narrowed to "only at the desk" or "only plugged in",
        // so the same inputs the other conditions use are passed in.
        return AppTriggerRules.isHolding(
            rules,
            running: Set(apps.runningBundleIDs()),
            externalDisplay: ExternalDisplaySupport.hasExternal(builtInFlags: displayInfo.builtInFlags()),
            onPower: power.snapshot().map { !$0.onBattery } ?? false)
    }
    private func currentAutoConditionHolds() -> Bool {
        externalDisplayCondition() || powerCondition() || appCondition()
    }

    // MARK: - Timer expiry

    private func scheduleExpiry(minutes: Int) {
        expiryToken = clock.schedule(after: TimeInterval(minutes * 60)) { [weak self] in
            self?.handleExpiry()
        }
    }

    private func handleExpiry() {
        switch TimerPolicy.onExpiry(hasAutoCondition: currentAutoConditionHolds(), suppressed: suppressed) {
        case .continueAsAuto:
            manualOn = false
            endDate = nil
            startDate = nil
            recompute()
        case .deactivate:
            stopSession()
        }
    }

    // MARK: - Battery guard

    private func batteryCheck() {
        guard let snap = power.snapshot() else { return }
        if BatteryGuard.shouldDeactivate(enabled: settings.batteryGuardEnabled,
                                          isOnBattery: snap.onBattery,
                                          percent: snap.percent,
                                          threshold: settings.batteryGuardPercent) {
            stopSession()
        }
    }

    private func scheduleBatteryWatch() {
        batteryToken = clock.schedule(after: 30) { [weak self] in
            guard let self else { return }
            self.batteryCheck()
            if self.isActive { self.scheduleBatteryWatch() }
        }
    }

    // MARK: - Jiggle

    private func scheduleJiggle() {
        let interval = TimeInterval(settings.jiggleIntervalMinutes * 60)
        jiggleToken = clock.schedule(after: interval) { [weak self] in
            guard let self else { return }
            self.doJiggle()
            if self.isActive && self.settings.jiggleEnabled { self.scheduleJiggle() }
        }
    }

    private func doJiggle() {
        guard let p = pointer.location(),
              let b = pointer.displayBounds(containing: p),
              let t = JiggleTarget.nudge(from: p, in: b) else { return }
        pointer.move(to: t)
    }

    // MARK: - Clamshell

    private func engageClamshell() {
        if !clamshell.isSudoersInstalled() {
            // Every false→true edge of `isActive` and every settings change
            // reaches here, and while a prompt is up the disk still says the
            // rule is missing — so without this the person got one password
            // dialog per click for a single decision, each of them an
            // `osascript` writing the same staging file in /etc/sudoers.d.
            // A *declined* prompt is a different state: the flag clears when
            // the prompt is answered, so the next session asks again.
            guard !sudoersInstallInFlight else { return }
            sudoersInstallInFlight = true
            clamshell.installSudoers { [weak self] ok in
                // The osascript callback arrives on a background queue; engine
                // state and store writes belong on main.
                DispatchQueue.main.async {
                    self?.sudoersInstallFinished(granted: ok)
                }
            }
        } else {
            reallyEngageClamshell()
        }
    }

    /// The prompt has been answered, and only now is there a file to reason
    /// about. Both questions asked while it was up were asked of a rule that
    /// did not exist yet, so both are asked again here.
    private func sudoersInstallFinished(granted: Bool) {
        sudoersInstallInFlight = false
        guard granted else { return }
        reallyEngageClamshell()
        releaseSudoersIfUnneeded()
    }

    /// Switching the option off takes the passwordless-sudo rule back out.
    ///
    /// The rule is the price of the feature, not of having installed Helm: a
    /// permanent NOPASSWD line in /etc/sudoers.d for something the user has
    /// turned off is a grant nobody is holding. Silent on failure — the user
    /// declined the password prompt, which is an answer, and the rule stays
    /// until they say otherwise.
    private func releaseSudoersIfUnneeded() {
        guard !settings.clamshellEnabled, clamshell.isSudoersInstalled() else { return }
        clamshell.removeSudoers { _ in }
    }

    private func reallyEngageClamshell() {
        // The sudoers prompt is async; the session may have already ended (or
        // clamshell may have been disabled) by the time the user answers it.
        // Never disable sleep for a session that is no longer active.
        guard isActive, settings.clamshellEnabled else { return }
        store.set(true, for: "clamshellGuard")
        _ = clamshell.setDisableSleep(true)
        clamshellActive = true
    }

    private func disengageClamshell() {
        _ = clamshell.setDisableSleep(false)
        store.set(false, for: "clamshellGuard")
        clamshellActive = false
    }

    private func cancelTimers() {
        jiggleToken = nil
        batteryToken = nil
    }

    // MARK: - Transport

    private struct StartPayload: Codable { let minutes: Int }
    /// Public because the page decodes it. It was typed out again over there,
    /// matched to this one by field names across a JSON hop with no compiler
    /// in between — and a field that stops matching does not fail, it silently
    /// decodes to nothing and the screen keeps its defaults forever. That is
    /// the bug `ModuleViewModel`'s own doc comment records, shipped once and
    /// then re-created inside the modules.
    public struct StatePayload: Codable {
        public let isActive: Bool
        public let conditions: [String]
        public let clamshellActive: Bool
        public let endDate: Date?
        public let startDate: Date?
    }

    private func wireTransport() {
        localTransport.setHandler { [weak self] cmd in
            guard let self else { return Data() }
            // On main, like every other writer here. The display, power and
            // application observers all deliver on the main thread; commands
            // arrived on a concurrency pool, so `isActive`, `activeConditions`
            // and the timer dates were written from two threads with no lock —
            // and the class carried `@unchecked Sendable` without saying why.
            await MainActor.run {
            switch cmd.name {
            case "toggle":
                self.toggleSession()
            case "start":
                if let payload = try? JSONDecoder().decode(StartPayload.self, from: cmd.payload) {
                    self.startSession(minutes: payload.minutes)
                }
            case "stop":
                self.stopSession()
            case "settingsChanged":
                self.recompute()
                self.reconcileActiveSettings()
                self.releaseSudoersIfUnneeded()
            default:
                break
            }
            }
            return Data()
        }
    }

    private func emitState() {
        let payload = StatePayload(isActive: isActive,
                                    conditions: activeConditions.map(\.wireName).sorted(),
                                    clamshellActive: clamshellActive,
                                    endDate: endDate,
                                    startDate: startDate)
        if let data = try? JSONEncoder().encode(payload) {
            localTransport.emit(EngineEvent(name: "state", payload: data))
        }
    }
}

private extension ActiveCondition {
    var wireName: String {
        switch self {
        case .manual: return "manual"
        case .timer: return "timer"
        case .externalDisplay: return "externalDisplay"
        case .power: return "power"
        case .app: return "app"
        }
    }
}
