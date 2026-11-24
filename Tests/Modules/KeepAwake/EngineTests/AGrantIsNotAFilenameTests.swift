import XCTest
import HelmTestSupport
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// «Is the rule installed» was asked of `/etc/sudoers.d/helm-keepawake` — a
/// filename — when the thing that matters is whether `sudo -n pmset
/// disablesleep` runs without a password.
///
/// A rule with this app's contents can sit under another name, from another
/// tool. A file check would then ask for an administrator password to install
/// what is already there, and after a removal report the grant taken back while
/// every process running as this user still has it.
final class AGrantIsNotAFilenameTests: XCTestCase {
    private var store: NamespacedStore!
    private var clamshell: FakeClamshell!
    private var engine: KeepAwakeEngine!

    override func setUp() {
        super.setUp()
        store = NamespacedStore(namespace: "keep-awake", backing: InMemoryKeyValueStore())
        clamshell = FakeClamshell()
        KeepAwakeSettings(store: store).setClamshellEnabled(true)
        engine = fakeEngine(store: store, clamshell: clamshell)
    }

    /// The control: with no grant of any kind, the person's gesture on the lid
    /// switch asks for one (a Start press never does).
    @MainActor
    func testWithNoGrantAtAllTheLidSwitchGestureAsksForOne() async {
        clamshell.sudoersInstalled = false
        clamshell.passwordlessGrantExists = false
        KeepAwakeSettings(store: store).setClamshellEnabled(false)

        engine.activate()
        engine.startSession(minutes: 0)
        engine.settingsChanged() // the option is seen off before the switch is turned
        engine.lidSwitchTurned(true)

        // The grant question is `sudo -n`, asked off the drawing thread.
        await waitUntil("the lid asked for the rule") { clamshell.installCalls == 1 }
        XCTAssertEqual(clamshell.installCalls, 1, "precondition: this is the path that prompts")
    }

    /// Somebody else's file, granting exactly this. Nothing to install, and no
    /// reason to put an administrator dialog in front of anybody.
    @MainActor
    func testAGrantSomebodyElseWroteIsNotAskedForAgain() async {
        clamshell.sudoersInstalled = false
        clamshell.passwordlessGrantExists = true

        engine.startSession(minutes: 0)

        await waitUntil("the lid disabled sleep") { engine.clamshellActive }
        XCTAssertEqual(clamshell.installCalls, 0,
                       "a password was requested to install a rule that already grants this")
        XCTAssertTrue(engine.clamshellActive, "and the feature works, because the grant is there")
    }

    /// The expensive half. Our file goes; the capability stays; the module must
    /// not report the whole thing done.
    @MainActor
    func testARemovalThatLeavesTheGrantBehindIsSaidOutLoud() async {
        tailTheLog()

        clamshell.sudoersInstalled = true
        clamshell.passwordlessGrantExists = true
        KeepAwakeSettings(store: store).setClamshellEnabled(false)

        engine.settingsChanged()

        // The withdrawal runs on the module's own queue, because a child
        // process must not run on the thread that draws.
        await waitUntil("the file went") { !self.clamshell.isSudoersInstalled() }
        await waitUntil("the log was written") { self.survivorLines() > 0 }
        XCTAssertTrue(survivorLines() > 0,
                      "the file went and the grant did not, and nothing said so — the module "
                      + "reported a revocation that revoked nothing")
    }

    /// And when the grant really does go with the file, there is nothing to
    /// warn about — otherwise the line above is wallpaper.
    @MainActor
    func testAnOrdinaryRemovalSaysNothing() async {
        tailTheLog()

        clamshell.sudoersInstalled = true
        clamshell.passwordlessGrantExists = false
        KeepAwakeSettings(store: store).setClamshellEnabled(false)

        engine.settingsChanged()

        // Asserted after the removal really happened: an absence read before the
        // subject has run is green on any code whatever.
        await waitUntil("the file went") { !self.clamshell.isSudoersInstalled() }
        XCTAssertEqual(survivorLines(), 0)
    }

    /// Quitting leaves the rule, and that is the decision.
    ///
    /// `deactivate()` is what `applicationWillTerminate` calls on every live
    /// engine, and a removal there would put up an `osascript` administrator
    /// dialog for an app that is already gone.
    ///
    /// The grant belongs to the feature, and there are two falling edges of it:
    /// the lid option's own switch (`releaseIfUnneeded`, the two tests above)
    /// and the module's (`willDisable`, which the host calls from the person's
    /// switch and never from quitting —
    /// `ALidThatDidNotWorkSaysSoTests`). `deactivate()` is the one route out that
    /// may not ask, because it is the one nobody is watching.
    func testQuittingNeverRaisesADialogAndTakesBackWhatItCanForFree() {
        clamshell.sudoersInstalled = true
        clamshell.passwordlessGrantExists = true

        engine.deactivate()

        XCTAssertEqual(clamshell.removeCalls, 0,
                       "a password dialog was raised on the way out of the process that raised it")
        XCTAssertFalse(clamshell.isSudoersInstalled(),
                       "the lid option is off and sleep is back, so the grant had nothing left to "
                       + "do — and the app about to stop existing is the last chance to say so")
    }

    /// The half that has to stay: a rule that cannot withdraw itself is left
    /// rather than answered with a dialog nobody is there for.
    func testQuittingLeavesARuleItCannotTakeOutForFree() {
        clamshell.sudoersInstalled = true
        clamshell.passwordlessGrantExists = true
        clamshell.withdrawalIsGranted = false

        engine.deactivate()

        XCTAssertEqual(clamshell.removeCalls, 0)
        XCTAssertTrue(clamshell.isSudoersInstalled())
    }

    private func survivorLines() -> Int {
        HelmLog.shared.recentEntries()
            .filter { $0.category == KeepAwakeEngine.moduleID && $0.message.contains("survives") }
            .count
    }
}
