import Foundation
import HelmRuntime

/// «Stay awake with the lid closed», and everything it costs.
///
/// **The one thing this module does that outlives its own process.** It is
/// `sudo pmset disablesleep 1` — a system-wide setting, above every IOKit
/// assertion, still in force after Helm quits — reached through a NOPASSWD
/// rule in `/etc/sudoers.d`. One port and a handful of flags, and no other part
/// of the engine reads any of them: the session logic asks for the lid and is
/// told whether it got it. The code that can leave a Mac unable to sleep, and
/// the code that can put a root password dialog on somebody's screen, is one
/// file with one set of tests pointed at it
/// (`Architecture/KeepAwake.md § The closed lid`).
///
/// Two things it must be told rather than ask, because both change *while a
/// password prompt is up* and the prompt can take minutes:
/// - `sessionIsActive`, so an answer that arrives after the session ended does
///   not disable sleep for nothing;
/// - `stateChanged`, because a refusal discovered in a callback has to reach
///   the screen, and the engine owns the published state.
/// `@unchecked Sendable` and **not** `@MainActor`, which is the engine's own
/// shape and is load-bearing here: `removeSudoers` calls back on a background
/// queue, and the check it makes there — «did the grant go with the file» —
/// deliberately runs on that queue rather than after a hop. A hop would put it
/// after the caller returned, and a synchronous fake would release a gate
/// before the thing it gates has happened. What does hop is state of ours.
final class ClamshellCoordinator: @unchecked Sendable {
    private let clamshell: ClamshellPort
    private let store: NamespacedStore
    private let settings: KeepAwakeSettings

    /// Where this port's child processes go.
    ///
    /// Most of `ClamshellPort` is `HelmProcess.run`, which waits for a child
    /// with **no deadline** and takes one of the slots shared with every other
    /// module, Homebrew's long searches included. And the callers here are the
    /// thread that draws: `activate()` is the host's module enable, at launch,
    /// and `recompute` runs from the display, power and application observers,
    /// which all deliver on main. Run here, a busy Homebrew page could park the
    /// main thread before anything is drawn.
    ///
    /// Serial, not `.global()`: one launch asks `pmset` twice and the second
    /// question only makes sense after the first is answered, and nothing here
    /// is worth two threads.
    private let shell = DispatchQueue(label: "helm.keep-awake.pmset", qos: .userInitiated)

    /// Is a session running *now* — asked at the moment of use, never captured
    /// as a value. Set by the engine after construction rather than passed in,
    /// because both of these close over the engine and the engine owns this.
    var sessionIsActive: () -> Bool = { false }
    var stateChanged: () -> Void = {}

    /// Sleep really is disabled system-wide, as far as `pmset` was willing to
    /// say. Every surface that says «sleep is off for the whole Mac» draws this,
    /// so it is false whenever the call refused.
    private(set) var active = false

    /// macOS was asked to turn sleep off and said no.
    ///
    /// Not the same as `active` being false, which reads as *nothing has
    /// happened*: only a refusal is a switch that says one thing while the
    /// machine does another, and this module's whole claim is that a lid is safe
    /// to close.
    ///
    /// Cleared by the next attempt that succeeds, so it is the state of the last
    /// answer rather than a memory of the worst one.
    private(set) var refused = false

    /// The option is off and the rule is still there.
    ///
    /// A declined administrator dialog is an answer; what it leaves behind is a
    /// permanent passwordless `pmset disablesleep` for this account, which is the
    /// price of a feature nobody is using any more.
    ///
    /// **It is a reading, not a memory of one call.** `/etc/sudoers.d` is a
    /// directory this account cannot write and anything with a password can, so
    /// an administrator may take the file out by hand. `lookForTheRule` keeps it
    /// current, and the look it makes is `fileExists`, not a child process.
    private(set) var grantRemains = false

    /// State of ours, on the thread it belongs to.
    ///
    /// Called from `shell` it hops; called from the main thread it runs **now**,
    /// which is not a convenience: `tearDown` is what `applicationWillTerminate`
    /// reaches, and the last word about system sleep may not be posted to a
    /// queue the process will not live to drain. The port's own reads
    /// deliberately do not hop — see `removeGrant`.
    private func onMain(_ block: @escaping @Sendable () -> Void) {
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }

    /// The one writer of `grantRemains`, so a change always reaches the published state.
    ///
    /// `releaseIfUnneeded` runs *after* the last `emitState` of a
    /// `settingsChanged`, so a value set there and not announced would sit in
    /// the engine until something else happened to emit.
    private func noteGrantRemains(_ value: Bool) {
        guard grantRemains != value else { return }
        grantRemains = value
        stateChanged()
    }

    /// Is our rule on disk — and say so while we are looking.
    ///
    /// Callable from either thread: the look belongs to the port and stays
    /// where it was asked from, the verdict is ours and lands on main.
    ///
    /// The read and the write are therefore not one critical section, and the
    /// cost is stated rather than engineered away: the launch look runs on
    /// `shell` while a settings edit looks on main, so an edit made in the same
    /// instant as the launch could have its verdict overtaken by the launch's
    /// older one. What that costs is one stale row until the next edit, and the
    /// alternative — a second `fileExists` on the main thread per launch — buys
    /// nothing else.
    private func lookForTheRule() -> Bool {
        let installed = clamshell.isSudoersInstalled()
        // The complaint is only about a rule nobody is using: while the option
        // is on, the same file is the feature working. The option is read in
        // the block, on main, so the verdict uses the value current when it lands.
        onMain { [self] in noteGrantRemains(installed && !settings.clamshellEnabled) }
        return installed
    }

    /// An admin password prompt is on screen and has not been answered.
    ///
    /// Nothing else can stand for this. `canDisableSleepWithoutPassword()` asks
    /// the system, and the grant appears only once the person types their
    /// password — so for the whole life of the prompt, which is seconds to
    /// minutes, the answer is the same "no" that started it.
    private var installInFlight = false
    /// The other half of the same guard. `removeSudoers` also puts up an
    /// administrator dialog, and `releaseIfUnneeded` runs on `settingsChanged`
    /// — which the settings page sends on every control it draws.
    private var removalInFlight = false
    /// A `canDisableSleepWithoutPassword()` probe is out on `shell`, and the
    /// OR of every `mayPrompt` asked while it was. Both are written on main.
    private var probeInFlight = false
    private var pendingMayPrompt = false
    /// The last value of `clamshellEnabled` acted on, so the switch's rising
    /// edge can be told from the setting merely being true. Seeded from the
    /// store: a launch with the setting already on is not somebody switching it
    /// on.
    private var lastSetting: Bool

    init(clamshell: ClamshellPort, store: NamespacedStore, settings: KeepAwakeSettings) {
        self.clamshell = clamshell
        self.store = store
        self.settings = settings
        self.lastSetting = settings.clamshellEnabled
    }

    // MARK: - Lifecycle

    /// What the last run may have left behind.
    ///
    /// The guard flag is a note that this app *may* have turned system sleep
    /// off; it survives a crash, which is the case it exists for. **It does not
    /// survive somebody editing the plist**, which every process running as this
    /// user can write: on its own, clearing the note would leave system sleep off
    /// for good, with every screen saying Keep Awake is idle.
    ///
    /// The rule on disk is the second anchor, and it cannot be arranged from
    /// this account: `/etc/sudoers.d` is `0755`, so `fileExists` answers with no
    /// grant, while the rule inside it is `0440 root:wheel` and removable only
    /// with a password. Either anchor is a reason to go and *look*; what
    /// `pmset -g` says decides whether anything is put back.
    ///
    /// With neither anchor nothing is shelled out: a Mac that has never had the
    /// lid option switched on pays two reads of local state.
    ///
    /// **And when there is an anchor, the two child processes it leads to run on
    /// `shell`.** This is `activate()`, which the host calls on the main thread
    /// while it is putting the app together; `pmset -g` and `sudo pmset
    /// disablesleep 0` are two waits with no deadline behind a semaphore shared
    /// with `brew`, and nothing is drawn until they answer.
    func recoverAtLaunch() {
        let noted = store.bool(KeepAwakeSettings.Key.clamshellGuard, default: false)
        shell.async { [self] in
            // Asked first rather than as the second half of an `||`, so the
            // launch that finds the note set still looks at the rule: this is
            // the reading the lid row draws.
            let ruleOnDisk = lookForTheRule()
            guard noted || ruleOnDisk else { return }
            // A nil report is not an empty one: nothing was read. With Helm's
            // note set, sleep may be off and putting it back is idempotent; with
            // only the rule on disk the person may have set the block themselves.
            if let report = clamshell.pmsetReport() {
                guard ClamshellRecovery.sleepDisabled(inPmsetOutput: report) else { return }
            } else if noted {
                HelmLog.shared.warn(KeepAwakeEngine.moduleID,
                                    "pmset -g could not be read; restoring sleep because Helm's note says it may have disabled it")
            } else {
                HelmLog.shared.info(KeepAwakeEngine.moduleID,
                                    "pmset -g could not be read; leaving system sleep as it is")
                return
            }
            restoreSleep(refused: "closed-lid sleep could not be restored at launch",
                         restored: "closed-lid sleep restored at launch")
        }
    }

    /// Put system sleep back, and keep the note if `pmset` refused.
    ///
    /// The refusal is the case both callers exist for: the rule this needs can
    /// be gone — removed by an admin, by a migration, by somebody tidying
    /// `/etc/sudoers.d` — and then sleep stays off machine-wide, past this
    /// process. Clearing the guard there takes away the only thing that brings
    /// the next launch back to look, so the Mac would never sleep again while
    /// every screen said Keep Awake was idle.
    ///
    /// One function for both callers, with the sentences theirs, so a refusal
    /// cannot be reported by one path and swallowed by the other.
    ///
    /// **The call runs wherever it is called from and the state always lands on
    /// main.** Off `shell` at launch; on the caller's own thread from
    /// `disengage`, because that is what `tearDown` reaches from
    /// `applicationWillTerminate` — a restore posted to a queue is a restore a
    /// dying process may never make, and a Mac left unable to sleep is this
    /// module's worst failure.
    private func restoreSleep(refused: String, restored: String) {
        let putBack = clamshell.setDisableSleep(false)
        onMain { [self] in
            guard putBack else {
                HelmLog.shared.warn(KeepAwakeEngine.moduleID, refused)
                // Told, for the same reason `reallyEngage`'s refusal tells: this
                // class does not assume its callers emit, and the launch
                // recovery answers after `activate()` has returned.
                stateChanged()
                return
            }
            store.set(false, for: KeepAwakeSettings.Key.clamshellGuard)
            active = false
            HelmLog.shared.info(KeepAwakeEngine.moduleID, restored)
            stateChanged()
        }
    }

    /// The module is being switched off, or Helm is quitting. **Sleep goes back,
    /// and the grant with it wherever it has nothing left to do.**
    ///
    /// **No dialog is raised here.** `deactivate()` is what
    /// `applicationWillTerminate` calls on every live engine, and a password
    /// dialog for an app that is already gone is one nobody answers. The
    /// withdrawal is `sudo -n`, because the rule permits its own removal; a rule
    /// too old to make that promise is left where it is. **A refused restore
    /// keeps its grant**, because the next launch needs
    /// `sudo -n pmset disablesleep 0` to put sleep back; `withdrawAtQuit` names
    /// all three states in which the rule is load-bearing.
    ///
    /// `releaseIfUnneeded()` takes it out on the option's own falling edge. A
    /// crash leaves the rule, which is what `recoverAtLaunch` wants.
    /// - Parameter sessionWillResume: a session the person asked for is still
    ///   running, so the next launch brings it back.
    func tearDown(sessionWillResume: Bool) {
        if active { disengage() }
        withdrawAtQuit(sessionWillResume: sessionWillResume)
    }

    /// Take the rule out on the way past — but only where it has nothing left to
    /// do.
    ///
    /// **This is the case dragging the app to the Trash leaves open**, and it is
    /// how a Mac application is normally removed: no code runs, so the grant
    /// would stay for the life of the machine. Most people quit before they
    /// delete, and quitting is code.
    ///
    /// This is `sudo -n`, silent, with nothing to decline; a rule too old to
    /// withdraw itself is left for the lid option's own switch to take out.
    ///
    /// Synchronous, on the thread that is quitting, for the reason `restoreSleep`
    /// is: work posted to a queue on the way out is a promise this process may
    /// not live to keep.
    ///
    /// The three refusals are the three states in which the grant is still
    /// load-bearing, and each of them costs something a person would notice:
    /// - sleep is still off (`active`, or the note to the next launch is set),
    ///   and putting it back needs `sudo -n pmset disablesleep 0` — this grant.
    ///   Withdraw it and the Mac never sleeps again, with every screen saying
    ///   Keep Awake is idle;
    /// - a session will resume with the lid option on. Helm's own updater
    ///   terminates and relaunches, and the resumed session engages the lid
    ///   without prompting — so the grant's absence would be silent;
    /// - a removal is already under way (`willDisable` asked for one), and that
    ///   route is allowed the dialog this one is not.
    ///
    /// `isSudoersInstalled()` rather than `lookForTheRule()`: the verdict that
    /// one publishes is posted to a main queue this process will not drain.
    ///
    /// **One case stays open: deleting Helm while it is still running leaves
    /// the rule.** No code runs, so nothing withdraws it. Nothing closes that
    /// without a Developer ID and a privileged helper the system removes with
    /// the app (`Architecture/StoredSettings.md § Sealed settings`). Until then
    /// `KAStr.lidExplainer` names the `sudo rm` that removes it, before the
    /// password is asked for.
    private func withdrawAtQuit(sessionWillResume: Bool) {
        guard !active,
              !store.bool(KeepAwakeSettings.Key.clamshellGuard, default: false),
              !(sessionWillResume && settings.clamshellEnabled),
              !removalInFlight,
              clamshell.isSudoersInstalled()
        else { return }
        guard clamshell.removeSudoersWithoutPassword() else {
            HelmLog.shared.info(KeepAwakeEngine.moduleID,
                                "the pmset rule cannot withdraw itself; leaving it for the lid option")
            return
        }
        HelmLog.shared.info(KeepAwakeEngine.moduleID, "the passwordless pmset rule was withdrawn at quit")
    }

    // MARK: - Engaging

    /// - Parameter mayPrompt: this follows something the person just did.
    ///   **Only a gesture may raise an administrator password dialog.** Engaging
    ///   is reached on every false→true edge of «the Mac is now being held
    ///   awake», including the edges a *rule* causes; a prompt there would name
    ///   nothing the person did, and any process running as this user could
    ///   choose its moment by launching a watched app.
    func engage(mayPrompt: Bool) {
        // The capability, not our filename: a rule written by something else
        // can grant exactly this (`ClamshellPort.canDisableSleepWithoutPassword`).
        //
        // It is also `sudo -n pmset disablesleep 0`: a child process, asked
        // *before* anything about a gesture is decided, from a recompute a
        // watched app launching causes. So it is asked on `shell` and every
        // decision that follows is made on main with the answer in hand.
        //
        // One probe at a time, because `releaseIfUnneeded` and `recompute` run on
        // every `settingsChanged`, which the settings page sends on every control
        // it draws. A call while one is out adds its `mayPrompt` to what is
        // pending and returns, so a gesture's prompt is never dropped by the
        // probe a rule started.
        pendingMayPrompt = pendingMayPrompt || mayPrompt
        guard !probeInFlight else { return }
        probeInFlight = true
        shell.async { [self] in
            let alreadyGranted = clamshell.canDisableSleepWithoutPassword()
            onMain {
                let pending = self.pendingMayPrompt
                self.probeInFlight = false
                self.pendingMayPrompt = false
                self.engage(mayPrompt: pending, alreadyGranted: alreadyGranted)
            }
        }
    }

    /// The half of `engage` that touches state of ours, with the one question
    /// that needed a child process already answered.
    private func engage(mayPrompt: Bool, alreadyGranted: Bool) {
        guard !alreadyGranted else {
            reallyEngage()
            return
        }
        // Nobody is expecting a password dialog, so there will not be one. The
        // session goes ahead: an IOKit assertion holds an open Mac awake
        // perfectly well, and the lid is the only part that needs the rule.
        guard mayPrompt else {
            HelmLog.shared.info(KeepAwakeEngine.moduleID, "closed-lid sleep needs an administrator "
                                + "rule; not asking for one outside the lid switch")
            return
        }
        // While a prompt is up the system still says the rule is missing, so
        // without this the person gets one dialog per click for a single
        // decision. A *declined* prompt is a different state: the flag clears
        // when the prompt is answered, so the next turn of the lid switch asks again.
        guard !installInFlight else { return }
        installInFlight = true
        clamshell.installSudoers { [weak self] granted in
            // The osascript callback arrives on a background queue; engine
            // state and store writes belong on main.
            DispatchQueue.main.async { self?.installFinished(granted: granted) }
        }
    }

    /// The prompt has been answered, and only now is there a grant to reason
    /// about. Both questions asked while it was up were asked of a rule that did
    /// not exist yet, so both are asked again here.
    private func installFinished(granted: Bool) {
        installInFlight = false
        guard granted else { return }
        reallyEngage()
        // `switchedOff: true`, and it is not a guess: a prompt stands for
        // minutes, and if the option went off while it was up, the falling edge
        // that carried the decision arrived when there was no file yet to
        // remove. A rule that lands for an option nobody has any more is the
        // same gesture, answered late.
        releaseIfUnneeded(switchedOff: !settings.clamshellEnabled)
    }

    private func reallyEngage() {
        // The prompt is async; the session may have ended, or the setting been
        // switched off, by the time it is answered. Never disable sleep for a
        // session that is no longer running.
        guard sessionIsActive(), settings.clamshellEnabled else { return }
        // The flag before the call, and it stays set if the call fails: it is a
        // note to the next launch that this app *may* have left system sleep
        // off, and the expensive mistake is missing that, not repeating it.
        store.set(true, for: KeepAwakeSettings.Key.clamshellGuard)
        // The result is the whole point. `sudo -n` fails whenever the NOPASSWD
        // rule is gone — removed by an admin, by a migration, by somebody
        // tidying `/etc/sudoers.d`. Claiming a lid is safe to close is the one
        // claim in this module that costs somebody a dead battery in a bag.
        guard clamshell.setDisableSleep(true) else {
            HelmLog.shared.warn(KeepAwakeEngine.moduleID, "closed-lid sleep could not be disabled")
            active = false
            // Asked and refused, which is not the same as never asked — and it is
            // the difference the lid row draws. Set before the emit, or the
            // payload this very call publishes still says nothing is wrong.
            refused = true
            stateChanged()
            return
        }
        active = true
        refused = false
        // A grant that is being used is not a grant left behind. The complaint
        // only makes sense while the option is off.
        noteGrantRemains(false)
        // A change to the system's own sleep setting, made through sudo and
        // outliving the process — the one thing here a crash can leave behind.
        // Both ends of it belong in the trail.
        HelmLog.shared.info(KeepAwakeEngine.moduleID, "closed-lid sleep disabled")
        // Every route here arrives after its caller has emitted — the grant is
        // asked for on `shell`, and the install prompt takes minutes — so «the
        // lid is safe to close» reaches the screen from here or not at all.
        stateChanged()
    }

    func disengage() {
        restoreSleep(refused: "closed-lid sleep could not be restored",
                     restored: "closed-lid sleep restored")
    }

    // MARK: - Settings

    /// What the option's switch did since the last `settingsChanged`.
    ///
    /// The edge, not the value: `settingsChanged` arrives for every control the
    /// page draws, and `clamshellEnabled` stays true after a password dialog is
    /// *declined* — so acting on the value would put a dialog in front of
    /// somebody for every later edit of an unrelated setting. Both directions are answered
    /// here, from one reading, because both cost an administrator password and
    /// the two halves of a reconcile must not each take their own.
    ///
    /// Read before the caller's own «is a session running» guard, so an edge
    /// that happens while the module is idle is *consumed* rather than saved up
    /// for whichever unrelated edit arrives after a rule starts a session. The
    /// switch's own rising edge is the exception: it is answered at once by asking
    /// for the grant (`reconcileActiveSettings`), session or not.
    func consumeEdge() -> Edge {
        let now = settings.clamshellEnabled
        defer { lastSetting = now }
        guard now != lastSetting else { return .none }
        return now ? .rising : .falling
    }

    /// Which way the option's switch moved. Three cases and no `default`
    /// anywhere: «nothing moved» is a case, and it is the common one.
    enum Edge {
        case none
        /// Switched on — the one gesture that may ask for the rule.
        case rising
        /// Switched off — the one gesture that may ask for it back.
        case falling
    }

    /// Switching the option off takes the passwordless rule back out. The rule
    /// is the price of the feature, not of having installed Helm.
    ///
    /// **Only the falling edge asks.** This runs on `settingsChanged`, which the
    /// page sends for every control it draws, a slider drag included. Asking on
    /// the *value* — the option is off, our file is there — would make each one
    /// an administrator password dialog, and a declined removal leaves exactly
    /// that state on disk for every future launch. The row's own words are
    /// «Switch this on and off again to remove it».
    ///
    /// - Parameter switchedOff: the option's falling edge — the gesture that
    ///   means «take that rule away». A decline is never final: switching it on
    ///   and off again asks again.
    func releaseIfUnneeded(switchedOff: Bool) {
        // The look is not the ask, and it happens on every settings change: it
        // is a `fileExists` on a 0755 directory, no child process and no
        // password. It is also the only thing that can ever *unsay* the row's
        // claim about a rule this app cannot see change.
        let installed = lookForTheRule()
        guard switchedOff, installed else { return }
        removeGrant()
    }

    /// The module is being switched off by hand in Settings, or «Reset all
    /// settings» is handing the system back.
    ///
    /// The same falling edge as the option's own, arrived at from one screen over:
    /// a module that is off will not use the grant either, and this is the last
    /// moment there is somebody at the screen to answer the dialog. `tearDown`
    /// cannot do it, because `applicationWillTerminate` calls that too
    /// (`tearDown` has why). What tells the two apart is
    /// `ModuleEngine.willDisable`, which only the person's own switch and «Reset
    /// all settings» call.
    ///
    /// On a switch-off the setting is left where it is: somebody who switches the
    /// module back on asked for the lid option once and will be asked for the
    /// password again, which is the same round trip switching the option off and
    /// on already makes.
    func releaseOnModuleDisabled() {
        guard lookForTheRule() else { return }
        removeGrant()
    }

    /// Silent on a declined prompt in the log's terms — that is an answer, not a
    /// fault — and **not** silent on screen: what a decline leaves behind is a
    /// permanent grant for a feature nobody is using.
    /// Both callers have looked already (`lookForTheRule`), which is what keeps
    /// the row's claim and the decision to ask one reading rather than two.
    private func removeGrant() {
        guard !removalInFlight else { return }
        removalInFlight = true
        // The child process belongs off the thread that draws: `releaseIfUnneeded`
        // runs from `settingsChanged`, which the page sends for every control it
        // draws.
        shell.async { [self] in
            // The rule permits its own withdrawal, so the ordinary route costs
            // nothing and asks nobody. Only a rule that cannot make that promise
            // — one with no `rm` line, one written by something else — reaches
            // the dialog.
            if clamshell.removeSudoersWithoutPassword() {
                finishedRemoving(true)
            } else {
                clamshell.removeSudoers { [weak self] removed in
                    self?.finishedRemoving(removed)
                }
            }
        }
    }

    /// Everything this coordinator has queued has run.
    ///
    /// `removeGrant` ends in `shell.async`, so a caller that awaits the command
    /// and then counts is counting a subject still in motion: a «no second
    /// dialog» assertion could pass over a second dialog that has not happened
    /// yet. `shell` is serial, so a block enqueued after the work runs after it:
    /// an ordering fact, not a sleep, the same shape as `drainMainQueue()` in the KeepAwake engine tests' `Fakes.swift`.
    func drainForTests() async {
        await withCheckedContinuation { done in shell.async { done.resume() } }
    }

    /// The one place a removal's answer is read, whichever route made it.
    private func finishedRemoving(_ removed: Bool) {
        // **Which rule survived decides who is being talked about.** A
        // declined dialog leaves *our* file exactly where it was, and that is
        // not a rule somebody else wrote.
        //
        // Read here rather than after a hop: these touch no state of ours,
        // and a hop would put the check after the caller returns, where a
        // synchronous fake releases a gate before the thing it gates.
        let ours = !removed && clamshell.isSudoersInstalled()
        if ours {
            HelmLog.shared.warn(KeepAwakeEngine.moduleID,
                                "the passwordless pmset rule Helm wrote was not removed")
        } else if clamshell.canDisableSleepWithoutPassword() {
            // The file is gone and the grant is not: another file grants the
            // same command (`ClamshellPort.canDisableSleepWithoutPassword`).
            HelmLog.shared.warn(KeepAwakeEngine.moduleID,
                                "a passwordless pmset rule survives that Helm did not write")
        }
        // State of ours does hop. `removalInFlight` is cleared whatever the
        // answer was, because a declined removal has to be askable again, and
        // a flag left standing would mean the rule could never come off for
        // the life of the process.
        Task { @MainActor in
            self.removalInFlight = false
            self.noteGrantRemains(ours)
        }
    }
}
