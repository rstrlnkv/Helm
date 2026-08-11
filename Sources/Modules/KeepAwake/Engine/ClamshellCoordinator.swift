import Foundation
import HelmRuntime

/// «Stay awake with the lid closed», and everything it costs.
///
/// **The one thing this module does that outlives its own process.** It is
/// `sudo pmset disablesleep 1` — a system-wide setting, above every IOKit
/// assertion, still in force after Helm quits — reached through a NOPASSWD
/// rule in `/etc/sudoers.d`. Six methods and four flags, and no other part of
/// the engine reads any of them: the session logic asks for the lid and is told
/// whether it got it.
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

    /// Is a session running *now* — asked at the moment of use, never captured
    /// as a value. Set by the engine after construction rather than passed in,
    /// because both of these close over the engine and the engine owns this.
    var sessionIsActive: () -> Bool = { false }
    var stateChanged: () -> Void = {}

    /// Sleep really is disabled system-wide, as far as `pmset` was willing to
    /// say. The panel draws «Lid closed — staying awake» from this, so it is
    /// false whenever the call refused.
    private(set) var active = false

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
    /// off; it survives a crash, which is the case it exists for. Only shell
    /// out when the flag is set — Swift evaluates both arguments of `&&`, so
    /// the flag has to short-circuit the `pmset` read.
    func recoverAtLaunch() {
        guard store.bool(KeepAwakeSettings.Key.clamshellGuard, default: false),
              ClamshellRecovery.sleepDisabled(inPmsetOutput: clamshell.pmsetReport())
        else { return }
        restoreSleep(refused: "closed-lid sleep could not be restored at launch",
                     restored: "closed-lid sleep restored at launch")
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
    private func restoreSleep(refused: String, restored: String) {
        guard clamshell.setDisableSleep(false) else {
            HelmLog.shared.warn("keepawake", refused)
            return
        }
        store.set(false, for: KeepAwakeSettings.Key.clamshellGuard)
        active = false
        HelmLog.shared.info("keepawake", restored)
    }

    /// The module is being switched off. Sleep goes back and the grant goes
    /// with it — unconditionally, whatever the stored setting says, because a
    /// permanent NOPASSWD line for a module that is off is a grant nobody is
    /// holding. `/etc/sudoers.d` on the machine this was written on holds two
    /// abandoned rules from predecessors; that is what «the rule survives the
    /// app» looks like a year later.
    func tearDown() {
        if active { disengage() }
        guard clamshell.isSudoersInstalled() else { return }
        clamshell.removeSudoers { _ in }
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
        guard !clamshell.canDisableSleepWithoutPassword() else {
            reallyEngage()
            return
        }
        // Nobody is expecting a password dialog, so there will not be one. The
        // session goes ahead: an IOKit assertion holds an open Mac awake
        // perfectly well, and the lid is the only part that needs the rule.
        guard mayPrompt else {
            HelmLog.shared.info("keepawake", "closed-lid sleep needs an administrator "
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
        releaseIfUnneeded()
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
            HelmLog.shared.warn("keepawake", "closed-lid sleep could not be disabled")
            active = false
            stateChanged()
            return
        }
        active = true
        // A change to the system's own sleep setting, made through sudo and
        // outliving the process — the one thing here a crash can leave behind.
        // Both ends of it belong in the trail.
        HelmLog.shared.info("keepawake", "closed-lid sleep disabled")
    }

    func disengage() {
        restoreSleep(refused: "closed-lid sleep could not be restored",
                     restored: "closed-lid sleep restored")
    }

    // MARK: - Settings

    /// Reconcile against the current setting, and answer whether this was the
    /// switch's **rising edge**.
    ///
    /// The edge, not the value: `settingsChanged` arrives for every control the
    /// page draws, and `clamshellEnabled` stays true after a password dialog is
    /// *declined* — so acting on the value put a dialog in front of somebody for
    /// every later edit of an unrelated setting.
    ///
    /// Read before the caller's own «is a session running» guard, so an edge
    /// that happens while the module is idle is *consumed* rather than saved up
    /// for whichever unrelated edit arrives after a rule starts a session.
    func consumeRisingEdge() -> Bool {
        let switchedOn = settings.clamshellEnabled && !lastSetting
        lastSetting = settings.clamshellEnabled
        return switchedOn
    }

    /// Switching the option off takes the passwordless rule back out. The rule
    /// is the price of the feature, not of having installed Helm.
    ///
    /// Silent on failure — the person declined the password prompt, which is an
    /// answer, and the rule stays until they say otherwise.
    func releaseIfUnneeded() {
        guard !settings.clamshellEnabled, clamshell.isSudoersInstalled() else { return }
        guard !removalInFlight else { return }
        removalInFlight = true
        clamshell.removeSudoers { [weak self] _ in
            guard let self else { return }
            // The file is gone and the grant may not be. Measured on a real
            // machine: `/etc/sudoers.d` held the identical rule under another
            // name, so «removed» was reported while any process running as this
            // user still had passwordless `pmset disablesleep`. A revocation
            // that revokes nothing is worse than none, because it is reported as
            // done.
            //
            // Read here rather than after a hop: this touches no state of ours,
            // and a hop would put the check after the caller returns — which is
            // how a synchronous fake releases a gate before the thing it gates
            // has happened, and how a test of it passes for free.
            if self.clamshell.canDisableSleepWithoutPassword() {
                HelmLog.shared.warn("keepawake",
                                    "a passwordless pmset rule survives that Helm did not write")
            }
            // Our own flag does hop: cleared whatever the answer was, because a
            // declined removal has to be askable again, and a flag left standing
            // would mean the rule could never come off for the life of the
            // process.
            Task { @MainActor in self.removalInFlight = false }
        }
    }
}
