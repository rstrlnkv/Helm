import Foundation
import HelmContract
import HelmRuntime

/// Orchestrates the pure KeepAwake logic units (Conditions/ExternalDisplaySupport/
/// BatteryGuard/TimerPolicy/JiggleTarget/ClamshellRecovery) against the
/// side-effecting ports. `activate()`/`deactivate()` are the MODULE lifecycle
/// (host enables/disables the module); the keep-awake session itself is controlled
/// independently via `startSession`/`stopSession`/`toggleSession`.
public final class KeepAwakeEngine: ModuleEngine, @unchecked Sendable {
    /// The module's own name for itself, and the namespace its settings are
    /// stored under.
    ///
    /// On the engine, with the descriptor forwarding it upward — the same
    /// direction the command enum travels, and the convention `DiskEngine`,
    /// `DuplicatesEngine`, `LeftoversEngine` and `UninstallerEngine` already
    /// follow. It was a literal in the descriptor while the engine side had no
    /// name at all, so nothing in `Engine/` could say which store it was
    /// reading. `StoreNamespacesAreModuleIdsTests` records the nine that
    /// shipped and fails on a rename: this is stored-settings data, and a
    /// rename orphans everything anybody has configured.
    public static let moduleID = "keep-awake"

    private let settings: KeepAwakeSettings
    private let store: NamespacedStore
    private let assertions: SleepAssertions
    private let displayInfo: DisplayInfoPort
    private let displayObserver: DisplayObserverPort
    private let power: PowerInfoPort
    private let apps: AppRunningPort
    private let pointer: PointerPort
    /// «Stay awake with the lid closed», and the NOPASSWD rule it needs. Six
    /// methods and four flags that nothing else here reads — see
    /// `ClamshellCoordinator`.
    private let lid: ClamshellCoordinator
    private let clock: Clock
    private let localTransport: LocalTransport
    public let transport: EngineTransport

    public private(set) var isActive = false
    public private(set) var activeConditions: Set<ActiveCondition> = []
    /// Forwarded, because the wire and the panel have always called it this.
    public var clamshellActive: Bool { lid.active }
    public private(set) var endDate: Date?
    /// When the current timed session began (nil when there is no timer).
    public private(set) var startDate: Date?

    private var manualOn = false
    /// An automatic condition is true and is being ignored, because a session
    /// was ended — by hand, or by a timer the person asked to end automation.
    ///
    /// Read outside this file as well as inside it, and that is the point: the
    /// flag existed from the first version and was published nowhere, so a Mac
    /// that slept with the rule's app still on screen had no account of itself
    /// anywhere. One name for it, here and on the wire.
    public private(set) var suppressed = false
    /// The rules whose triggers are true right now — **whether or not they are
    /// being obeyed**, which is what makes this different from
    /// `activeConditions`.
    ///
    /// A suppressed rule contributes nothing to `activeConditions`, so from the
    /// outside a paused rule and a rule whose app has quit looked identical:
    /// the page drew «Not applying right now» under a banner saying the rule
    /// was paused. Two accounts of one rule on one screen.
    ///
    /// Non-empty is also precisely the condition under which `stopSession()`
    /// silences a rule as well as ending the session — a fact the hero could
    /// only state in its `.automatic` branch, because that was the only branch
    /// that could see any conditions at all.
    public private(set) var triggeredConditions: Set<ActiveCondition> = []
    /// The bundle ids of the app rules that are satisfied right now — so the
    /// screen can say *which* app, rather than «App». Ids rather than names:
    /// the lookup belongs to whoever draws, and names stay off the wire.
    public private(set) var holdingApps: [String] = []
    /// The battery guard is holding everything down, and nothing this module
    /// does will run until the charge comes back or the charger goes in.
    ///
    /// Published because the alternative is what shipped: the session ends
    /// with nobody touching anything, and the code's own comment said «the log
    /// is the only place that can say who ended it and why». That is the same
    /// silence the paused-rule banner exists to break, on a state a person is
    /// even less likely to guess at — they pressed «15 min» and nothing
    /// happened.
    public private(set) var batteryStopped = false

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
        self.clock = clock
        self.localTransport = transport
        self.transport = transport
        self.lid = ClamshellCoordinator(clamshell: clamshell, store: store, settings: settings)
        // After every stored property is set, which is the first moment `self`
        // may be captured. Both are asked at the moment of use rather than read
        // now: a password prompt can be on screen for minutes, and whether a
        // session is still running is a different answer by the time it is
        // answered.
        self.lid.sessionIsActive = { [weak self] in self?.isActive ?? false }
        self.lid.stateChanged = { [weak self] in self?.emitState() }
        wireTransport()
    }

    // MARK: - ModuleEngine (module enabled/disabled)

    public func activate() {
        lid.recoverAtLaunch()
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
        // **Power is the one that would be a crash**, and the reason is worth
        // keeping: it hands IOKit an *unretained* pointer to itself as the
        // callback context (`IOPSNotificationCreateRunLoopSource`), so a
        // callback already scheduled would resolve a context that is going
        // away — which is why its `stopObserving` invalidates the source as
        // well as removing it.
        //
        // The display observer is stopped here too. It is not a crash if it is
        // not — `ScreenParamsObserver` registers a block that captures the
        // caller's closure and never `self`, and clears its own token in
        // `deinit` — but *when* that happens is then a fact about when the last
        // reference goes, and this is the moment it is meant to happen. The
        // method was on the port and called by nobody for exactly as long as
        // that reasoning stood in for calling it.
        //
        // `WorkspaceAppPort` has no `stopObserving` to call and clears its
        // token the same way. That is the remaining asymmetry, and it is named
        // here rather than left to be rediscovered.
        power.stopObserving()
        displayObserver.stopObserving()
        if isActive { assertions.release() }
        // Sleep back, and the grant with it: switching the module off is a
        // decision, and the sudo rule is the one thing here that would outlive
        // it — outlive quitting Helm, and outlive deleting it.
        lid.tearDown()
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

    /// The one verb the keyboard has, and it has to be able to undo itself.
    ///
    /// Measured before this branch existed: with a rule holding the Mac, ⌥⌘K
    /// paused the rule; ⌥⌘K again did **not** put it back — it started a
    /// session by hand, so the shortcut oscillated between «rule paused» and
    /// «held by hand for ever» and could never reach «just the rule». Off,
    /// then on, has to be where you started.
    public func toggleSession() {
        if isActive {
            stopSession()
        } else if suppressed {
            resumeAutomation()
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
        // The one path where an administrator dialog is expected: somebody
        // pressed a button a moment ago and is still looking at the screen.
        recompute(byGesture: true)
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

    /// Lift a suppression without starting a session.
    ///
    /// Not `startSession`: that is a manual session, which outlives the rule
    /// and would go on holding the Mac after the app quit. The automatic
    /// conditions are true or they are not; this only stops ignoring them, and
    /// if none of them holds any more the recompute simply finds nothing.
    public func resumeAutomation() {
        guard suppressed else { return }
        suppressed = false
        HelmLog.shared.info("keepawake", "automation resumed by hand")
        recompute()
    }

    // MARK: - Core recompute

    /// - Parameter byGesture: this recompute follows something the person just
    ///   did. **Only a gesture may raise an administrator password dialog.**
    ///   Engaging the closed-lid setting installs a NOPASSWD sudoers rule, and
    ///   that was reached from here on every false→true edge of `isActive` —
    ///   including the edges a *rule* causes. So a watched app launching put a
    ///   real system password prompt on screen with nothing on it naming the
    ///   app, the rule or Helm, at a moment the person had touched nothing; and
    ///   any process running as this user could choose that moment by launching
    ///   the app. Automatic paths still engage when the grant already exists —
    ///   that costs no dialog — and otherwise say so in the log and carry on
    ///   holding sleep the ordinary way.
    private func recompute(byGesture: Bool = false) {
        // The battery guard is a **veto, not a suppression.** While the charge is
        // under the floor nothing may hold the Mac — and the moment the charger
        // goes in the veto lifts by itself, because it is recomputed rather than
        // remembered. Written as `stopSession()` it borrowed the person's verb:
        // `suppressed` means somebody said stop, and suppression only lifts when
        // the *trigger* drops and returns — so a rule silenced by a flat battery
        // stayed silenced after the Mac was plugged back in. Written as
        // `deactivate()` it did nothing at all, since the rule simply took the
        // Mac again on the next recompute.
        // **The sets are refreshed before the veto returns, not after it.**
        // They used to be computed further down, past this `return`, so while a
        // veto was in force both kept whatever they held when it began: the
        // hero went on offering to pause a rule that was not holding, a row
        // read «Paused» from a trigger that had dropped, and the figure named
        // an app that had since quit.
        refreshTriggers()
        guard !batteryVetoes() else {
            batteryStopped = true
            releaseForBattery()
            return
        }
        batteryStopped = false

        // Read from the set `refreshTriggers` just built, not asked of the
        // ports a second time: three more reads of the display list, the power
        // source and the running applications, on every event, for answers this
        // recompute already has — and two of them could differ from the ones
        // the screen is about to be told about.
        if suppressed && triggeredConditions.isEmpty {
            suppressed = false
        }

        var inputs = Conditions.Inputs()
        inputs.manual = manualOn
        inputs.timerRunning = (endDate != nil && endDate! > clock.now())
        inputs.externalDisplay = triggeredConditions.contains(.externalDisplay)
        inputs.onPower = triggeredConditions.contains(.power)
        inputs.appRunning = triggeredConditions.contains(.app)
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
            if MacHardware.hasLid, settings.clamshellEnabled {
                lid.engage(mayPrompt: byGesture)
            }
            if settings.jiggleEnabled { scheduleJiggle() }
            scheduleBatteryWatch()
        } else if !r.isActive && isActive {
            assertions.release()
            HelmLog.shared.info("keepawake", "released")
            if lid.active { lid.disengage() }
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
        // Consumed before the `isActive` guard — see `consumeRisingEdge`.
        let switchedOn = lid.consumeRisingEdge()
        guard isActive else { return }
        assertions.release()
        assertions.preventSleep(display: settings.keepDisplayOn)
        if settings.clamshellEnabled, !lid.active {
            lid.engage(mayPrompt: switchedOn)
        } else if !settings.clamshellEnabled, lid.active {
            lid.disengage()
        }
        if settings.jiggleEnabled, jiggleToken == nil {
            scheduleJiggle()
        } else if !settings.jiggleEnabled {
            jiggleToken = nil
        }
        emitState()
    }

    private func externalDisplayCondition() -> Bool {
        // The page hides this rule on a Mac with no display of its own, and the
        // engine has to agree — a stored `true` from a machine that was a
        // laptop last week, or from a hand-edited plist, would otherwise hold a
        // Mac mini awake for ever through a row nobody can see to switch off.
        guard MacHardware.hasBuiltInDisplay else { return false }
        return settings.autoExternalDisplay
            && ExternalDisplaySupport.hasExternal(builtInFlags: displayInfo.builtInFlags())
    }
    private func powerCondition() -> Bool {
        // `snapshot()` is nil for two different reasons and this read them as
        // one. A Mac with no battery — mini, Studio, iMac — has an empty power
        // source list, so nil there means «no battery, therefore mains», and
        // reading it as «not on power» made this rule dead on every desktop,
        // along with every app rule narrowed to `.power`. Nil for an
        // *incomplete* dictionary still has to mean not-on-power, because
        // ending a session early is this module's safe failure.
        settings.autoPower && power.isOnMains
    }
    private func appCondition() -> Bool { !holdingAppRules().isEmpty }

    private func holdingAppRules() -> [String] {
        let rules = settings.appTriggers
        guard !rules.isEmpty else { return [] }
        // A rule may be narrowed to "only at the desk" or "only plugged in",
        // so the same inputs the other conditions use are passed in.
        return AppTriggerRules.holding(
            rules,
            running: Set(apps.runningBundleIDs()),
            externalDisplay: ExternalDisplaySupport.hasExternal(builtInFlags: displayInfo.builtInFlags()),
            // `isOnMains`, like `powerCondition` above. This site was left on
            // `snapshot()` when that fix landed, so a rule narrowed to «only
            // when plugged in» stayed dead on every Mac without a battery —
            // the exact defect the commit claimed to have closed.
            onPower: power.isOnMains)
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
        switch TimerPolicy.onExpiry(hasAutoCondition: currentAutoConditionHolds(),
                                    suppressed: suppressed,
                                    timerEndsAutomation: settings.timerEndsAutomation) {
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
            // A session ending because a rule was asked to end with its timer
            // reads, from outside, exactly like one ending because the timer
            // ran out — and the two leave the Mac in different states: this one
            // leaves an automatic condition true and deliberately ignored.
            if settings.timerEndsAutomation && currentAutoConditionHolds() {
                HelmLog.shared.info("keepawake",
                                    "timer ended; automation suppressed until the trigger returns")
            }
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

    /// True while the charge is under the floor the person set.
    /// What the screens read about the rules, whatever else this recompute
    /// decides. Same three expressions `stopSession` consults, built once.
    private func refreshTriggers() {
        holdingApps = holdingAppRules()
        triggeredConditions = []
        if externalDisplayCondition() { triggeredConditions.insert(.externalDisplay) }
        if powerCondition() { triggeredConditions.insert(.power) }
        if !holdingApps.isEmpty { triggeredConditions.insert(.app) }
    }

    private func batteryVetoes() -> Bool {
        guard MacHardware.hasBattery else { return false }
        // No reading is two states and `isOnMains` tells them apart, the same
        // split `powerCondition` above was corrected for. «No veto» for both
        // switched the guard off exactly where it matters: a laptop on battery
        // whose IOKit dictionary came back short, holding an indefinite session
        // nothing else ever ends.
        guard let snap = power.snapshot() else {
            return BatteryGuard.shouldDeactivateWithNoReading(
                enabled: settings.batteryGuardEnabled, isOnMains: power.isOnMains)
        }
        return BatteryGuard.shouldDeactivate(enabled: settings.batteryGuardEnabled,
                                             isOnBattery: snap.onBattery,
                                             percent: snap.percent,
                                             threshold: settings.batteryGuardPercent)
    }

    /// Let go, and say so once — not once per power notification.
    private func releaseForBattery() {
        activeConditions = []
        // A session that was *asked for* counts, even though it never became
        // active: pressing «15 min» at 5 % now refuses instantly rather than
        // holding the Mac for the thirty seconds until the watch ticks, and a
        // refusal nobody is told about is the module failing silently at the
        // one thing it was asked to do.
        guard isActive || manualOn || endDate != nil else { emitState(); return }
        // The session ends without the person touching anything, so the log is the
        // only place that can say who ended it and why — and a figure it did not
        // read has no business in it. This was `percent ?? 0`, which reads as 0%:
        // a measurement nobody took, and the one charge that means the Mac is
        // about to go out.
        let charge = power.snapshot().map { "\($0.percent)%" } ?? "an unreadable charge"
        HelmLog.shared.info("keepawake", "battery guard stopped the session at "
                            + "\(charge) (floor \(settings.batteryGuardPercent)%)")
        assertions.release()
        if lid.active { lid.disengage() }
        cancelTimers()
        isActive = false
        // A hand-started session really is over — there is no deadline left to
        // come back to. A rule is not: it holds again the moment the veto lifts.
        manualOn = false
        endDate = nil
        startDate = nil
        rememberSession()
        emitState()
    }

    private func batteryCheck() {
        // One decision, in `recompute`. This used to hold a copy of it and call
        // `stopSession()`, which is how the guard came to borrow a verb that
        // means «a person said stop».
        recompute()
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

    /// The `settingsChanged` path, reachable without a transport hop.
    ///
    /// The command handler does these three in this order, and a test of what
    /// happens when a setting changes should not have to encode a JSON payload
    /// to say so.
    func settingsChangedForTests() {
        recompute()
        reconcileActiveSettings()
        lid.releaseIfUnneeded()
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
        /// A rule that applies and is being ignored. Every other field here
        /// describes a Mac being held awake; this one is the only account of a
        /// Mac that is not, while everything on screen says it should be.
        public let suppressed: Bool
        /// Defaulted, because this field arrived after the wire did and an
        /// older payload still has to decode. Absent means «no rule's trigger
        /// holds», which is the reading that shows no caption and no «Paused»
        /// note — a screen that says nothing beats a screen that says the
        /// wrong thing.
        public var triggeredConditions: [String] = []
        /// Defaulted for the same reason as the field above: it arrived after
        /// the wire did, and an older payload has to decode.
        public var holdingApps: [String] = []
        /// Defaulted like the two above: it arrived after the wire did.
        public var batteryStopped: Bool = false
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
            case .resumeAutomation:
                self.resumeAutomation()
            case .settingsChanged:
                self.recompute()
                self.reconcileActiveSettings()
                self.lid.releaseIfUnneeded()
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
                                    startDate: startDate,
                                    suppressed: suppressed,
                                    triggeredConditions: triggeredConditions
                                        .map(\.rawValue).sorted(),
                                    holdingApps: holdingApps,
                                    batteryStopped: batteryStopped)
        localTransport.emit(KeepAwakeEvent.state, encoding: payload)
    }
}
