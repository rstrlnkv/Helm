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
        // The one loss in this module that nothing else reports: a rules string
        // the file got wrong reads as no rules, so the apps somebody chose stop
        // holding the Mac awake and every screen goes on looking well.
        if settings.appRulesUnreadable {
            HelmLog.shared.warn("keepawake", "the stored app rules could not be read; "
                                + "no app is holding sleep")
        }
        displayObserver.startObserving { [weak self] in self?.recompute() }
        power.startObserving { [weak self] in
            self?.batteryCheck()
            self?.recompute()
        }
        apps.startObserving { [weak self] in self?.recompute() }
        // Before the recompute, so the session the person started is one of the
        // conditions it resolves rather than something added afterwards.
        restoreSession()
        recompute()
    }

    public func deactivate() {
        // Before anything else: the module can be switched off from Settings,
        // and what that drops is this engine and everything it owns. An
        // observer left armed is a pointer into freed memory the next time the
        // charger moves.
        //
        // **Only this one, and the other two are not an oversight.** The power
        // port hands IOKit an *unretained* pointer to itself as the callback
        // context (`IOPSNotificationCreateRunLoopSource`), so a callback already
        // scheduled would resolve a context that is going away — which is why
        // its `stopObserving` invalidates the source as well as removing it.
        // `ScreenParamsObserver` and `WorkspaceAppPort` register blocks that
        // capture the caller's closure and never `self`; each clears its own
        // token at the top of `startObserving` and again in `deinit`, so
        // dropping the engine takes them with it. Read as a general rule, this
        // line says the other two were forgotten. They were not.
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

    /// The engine has the last word on how long a session may be.
    ///
    /// Every number a person can pick is bounded where they pick it — the
    /// settings stepper, the tile's presets, `TimerPolicy.extendedMinutes` for
    /// the "+15" — and one caller is not a person: `wireTransport` decodes
    /// `KeepAwakeStart` from a JSON payload and hands `payload.minutes`
    /// straight here, where `minutes * 60` **traps** on `Int` overflow. A
    /// clamp in every view is a clamp in no engine.
    ///
    /// A negative is refused rather than brought up to the floor: zero is this
    /// module's spelling of "until I say stop", so clamping would turn a
    /// session of minus a minute into one with no deadline at all — the Mac
    /// held awake on the strength of a number nobody wrote, which is the
    /// direction this module does not fail in.
    public func startSession(minutes: Int) {
        guard minutes >= 0 else { return }
        let minutes = minutes.clamped(to: 0...TimerPolicy.longestSessionMinutes)
        manualOn = true
        suppressed = false
        expiryToken = nil
        if minutes > 0 {
            let now = clock.now()
            startDate = now
            endDate = now.addingTimeInterval(TimeInterval(minutes * 60))
            scheduleExpiry(after: TimeInterval(minutes * 60))
        } else {
            startDate = nil
            endDate = nil
        }
        rememberSession()
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
        // Stopping is a decision too, and it has to outlive the process as firmly
        // as starting does — otherwise the next launch resurrects what was
        // switched off.
        rememberSession()
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

        // Logged on the transition and never on the recompute. `recompute()` runs
        // from three observers — a display moving, the charger, an app launching —
        // so a line here per call would be a stream, and the one trail that has to
        // stay readable would be mostly this module. Whether sleep is held is the
        // module's entire output and it changes rarely, which is exactly what a log
        // is for.
        if r.isActive && !isActive {
            isActive = true
            assertions.preventSleep(display: settings.keepDisplayOn)
            HelmLog.shared.info("keepawake", "holding sleep: \(ConditionLabel.of(r.conditions))"
                                + (settings.keepDisplayOn ? ", display too" : ""))
            if settings.clamshellEnabled { engageClamshell() }
            if settings.jiggleEnabled { scheduleJiggle() }
            scheduleBatteryWatch()
        } else if !r.isActive && isActive {
            assertions.release()
            HelmLog.shared.info("keepawake", "released")
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

    /// In seconds, not minutes: a session restored after a relaunch is scheduled
    /// for what is *left* of it rather than for the duration it was asked for.
    private func scheduleExpiry(after seconds: TimeInterval) {
        expiryToken = clock.schedule(after: seconds) { [weak self] in
            self?.handleExpiry()
        }
    }

    private func handleExpiry() {
        switch TimerPolicy.onExpiry(hasAutoCondition: currentAutoConditionHolds(), suppressed: suppressed) {
        case .continueAsAuto:
            // The timer ran out and the Mac stays awake anyway, because a display
            // or the charger is holding it. Without this line the countdown simply
            // disappears and nothing accounts for the assertion still being held.
            HelmLog.shared.info("keepawake", "timer ended; an automatic condition still holds")
            manualOn = false
            endDate = nil
            startDate = nil
            rememberSession()
            recompute()
        case .deactivate:
            stopSession()
        }
    }

    // MARK: - A session across the end of the process

    /// Not private, so the tests that plant a session name the same keys the
    /// engine reads rather than spelling them a second time.
    enum SessionKey {
        static let on = "sessionOn"
        static let startedAt = "sessionStartedAt"
        static let endsAt = "sessionEndsAt"
    }

    /// Written wherever the person's intent changes, and **not** in
    /// `deactivate()`.
    ///
    /// `deactivate()` looks like the place for it and is the one place it must not
    /// go: `applicationWillTerminate` calls it on every live engine
    /// (`HelmApp/AppDelegate.swift:237`), so recording "off" there would erase the
    /// session on every quit — including the silent updater's, which is the
    /// relaunch this whole thing exists for. It would have been a fix that
    /// changed nothing.
    ///
    /// The cost of that choice, stated: `deactivate()` also runs when the module
    /// is switched off in Settings, and it cannot tell the two callers apart. So
    /// switching Keep Awake off and on again resumes a session that has not
    /// expired. Of the two possible mistakes, forgetting what the person asked for
    /// is the one that was reported.
    /// Stored against 2001 and not 1970, which is not a style choice: a `Date`
    /// *is* a `Double` of seconds since the reference date, so that round-trips
    /// exactly, while going through `timeIntervalSince1970` adds and then
    /// subtracts 978 307 200 and loses the low-order bits. The restored deadline
    /// then differs from the stored one by a fraction of a second — enough for a
    /// re-scheduled expiry to miss the interval it was scheduled for, and enough
    /// to make a test of it pass or fail on the fractional part of `Date()`.
    private func rememberSession() {
        store.set(manualOn, for: SessionKey.on)
        store.set(startDate?.timeIntervalSinceReferenceDate ?? 0, for: SessionKey.startedAt)
        store.set(endDate?.timeIntervalSinceReferenceDate ?? 0, for: SessionKey.endsAt)
    }

    private func restoreSession() {
        let stamp = { (seconds: Double) -> Date? in
            seconds > 0 ? Date(timeIntervalSinceReferenceDate: seconds) : nil
        }
        let storedStart = stamp(store.double(SessionKey.startedAt, default: 0))
        let storedEnd = stamp(store.double(SessionKey.endsAt, default: 0))

        switch SessionRestore.decide(manualOn: store.bool(SessionKey.on, default: false),
                                     startDate: storedStart, endDate: storedEnd,
                                     now: clock.now()) {
        case .none:
            let hadOne = store.bool(SessionKey.on, default: false)
            manualOn = false
            startDate = nil
            endDate = nil
            // The record goes with it, so a later launch cannot find the same
            // spent deadline and weigh it again.
            rememberSession()
            // Worth a line precisely because nothing visible happens: this is the
            // answer to "why did my Mac sleep" when the app was gone longer than
            // the session had left.
            if hadOne {
                HelmLog.shared.info("keepawake", "a stored session had already ended")
            }
        case .indefinite:
            manualOn = true
            startDate = nil
            endDate = nil
            HelmLog.shared.info("keepawake", "restored a session with no deadline")
        case .remaining(let left):
            manualOn = true
            startDate = storedStart
            // The deadline the module decided on, not the one it read. The two
            // differ wherever the decision bounded the stored pair — a clock
            // that moved, or a pair that is credible as a duration and absurd
            // as dates — and the countdown every surface draws is this date
            // minus now, converted to an `Int`.
            endDate = clock.now().addingTimeInterval(left)
            scheduleExpiry(after: left)
            HelmLog.shared.info("keepawake", "restored a session: \(Int(left / 60)) min left")
        }
    }

    // MARK: - Battery guard

    private func batteryCheck() {
        guard let snap = power.snapshot() else { return }
        if BatteryGuard.shouldDeactivate(enabled: settings.batteryGuardEnabled,
                                          isOnBattery: snap.onBattery,
                                          percent: snap.percent,
                                          threshold: settings.batteryGuardPercent) {
            // The session ends without the person touching anything, so the log is
            // the only place that can say who ended it and why.
            HelmLog.shared.info("keepawake", "battery guard stopped the session at "
                                + "\(snap.percent)% (floor \(settings.batteryGuardPercent)%)")
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
        // Announced because the system cannot tell this from a hand on the
        // trackpad. Measured: a synthetic `mouseMoved` took the idle counter
        // from 284,97 s to 0,30 s. The default interval here is five minutes —
        // exactly `ScanSchedule.idleThreshold` — so anything deciding "has the
        // person left" from that counter alone would find the Mac permanently
        // busy, and **no background scan would ever run** for anybody with this
        // switch on. `ScanCoordinator` subtracts what it hears here.
        NotificationCenter.default.post(name: .helmPointerNudged, object: nil)
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
        // A change to the system's own sleep setting, made through sudo and
        // outliving the process — the one thing this module does that a crash can
        // leave behind. Both ends of it belong in the trail.
        HelmLog.shared.info("keepawake", "closed-lid sleep disabled")
    }

    private func disengageClamshell() {
        _ = clamshell.setDisableSleep(false)
        store.set(false, for: "clamshellGuard")
        clamshellActive = false
        HelmLog.shared.info("keepawake", "closed-lid sleep restored")
    }

    private func cancelTimers() {
        jiggleToken = nil
        batteryToken = nil
    }

    // MARK: - Transport

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
            // Inside `MainActor.run`, which returns nothing: an unknown name
            // leaves without doing anything, and the empty reply below is the
            // same answer the caller would have got from a `default`.
            guard let name = KeepAwakeCommand(rawValue: cmd.name) else { return }
            switch name {
            case .toggle:
                self.toggleSession()
            case .start:
                if let payload = EngineReply.decode(KeepAwakeStart.self, from: cmd) {
                    self.startSession(minutes: payload.minutes)
                }
            case .stop:
                self.stopSession()
            case .settingsChanged:
                self.recompute()
                self.reconcileActiveSettings()
                self.releaseSudoersIfUnneeded()
            }
            }
            return Data()
        }
    }

    private func emitState() {
        let payload = StatePayload(isActive: isActive,
                                    conditions: activeConditions.map(\.rawValue).sorted(),
                                    clamshellActive: clamshellActive,
                                    endDate: endDate,
                                    startDate: startDate)
        localTransport.emit(KeepAwakeEvent.state, encoding: payload)
    }
}
