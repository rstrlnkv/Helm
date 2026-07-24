import Foundation
import HelmContract
import HelmRuntime

/// Orchestrates the pure KeepAwake logic units (Conditions/ExternalDisplaySupport/
/// PowerSupport/BatteryGuard/TimerPolicy/JiggleTarget/ClamshellRecovery) against the
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
        !settings.autoApps.isEmpty && !Set(settings.autoApps).isDisjoint(with: apps.runningBundleIDs())
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
            clamshell.installSudoers { [weak self] ok in
                if ok { self?.reallyEngageClamshell() }
            }
        } else {
            reallyEngageClamshell()
        }
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
    private struct StatePayload: Codable {
        let isActive: Bool
        let conditions: [String]
        let clamshellActive: Bool
        let endDate: Date?
        let startDate: Date?
    }

    private func wireTransport() {
        localTransport.setHandler { [weak self] cmd in
            guard let self else { return Data() }
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
            default:
                break
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
