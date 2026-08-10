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
    /// An admin password prompt is on screen and has not been answered.
    ///
    /// Nothing else can stand for this. `isSudoersInstalled()` asks the
    /// filesystem, and the file appears only when the person types their
    /// password — so for the whole life of the prompt, which is seconds to
    /// minutes, the answer is the same "no" that started it.
    private var sudoersInstallInFlight = false
    /// The other half of the same guard. `removeSudoers` also puts up an
    /// administrator dialog, and `releaseSudoersIfUnneeded` runs on
    /// `settingsChanged` — which the settings page sends on every control it
    /// draws. Five ordinary edits with the lid option off produced five
    /// password prompts, because `/etc/sudoers.d` still holds the rule for the
    /// whole life of the dialog and every edit asked again.
    private var sudoersRemovalInFlight = false
    /// The last value of `clamshellEnabled` this engine acted on, so the rising
    /// edge of the switch can be told from the setting merely being true.
    /// Seeded from the store at construction: a launch with the setting already
    /// on is not somebody switching it on.
    private var lastClamshellSetting = false

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
        self.lastClamshellSetting = settings.clamshellEnabled
        wireTransport()
    }

    // MARK: - ModuleEngine (module enabled/disabled)

    public func activate() {
        // Only shell out to pmset when we actually recorded disabling sleep;
        // Swift evaluates both call arguments, so short-circuit with the flag.
        if store.bool(KeepAwakeSettings.Key.clamshellGuard, default: false),
           ClamshellRecovery.sleepDisabled(inPmsetOutput: clamshell.pmsetReport()) {
            _ = clamshell.setDisableSleep(false)
            store.set(false, for: KeepAwakeSettings.Key.clamshellGuard)
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
        // Switching the module off is a decision, and the sudo rule is the one
        // thing here that would otherwise outlive it — outlive quitting Helm,
        // and outlive deleting it. `/etc/sudoers.d` on the machine this was
        // written on holds two abandoned NOPASSWD grants from predecessors;
        // that is what «the rule survives the app» looks like a year later.
        releaseSudoersOnTeardown()
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
        guard !batteryVetoes() else {
            releaseForBattery()
            return
        }
        let ext = externalDisplayCondition()
        let pwr = powerCondition()
        let appR = appCondition()

        // Same three the suppression test below uses, and the same three
        // `stopSession` consults — built once here, so the caption on screen
        // and the behaviour it describes cannot come apart.
        triggeredConditions = []
        if ext { triggeredConditions.insert(.externalDisplay) }
        if pwr { triggeredConditions.insert(.power) }
        if appR { triggeredConditions.insert(.app) }

        if suppressed && triggeredConditions.isEmpty {
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
            if MacHardware.hasLid, settings.clamshellEnabled {
                engageClamshell(mayPrompt: byGesture)
            }
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
        // The switch's rising edge, not its value. `settingsChanged` arrives
        // for every control the page draws, and the value stays true after a
        // password dialog is *declined* — so asking on the value put a dialog
        // in front of somebody for every later edit of an unrelated setting.
        // The same shape as `sudoersRemovalInFlight`, which was the other half
        // of this defect.
        //
        // Read before the `isActive` guard, so an edge that happens while the
        // module is idle is *consumed* rather than saved up for whichever
        // unrelated edit happens to arrive after a rule starts a session.
        let switchedOn = settings.clamshellEnabled && !lastClamshellSetting
        lastClamshellSetting = settings.clamshellEnabled
        guard isActive else { return }
        assertions.release()
        assertions.preventSleep(display: settings.keepDisplayOn)
        if settings.clamshellEnabled, !clamshellActive {
            engageClamshell(mayPrompt: switchedOn)
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
    private func appCondition() -> Bool {
        let rules = settings.appTriggers
        guard !rules.isEmpty else { return false }
        // A rule may be narrowed to "only at the desk" or "only plugged in",
        // so the same inputs the other conditions use are passed in.
        return AppTriggerRules.isHolding(
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
    private func batteryVetoes() -> Bool {
        guard MacHardware.hasBattery else { return false }
        guard let snap = power.snapshot() else { return false }
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
        let percent = power.snapshot()?.percent ?? 0
        // The session ends without the person touching anything, so the log is
        // the only place that can say who ended it and why.
        HelmLog.shared.info("keepawake", "battery guard stopped the session at "
                            + "\(percent)% (floor \(settings.batteryGuardPercent)%)")
        assertions.release()
        if clamshellActive { disengageClamshell() }
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

    // MARK: - Clamshell

    private func engageClamshell(mayPrompt: Bool) {
        // The capability, not our filename. A rule written by something else —
        // a predecessor, an admin, a migration — grants exactly this, and
        // asking about the file made Helm request a password to install what
        // was already there.
        if !clamshell.canDisableSleepWithoutPassword() {
            // Nobody is expecting a password dialog, so there will not be one.
            // The session goes ahead: an IOKit assertion holds an open Mac
            // awake perfectly well, and the lid is the only part that needs
            // the rule.
            guard mayPrompt else {
                HelmLog.shared.info("keepawake", "closed-lid sleep needs an administrator "
                                    + "rule; not asking for one outside a deliberate start")
                return
            }
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
    /// Unconditional: the module is being switched off, so the grant has no
    /// customer left whatever the stored setting says.
    /// The `settingsChanged` path, reachable without a transport hop.
    ///
    /// The command handler does these three in this order, and a test of what
    /// happens when a setting changes should not have to encode a JSON payload
    /// to say so.
    func settingsChangedForTests() {
        recompute()
        reconcileActiveSettings()
        releaseSudoersIfUnneeded()
    }

    private func releaseSudoersOnTeardown() {
        guard clamshell.isSudoersInstalled() else { return }
        clamshell.removeSudoers { _ in }
    }

    private func releaseSudoersIfUnneeded() {
        guard !settings.clamshellEnabled, clamshell.isSudoersInstalled() else { return }
        // Removing our file is all this can do; whether the *capability* went
        // with it is a different question, asked below once the file is gone.
        guard !sudoersRemovalInFlight else { return }
        sudoersRemovalInFlight = true
        clamshell.removeSudoers { [weak self] _ in
            guard let self else { return }
            // The file is gone and the grant may not be. Measured on a real
            // machine: `/etc/sudoers.d` held the identical rule under another
            // name, so «removed» was reported while any process running as this
            // user still had passwordless `pmset disablesleep`. A revocation
            // that revokes nothing is worse than none, because it is reported
            // as done.
            //
            // Read here rather than in a hop: this touches no engine state, and
            // a hop would put the check after the caller returns — which is how
            // a synchronous fake releases a gate before the thing it gates has
            // happened, and how a test of it passes for free.
            if self.clamshell.canDisableSleepWithoutPassword() {
                HelmLog.shared.warn("keepawake",
                                    "a passwordless pmset rule survives that Helm did not write")
            }
            // Engine state does hop: cleared whatever the answer was, because a
            // declined removal has to be askable again and a flag left standing
            // would mean the rule could never come off for the life of the
            // process.
            Task { @MainActor in self.sudoersRemovalInFlight = false }
        }
    }

    private func reallyEngageClamshell() {
        // The sudoers prompt is async; the session may have already ended (or
        // clamshell may have been disabled) by the time the user answers it.
        // Never disable sleep for a session that is no longer active.
        guard isActive, settings.clamshellEnabled else { return }
        // The flag before the call, and it stays set if the call fails: it is a
        // note to the next launch that this app *may* have left system sleep
        // off, and the expensive mistake is missing that, not repeating it.
        store.set(true, for: KeepAwakeSettings.Key.clamshellGuard)
        // The result is the whole point. `sudo -n` fails whenever the NOPASSWD
        // rule is gone — removed by an admin, by a migration, by somebody
        // tidying `/etc/sudoers.d` — and the two ends of this used to discard
        // it. Claiming a lid is safe to close is the one claim in this module
        // that costs somebody a dead battery in a bag.
        guard clamshell.setDisableSleep(true) else {
            HelmLog.shared.warn("keepawake", "closed-lid sleep could not be disabled")
            clamshellActive = false
            emitState()
            return
        }
        clamshellActive = true
        // A change to the system's own sleep setting, made through sudo and
        // outliving the process — the one thing this module does that a crash can
        // leave behind. Both ends of it belong in the trail.
        HelmLog.shared.info("keepawake", "closed-lid sleep disabled")
    }

    private func disengageClamshell() {
        // If this fails, system sleep is still off — machine-wide, past this
        // process — and clearing the guard would take away the only thing that
        // brings the next launch back to look. The Mac would never sleep again
        // and every screen would say Keep Awake was off.
        guard clamshell.setDisableSleep(false) else {
            HelmLog.shared.warn("keepawake", "closed-lid sleep could not be restored")
            return
        }
        store.set(false, for: KeepAwakeSettings.Key.clamshellGuard)
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
                                    startDate: startDate,
                                    suppressed: suppressed,
                                    triggeredConditions: triggeredConditions
                                        .map(\.rawValue).sorted())
        localTransport.emit(KeepAwakeEvent.state, encoding: payload)
    }
}
