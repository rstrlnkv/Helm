import Foundation
import HelmRuntime

/// «Stay awake with the lid closed», and everything it costs.
///
/// **The one thing this module does that outlives its own process.** It is
/// `sudo pmset disablesleep 1` — a system-wide setting, above every IOKit
/// assertion, still in force after Helm quits — reached through a NOPASSWD
/// rule in `/etc/sudoers.d`. One port and a handful of flags, and no other part
/// of the engine reads any of them: the session logic asks for the lid and is
/// told whether it got it.
///
/// It lived inside `KeepAwakeEngine` among the timers and the battery guard.
/// Out here, the code that can leave a Mac unable to sleep, and the code that
/// can put a root password dialog on somebody's screen, is one file with one
/// set of tests pointed at it.
///
/// Two things it must be told rather than ask, because both change *while a
/// password prompt is up* and the prompt can take minutes:
/// - `sessionIsActive`, so an answer that arrives after the session ended does
///   not disable sleep for nothing;
/// - `stateChanged`, because a refusal discovered in a callback has to reach
///   the screen, and the engine owns the wire.
/// `@unchecked Sendable` and **not** `@MainActor`, which is the engine's own
/// shape and is load-bearing here: `removeSudoers` calls back on a background
/// queue, and the check it makes there — «did the grant go with the file» —
/// deliberately runs on that queue rather than after a hop. A hop would put it
/// after the caller returned, which is how a synchronous fake releases a gate
/// before the thing it gates has happened. What does hop is state of ours.
final class ClamshellCoordinator: @unchecked Sendable {
    private let clamshell: ClamshellPort
    private let store: NamespacedStore
    private let settings: KeepAwakeSettings

    /// Where this port's child processes go.
    ///
    /// Most of `ClamshellPort` is `HelmProcess.run`, which waits for a child
    /// with **no deadline** and takes one of eight slots shared with every other
    /// module — Homebrew's search is two `brew search` runs of about nine
    /// seconds each. And the callers here are the thread that draws: `activate()`
    /// is the host's module enable, at launch, and `recompute` runs from the
    /// display, power and application observers, which all deliver on main. So a
    /// Mac whose Homebrew page was busy could have its main thread parked inside
    /// this file before anything was drawn — the same shape
    /// `fix(settings): the thread that draws never waits for the keychain`
    /// (4dcc5fb6) took out of `SettingGuard`.
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
    /// `active` going false already carried this, and carried it as *nothing has
    /// happened* — which is what the row then said, in a paragraph about what an
    /// administrator password buys. The two states have to be told apart on the
    /// wire, because only one of them is a switch that says one thing while the
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
    /// price of a feature nobody is using any more. `removeSudoers`' own `Bool`
    /// was discarded, so the only record of it was a log line blaming somebody
    /// else for a rule Helm wrote.
    ///
    /// **It is a reading, not a memory of one call.** Written only in the
    /// removal's callback, it was a local flag standing in for a live fact about
    /// `/etc/sudoers.d` — a directory this account cannot write and anything
    /// with a password can — so an administrator taking the file out by hand
    /// left the row naming a root grant that was gone, with the only thing it
    /// offered being a way to remove it again. `lookForTheRule` is the reverse
    /// channel, and the look it makes is `fileExists`, not a child process.
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

    /// The one writer of `grantRemains`, so a change always reaches the wire.
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
    /// Every caller wanted the same fact and only the removal's callback ever
    /// published it. The stat is the one `recoverAtLaunch` already pays for; its
    /// answer is now kept rather than dropped. Callable from either thread: the
    /// look belongs to the port and stays where it was asked from, the verdict
    /// is ours and lands on main.
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
        let optionOn = settings.clamshellEnabled
        // The complaint is only about a rule nobody is using: while the option
        // is on, the same file is the feature working.
        onMain { [self] in noteGrantRemains(installed && !optionOn) }
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
    /// — which the settings page sends on every control it draws. Five ordinary
    /// edits with the lid option off produced five password prompts.
    private var removalInFlight = false
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
    /// survive somebody editing the plist**, and it lives in one every process
    /// running as this user can write — so on its own it made the recovery
    /// switchable off by anything on the machine: clear the note and system sleep
    /// stays off for good, with every screen saying Keep Awake is idle.
    ///
    /// The rule on disk is the second anchor, and it is the one that cannot be
    /// arranged from this account. Measured: `/etc/sudoers.d` is `0755`, so
    /// `fileExists` answers from uid 501 with no grant of any kind, while the rule
    /// inside it is `0440 root:wheel` — unreadable, and removable only with a
    /// password. Either anchor is a reason to go and *look*; what `pmset -g` says
    /// is still what decides whether anything is put back.
    ///
    /// The shell-out stays off the ordinary path: with neither anchor the
    /// second half of this guard is never evaluated, which is what a Mac that has
    /// never had the lid option switched on wants — the whole cost of it there is
    /// two reads of local state.
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
            // the reading the lid row draws, and short-circuiting it left the
            // page with nothing to say until the first settings edit.
            let ruleOnDisk = lookForTheRule()
            guard noted || ruleOnDisk,
                  ClamshellRecovery.sleepDisabled(inPmsetOutput: clamshell.pmsetReport())
            else { return }
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
    /// Written once because it was written twice: launch recovery discarded the
    /// result (`_ = clamshell.setDisableSleep(false)`) for as long as `disengage`
    /// had been reading it, so the same defect the tests here were written for
    /// survived its own fix on the other path.
    /// The sentences are the caller's, so a refusal cannot be reported by one
    /// path and swallowed by the other — which is the defect, not the wording.
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
                // class does not get to assume its callers emit. Every one of
                // them does today — `recompute`, `releaseForBattery`,
                // `reconcileActiveSettings`, `deactivate` and `activate` all end
                // in `emitState()` — and the launch recovery no longer does,
                // because it answers after `activate()` has returned.
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
    /// It used to remove the rule here too, and that was a promise this process
    /// cannot keep: `removeSudoers` dispatches to a global queue and runs
    /// `osascript … with administrator privileges`, while `deactivate()` is what
    /// `applicationWillTerminate` calls on every live engine. So quitting put an
    /// administrator password dialog on screen on behalf of an app that was
    /// already gone. `/etc/sudoers.d` on the machine this was written on holds
    /// two abandoned rules from predecessors — and this app's own removal was
    /// written the same way, so it was on course to leave a third.
    ///
    /// It also ran straight after the restore, whatever the restore answered. A
    /// refused restore leaves system sleep off machine-wide and keeps
    /// `clamshellGuard` set precisely so the next launch comes back and looks —
    /// and what that launch needs is `sudo -n pmset disablesleep 0`, i.e. this
    /// grant. The one path where the rule is load-bearing was the one taking it
    /// away.
    ///
    /// Both objections are answered rather than overruled, and only one of them
    /// was about the password. **The dialog is still never raised here** — the
    /// withdrawal is `sudo -n`, because the rule permits its own removal, and a
    /// rule too old to make that promise is left where it is. **And the refused
    /// restore still keeps its grant**, along with the two other states in which
    /// the rule is load-bearing; `withdrawAtQuit` names all three. What changed
    /// is the case neither objection covered: quit, then drag the app to the
    /// Trash, which runs no code and left the grant naming an application that
    /// no longer existed.
    ///
    /// `releaseIfUnneeded()` still takes it out on the option's own falling edge,
    /// and that edge is now free too. A crash still leaves the rule, which is
    /// what `recoverAtLaunch` wants.
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
    /// how a Mac application is normally removed: no code runs, so a grant that
    /// only a person at a screen could revoke stayed for the life of the machine
    /// naming an application that no longer existed. Most people quit before
    /// they delete, and quitting is code.
    ///
    /// It became affordable because the rule permits its own withdrawal: this is
    /// `sudo -n`, silent, with nothing to decline. **A dialog is never raised
    /// here** — `applicationWillTerminate` reaches this on every live engine, and
    /// nobody types a password into a dialog belonging to an app that is already
    /// gone. A rule too old to withdraw itself is therefore left where it is, for
    /// the lid option's own switch to take out.
    ///
    /// Synchronous, on the thread that is quitting, for the reason `restoreSleep`
    /// is: work posted to a queue on the way out is a promise this process may
    /// not live to keep. It is one `sudo -n rm` beside the one `sudo -n pmset`
    /// already spent there.
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
    /// **One case stays open, and it is written here rather than papered over:
    /// deleting Helm while it is still running leaves the rule.** No code runs,
    /// so nothing withdraws it, and the file then names an application that is
    /// gone. Nothing closes that without a Developer ID and a real privileged
    /// helper the system removes with the app — the fifth thing that purchase is
    /// blocking, beside `NEVPNManager`, `SMAppService`, notarization and a
    /// stable cdhash for TCC and the keychain (ARCHITECTURE.md § A seal needs a
    /// signature). Until then the answer is a sentence: `KAStr.adminNote` names
    /// the path and the `sudo rm` that removes it, before the password is asked
    /// for rather than after.
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
    ///   was reached on every false→true edge of «the Mac is now being held
    ///   awake», including the edges a *rule* causes — so a watched app
    ///   launching put a real system password prompt on screen with nothing on
    ///   it naming the app, the rule or Helm, at a moment the person had touched
    ///   nothing; and any process running as this user could choose that moment
    ///   by launching the app.
    func engage(mayPrompt: Bool) {
        // The capability, not our filename. A rule written by something else —
        // a predecessor, an admin, a migration — grants exactly this, and
        // asking about the file made Helm request a password to install what
        // was already there.
        //
        // It is also `sudo -n pmset disablesleep 0`: a child process, asked
        // *before* anything about a gesture is decided, from a recompute a
        // watched app launching causes. So it is asked on `shell` and every
        // decision that follows is made on main with the answer in hand.
        shell.async { [self] in
            let alreadyGranted = clamshell.canDisableSleepWithoutPassword()
            onMain { self.engage(mayPrompt: mayPrompt, alreadyGranted: alreadyGranted) }
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
                                + "rule; not asking for one outside a deliberate start")
            return
        }
        // While a prompt is up the system still says the rule is missing, so
        // without this the person got one dialog per click for a single
        // decision. A *declined* prompt is a different state: the flag clears
        // when the prompt is answered, so the next session asks again.
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
        // tidying `/etc/sudoers.d` — and both ends of this used to discard it.
        // Claiming a lid is safe to close is the one claim in this module that
        // costs somebody a dead battery in a bag.
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
        // Every route here now arrives after its caller has emitted — the
        // grant is asked for on `shell`, and the install prompt takes minutes —
        // so «the lid is safe to close» reaches the screen from here or not at
        // all. It used to ride on `recompute`'s own emit, which is one frame
        // earlier than the answer.
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
    /// *declined* — so acting on the value put a dialog in front of somebody for
    /// every later edit of an unrelated setting. Both directions are answered
    /// here, from one reading, because both cost an administrator password and
    /// the two halves of a reconcile must not each take their own.
    ///
    /// Read before the caller's own «is a session running» guard, so an edge
    /// that happens while the module is idle is *consumed* rather than saved up
    /// for whichever unrelated edit arrives after a rule starts a session.
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
    /// page sends for every control it draws, and the battery floor is a
    /// `Slider` whose binding saves on every distinct rounded value: one drag
    /// from 20 % to 50 % is six of these. Asking on the *value* — the option is
    /// off, our file is there — made each one an administrator password dialog
    /// for a decision already answered, and a declined removal leaves precisely
    /// that state on disk for every future launch, so it was six dialogs a drag
    /// for ever. `removalInFlight` only ever covered the seconds one dialog was
    /// up. The install side reached this answer first (`consumeEdge`), and the
    /// row's own words are already «Switch this on and off again to remove it».
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

    /// The module itself is being switched off, by hand, in Settings.
    ///
    /// The same falling edge as the option's own, arrived at from one screen over:
    /// a module that is off will not use the grant either, and this is the last
    /// moment there is somebody at the screen to answer the dialog. `tearDown`
    /// cannot do it — `applicationWillTerminate` calls that on every live engine,
    /// so removing the rule there put an administrator password dialog on screen
    /// on behalf of an app that was already gone (`tearDown` has the story). What
    /// tells the two apart is `ModuleEngine.willDisable`, which only the person's
    /// own switch calls.
    ///
    /// The setting is left where it is: somebody who switches the module back on
    /// asked for the lid option once and will be asked for the password again,
    /// which is the same round trip switching the option off and on already makes.
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
            // — one from before the line existed, one written by something else
            // — reaches the dialog.
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
    /// and then counts is counting a subject still in motion: the ask happens on
    /// `shell`, not on the thread that sent the command. On an idle machine the
    /// queue wins that race and on a loaded one it does not, which is how
    /// `TheRemovalPromptIsAPromptTooTests` failed once in a full suite on
    /// 2026-08-25 and never once alone — and, worse, how its «no second dialog»
    /// assertions could pass over a second dialog that simply had not happened
    /// yet. `shell` is serial, so a block enqueued after the work runs after it:
    /// an ordering fact, not a sleep, the same shape as the file's `drainMain`.
    func drainForTests() async {
        await withCheckedContinuation { done in shell.async { done.resume() } }
    }

    /// The one place a removal's answer is read, whichever route made it.
    private func finishedRemoving(_ removed: Bool) {
        // **Which rule survived decides who is being talked about.** Both
        // branches were one line accusing a third party, and one of the two
        // cases it fired in is the case where Helm wrote the rule itself: a
        // declined dialog leaves *our* file exactly where it was, and the
        // report «a rule survives that Helm did not write» then sent whoever
        // read the log looking for a second one.
        //
        // Read here rather than after a hop: these touch no state of ours,
        // and a hop would put the check after the caller returns — which is
        // how a synchronous fake releases a gate before the thing it gates
        // has happened, and how a test of it passes for free.
        let ours = !removed && clamshell.isSudoersInstalled()
        if ours {
            HelmLog.shared.warn(KeepAwakeEngine.moduleID,
                                "the passwordless pmset rule Helm wrote was not removed")
        } else if clamshell.canDisableSleepWithoutPassword() {
            // The file is gone and the grant is not. Measured on a real
            // machine: `/etc/sudoers.d` held the identical rule under another
            // name, so «removed» was reported while any process running as
            // this user still had passwordless `pmset disablesleep`. A
            // revocation that revokes nothing is worse than none, because it
            // is reported as done.
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
