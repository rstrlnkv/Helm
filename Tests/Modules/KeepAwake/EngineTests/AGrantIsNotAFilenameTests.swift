import XCTest
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// «Is the rule installed» was asked of `/etc/sudoers.d/helm-keepawake` — a
/// filename — when the thing that matters is whether `sudo -n pmset
/// disablesleep` runs without a password.
///
/// The difference is not theoretical. On the machine this was written on,
/// `/etc/sudoers.d` held a `vorssaint-clamshell` from a predecessor whose
/// contents are this app's rule character for character, under another name.
/// `sudo -n -l` listed the grant; the file check said no. So Helm asked for an
/// administrator password to install what was already there — and after a
/// removal it reported the grant taken back while every process running as
/// this user still had it.
final class AGrantIsNotAFilenameTests: XCTestCase {
    private var store: NamespacedStore!
    private var clamshell: FakeClamshell!
    private var engine: KeepAwakeEngine!

    override func setUp() {
        super.setUp()
        store = NamespacedStore(namespace: "keep-awake", backing: InMemoryKeyValueStore())
        clamshell = FakeClamshell()
        KeepAwakeSettings(store: store).setClamshellEnabled(true)
        engine = KeepAwakeEngine(settings: KeepAwakeSettings(store: store), store: store,
                                 assertions: FakeAssertions(), displayInfo: FakeDisplayInfo(),
                                 displayObserver: FakeDisplayObserver(), power: FakePower(),
                                 apps: FakeApps(), pointer: FakePointer(),
                                 clamshell: clamshell, clock: FakeClock())
    }

    /// The control: with no grant of any kind, the first session asks.
    func testWithNoGrantAtAllTheFirstSessionAsksForOne() {
        clamshell.sudoersInstalled = false
        clamshell.passwordlessGrantExists = false

        engine.startSession(minutes: 0)

        XCTAssertEqual(clamshell.installCalls, 1, "precondition: this is the path that prompts")
    }

    /// Somebody else's file, granting exactly this. Nothing to install, and no
    /// reason to put an administrator dialog in front of anybody.
    func testAGrantSomebodyElseWroteIsNotAskedForAgain() {
        clamshell.sudoersInstalled = false
        clamshell.passwordlessGrantExists = true

        engine.startSession(minutes: 0)

        XCTAssertEqual(clamshell.installCalls, 0,
                       "a password was requested to install a rule that already grants this")
        XCTAssertTrue(engine.clamshellActive, "and the feature works, because the grant is there")
    }

    /// The expensive half. Our file goes; the capability stays; the module used
    /// to report the whole thing done.
    func testARemovalThatLeavesTheGrantBehindIsSaidOutLoud() {
        HelmLog.shared.setEnabled(true)
        defer { HelmLog.shared.setEnabled(false); HelmLog.shared.clearTail() }
        HelmLog.shared.clearTail()

        clamshell.sudoersInstalled = true
        clamshell.passwordlessGrantExists = true
        KeepAwakeSettings(store: store).setClamshellEnabled(false)

        engine.settingsChangedForTests()

        XCTAssertEqual(clamshell.removeCalls, 1, "precondition: the file was removed")
        XCTAssertTrue(survivorLines() > 0,
                      "the file went and the grant did not, and nothing said so — the module "
                      + "reported a revocation that revoked nothing")
    }

    /// And when the grant really does go with the file, there is nothing to
    /// warn about — otherwise the line above is wallpaper.
    func testAnOrdinaryRemovalSaysNothing() {
        HelmLog.shared.setEnabled(true)
        defer { HelmLog.shared.setEnabled(false); HelmLog.shared.clearTail() }
        HelmLog.shared.clearTail()

        clamshell.sudoersInstalled = true
        clamshell.passwordlessGrantExists = false
        KeepAwakeSettings(store: store).setClamshellEnabled(false)

        engine.settingsChangedForTests()

        XCTAssertEqual(survivorLines(), 0)
    }

    /// **Quitting leaves the rule, and that is the decision.**
    ///
    /// It used to remove it here, which read well and could not work:
    /// `deactivate()` is what `applicationWillTerminate` calls on every live
    /// engine, and `removeSudoers` dispatches to a global queue and puts up an
    /// `osascript` administrator dialog — for an app that is already gone. The
    /// two abandoned NOPASSWD files on this machine are what that looks like a
    /// year later, and Helm's own removal was written the same way.
    ///
    /// The grant belongs to the *feature*, and there are two falling edges of it
    /// now: the lid option's own switch (`releaseIfUnneeded`, the two tests above)
    /// and the module's (`willDisable`, which the host calls from the person's
    /// switch and never from quitting —
    /// `ALidThatDidNotWorkSaysSoTests`). `deactivate()` is the one route out that
    /// may not ask, because it is the one nobody is watching.
    func testQuittingLeavesTheRuleToTheTwoEdgesThatMayAsk() {
        clamshell.sudoersInstalled = true
        clamshell.passwordlessGrantExists = true

        engine.deactivate()

        XCTAssertEqual(clamshell.removeCalls, 0,
                       "a password dialog was raised on the way out of the process that raised it")
        XCTAssertTrue(clamshell.isSudoersInstalled())
    }

    private func survivorLines() -> Int {
        HelmLog.shared.recentEntries()
            .filter { $0.category == KeepAwakeEngine.moduleID && $0.message.contains("survives") }
            .count
    }
}
