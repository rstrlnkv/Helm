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

    /// Switching the module off takes the rule with it. It used to survive
    /// that, and quitting, and deleting the app — which is what the two
    /// abandoned NOPASSWD files on this machine are.
    func testSwitchingTheModuleOffTakesTheRuleWithIt() {
        clamshell.sudoersInstalled = true
        clamshell.passwordlessGrantExists = true

        engine.deactivate()

        XCTAssertEqual(clamshell.removeCalls, 1,
                       "the module is off and a permanent passwordless sudo rule for it is not")
    }

    private func survivorLines() -> Int {
        HelmLog.shared.recentEntries()
            .filter { $0.category == "keepawake" && $0.message.contains("survives") }
            .count
    }
}
