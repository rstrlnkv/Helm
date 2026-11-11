import XCTest
import HelmTestSupport
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// Who is allowed to put a system administrator password dialog on screen.
///
/// «Stay awake with the lid closed» installs a NOPASSWD sudoers rule, and that
/// was reached from `recompute()` on every false→true edge of `isActive` —
/// including the edges a *rule* causes. So launching a watched app raised a
/// real macOS password prompt at a moment nobody had touched Helm, with nothing
/// on the dialog naming the app, the rule or this program. Any process running
/// as this user could pick that moment by launching the app.
///
/// The prompt now needs a gesture behind it: the lid switch's own rising edge
/// (`lidSwitchTurned`) and nothing else — a Start press is a gesture on another
/// control (owner decision 2026-11-11). Automatic paths still engage when the grant already exists,
/// because that costs no dialog — and the session itself is never held back,
/// since an IOKit assertion keeps an open Mac awake perfectly well.
final class APasswordDialogNeedsAGestureTests: XCTestCase {
    private var store: NamespacedStore!
    private var clamshell: FakeClamshell!
    private var apps: FakeApps!
    private var lidInfo: FakeLidInfo!
    private var engine: KeepAwakeEngine!

    override func setUp() {
        super.setUp()
        store = NamespacedStore(namespace: "keep-awake", backing: InMemoryKeyValueStore())
        KeepAwakeSettings(store: store).setClamshellEnabled(true)
        clamshell = FakeClamshell()
        clamshell.sudoersInstalled = false
        clamshell.passwordlessGrantExists = false
        apps = FakeApps()
        lidInfo = FakeLidInfo()
        lidInfo.lid = true
        engine = KeepAwakeEngine(settings: KeepAwakeSettings(store: store), store: store,
                                 assertions: FakeAssertions(), displayInfo: FakeDisplayInfo(),
                                 displayObserver: FakeDisplayObserver(), power: FakePower(),
                                 apps: apps, pointer: FakePointer(),
                                 clamshell: clamshell, clock: FakeClock(), lidInfo: lidInfo)
    }

    /// The prompt's answer reaches the engine through `DispatchQueue.main.async`
    /// — `osascript` calls back on a background queue, and engine state belongs
    /// on main. A synchronous test never spins the run loop, so without this the
    /// engine stays permanently "a prompt is on screen" and every later ask is
    /// suppressed by the in-flight guard rather than by the code under test.
    private func drainMain() {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }

    /// Every settings edit asks `sudo -n` again, on the lid's own queue. This is
    /// what makes «and it did *not* ask for a password» a statement about an
    /// answered question rather than about one still in the post.
    @MainActor
    private func waitForTheQuestion(after asked: Int,
                                    file: StaticString = #filePath,
                                    line: UInt = #line) async {
        await waitUntil("the lid ask whether it needs a password", file: file, line: line) {
            clamshell.grantChecks > asked
        }
    }

    /// Decision A. A Start press is not the lid switch: with the option stored
    /// on and no passwordless rule, Start holds the Mac without the lid rule and
    /// raises no dialog.
    @MainActor
    func testStartingASessionByHandDoesNotAskAndHoldsWithoutTheLidRule() async {
        engine.startSession(minutes: 0)

        await waitUntil("the lid asked whether it needs a password") { clamshell.grantChecks > 0 }
        await engine.drainClamshellForTests()
        XCTAssertTrue(engine.isActive, "precondition: the press started a session")
        XCTAssertEqual(clamshell.installCalls, 0,
                       "a Start press raised the administrator dialog")
        XCTAssertFalse(engine.clamshellActive, "without a grant the lid rule is not held")
        XCTAssertFalse(clamshell.disableSleepCalls.contains(true),
                       "pmset disablesleep was attempted without a grant")
    }

    /// The control. The lid switch's own gesture still asks — otherwise every
    /// assertion below passes with the feature deleted.
    @MainActor
    func testTheLidSwitchTurnedOnByHandStillAsksForTheRule() async {
        KeepAwakeSettings(store: store).setClamshellEnabled(false)
        engine.startSession(minutes: 0)
        engine.settingsChanged()
        await engine.drainClamshellForTests()
        XCTAssertEqual(clamshell.installCalls, 0, "precondition: nothing asked yet")

        engine.lidSwitchTurned(true)

        await waitUntil("the lid asked for the rule") { clamshell.installCalls == 1 }
        XCTAssertEqual(clamshell.installCalls, 1,
                       "the switch's own gesture is the one place a password dialog belongs")
    }

    /// The expensive one. A rule fires, the Mac is held awake, and no dialog.
    @MainActor
    func testARuleFiringDoesNotRaiseAPasswordDialog() async {
        store.set(true, for: KeepAwakeSettings.Key.autoPower)
        let power = FakePower()
        power.says(.mains)
        let ruled = KeepAwakeEngine(settings: KeepAwakeSettings(store: store), store: store,
                                    assertions: FakeAssertions(), displayInfo: FakeDisplayInfo(),
                                    displayObserver: FakeDisplayObserver(), power: power,
                                    apps: apps, pointer: FakePointer(),
                                    clamshell: clamshell, clock: FakeClock(), lidInfo: lidInfo)

        let asked = clamshell.grantChecks
        ruled.activate()

        await waitForTheQuestion(after: asked)
        XCTAssertTrue(ruled.isActive,
                      "precondition: the rule really did start a session — a test that a "
                      + "dialog did not appear passes trivially if nothing happened")
        XCTAssertEqual(clamshell.installCalls, 0,
                       "an app launching put a system password dialog on screen, at a moment "
                       + "chosen by whatever launched it")
    }

    /// And the feature is not quietly broken for the automatic path: where the
    /// grant is already there, the lid still works with no dialog to raise.
    @MainActor
    func testAnAutomaticSessionStillDisablesLidSleepWhenTheGrantExists() async {
        clamshell.passwordlessGrantExists = true
        store.set(true, for: KeepAwakeSettings.Key.autoPower)
        let power = FakePower()
        power.says(.mains)
        let ruled = KeepAwakeEngine(settings: KeepAwakeSettings(store: store), store: store,
                                    assertions: FakeAssertions(), displayInfo: FakeDisplayInfo(),
                                    displayObserver: FakeDisplayObserver(), power: power,
                                    apps: apps, pointer: FakePointer(),
                                    clamshell: clamshell, clock: FakeClock(), lidInfo: lidInfo)

        ruled.activate()

        await waitUntil("the lid disabled sleep") { ruled.clamshellActive }
        XCTAssertEqual(clamshell.installCalls, 0)
        XCTAssertTrue(ruled.clamshellActive,
                      "nothing had to be asked, so nothing should have been withheld")
    }

    /// The other door into the prompt. `settingsChanged` arrives for every
    /// control the page draws, and `clamshellEnabled` stays true after a dialog
    /// is *declined* — so asking on the value meant a password dialog for every
    /// later edit of an unrelated setting.
    @MainActor
    func testEditingAnUnrelatedSettingDoesNotAskAgain() async {
        engine.startSession(minutes: 0)
        engine.lidSwitchTurned(false)
        engine.lidSwitchTurned(true)
        await waitUntil("the lid asked for the rule") { clamshell.installCalls == 1 }
        XCTAssertEqual(clamshell.installCalls, 1, "precondition: the first ask happened")
        // Declined: the file is still absent and the setting is still on.
        clamshell.finishInstall(granted: false)
        drainMain()

        for _ in 0..<3 {
            let asked = clamshell.grantChecks
            engine.settingsChanged()
            await waitForTheQuestion(after: asked)
        }

        XCTAssertEqual(clamshell.installCalls, 1,
                       "three unrelated edits produced three administrator dialogs")
    }

    /// …and switching the setting off and on again is a fresh decision, so it
    /// does ask. Without this the guard above would be «never ask twice».
    @MainActor
    func testTurningTheSettingOffAndOnAsksAgain() async {
        engine.startSession(minutes: 0)
        engine.lidSwitchTurned(false)
        engine.lidSwitchTurned(true)
        await waitUntil("the lid asked for the rule") { clamshell.installCalls == 1 }
        clamshell.finishInstall(granted: false)
        drainMain()

        engine.lidSwitchTurned(false)
        engine.lidSwitchTurned(true)

        await waitUntil("the lid asked for the rule a second time") { clamshell.installCalls == 2 }
        XCTAssertEqual(clamshell.installCalls, 2,
                       "somebody switched it on again and nothing happened")
    }
}
