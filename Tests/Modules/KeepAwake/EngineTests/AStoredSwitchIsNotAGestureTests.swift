import XCTest
import HelmTestSupport
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// Backlog M115. A stored «lid closed» option with no passwordless rule is a
/// value, not a gesture — and the administrator dialog may come only from the
/// person's own gesture on the lid switch (`consumeEdge`: edge, not value).
/// A plain Start press is a gesture on a different control.
final class AStoredSwitchIsNotAGestureTests: XCTestCase {
    private var store: NamespacedStore!
    private var clamshell: FakeClamshell!
    private var engine: KeepAwakeEngine!
    private var lidInfo: FakeLidInfo!
    private var apps: FakeApps!
    private var displayInfo: FakeDisplayInfo!

    override func setUp() {
        super.setUp()
        store = NamespacedStore(namespace: "keep-awake", backing: InMemoryKeyValueStore())
        KeepAwakeSettings(store: store).setClamshellEnabled(true)
        clamshell = FakeClamshell()
        clamshell.sudoersInstalled = false
        clamshell.passwordlessGrantExists = false
        lidInfo = FakeLidInfo()
        lidInfo.lid = true
        apps = FakeApps()
        displayInfo = FakeDisplayInfo()
        engine = KeepAwakeEngine(settings: KeepAwakeSettings(store: store), store: store,
                                 assertions: FakeAssertions(), displayInfo: displayInfo,
                                 displayObserver: FakeDisplayObserver(), power: FakePower(),
                                 apps: apps, pointer: FakePointer(),
                                 clamshell: clamshell, clock: FakeClock(), lidInfo: lidInfo)
    }

    /// The red one. The option was stored on (an earlier launch, a declined
    /// dialog, a migration); nobody touched the lid switch; the person pressed
    /// Start. No dialog.
    @MainActor
    func testAStartPressDoesNotAskForAPasswordBecauseTheSwitchWasStoredOn() async {
        engine.startSession(minutes: 0)

        await waitUntil("the lid asked whether it needs a password") { clamshell.grantChecks > 0 }
        await engine.drainClamshellForTests()
        XCTAssertTrue(engine.isActive, "precondition: the press started a session")
        XCTAssertEqual(clamshell.installCalls, 0,
                       "a stored value raised the administrator dialog on a Start press; "
                       + "only the lid switch's own rising edge may")
    }

    /// The control: the person's own gesture on the switch, during a running
    /// session, still asks — or the test above passes with the feature deleted.
    @MainActor
    func testTheSwitchBeingTurnedOnDuringASessionStillAsks() async {
        KeepAwakeSettings(store: store).setClamshellEnabled(false)
        engine.startSession(minutes: 0)
        engine.settingsChanged()
        await engine.drainClamshellForTests()
        XCTAssertTrue(engine.isActive, "precondition: a session is running")
        XCTAssertEqual(clamshell.installCalls, 0, "precondition: the option was off")

        engine.lidSwitchTurned(true)

        await waitUntil("the lid asked for the rule") { clamshell.installCalls == 1 }
        XCTAssertEqual(clamshell.installCalls, 1)
    }

    // MARK: - M115: a store value written from outside

    /// The red one. Another process (`defaults write`, a sync, a migration)
    /// flips the key during a running session and the settings-changed path
    /// runs. It is a value, not the person's gesture on the switch: no dialog.
    @MainActor
    func testAnOutsideWriteToTheLidKeyDoesNotAskForAPassword() async {
        KeepAwakeSettings(store: store).setClamshellEnabled(false)
        engine.startSession(minutes: 0)
        engine.settingsChanged()
        await engine.drainClamshellForTests()
        XCTAssertTrue(engine.isActive, "precondition: a session is running")
        XCTAssertEqual(clamshell.installCalls, 0, "precondition: the option was off")

        let asked = clamshell.grantChecks
        store.set(true, for: KeepAwakeSettings.Key.clamshellEnabled)
        engine.settingsChanged()

        await waitUntil("the lid asked whether it needs a password") { clamshell.grantChecks > asked }
        await engine.drainClamshellForTests()
        XCTAssertEqual(clamshell.installCalls, 0,
                       "a value written from outside raised the administrator dialog")
    }

    // MARK: - M123: a Mac with no lid

    /// A stored «lid closed» option from a laptop week, a plist, a sync, on a
    /// Mac with no lid: a settings edit during a session must not engage it.
    @MainActor
    func testAStoredLidOptionOnAMacWithNoLidEngagesNothing() async {
        lidInfo.lid = false
        engine.startSession(minutes: 0)
        XCTAssertTrue(engine.isActive, "precondition: the session is running")

        engine.settingsChanged()
        engine.settingsChanged()
        await engine.drainClamshellForTests()

        XCTAssertEqual(clamshell.installCalls, 0, "a lid rule was asked for on a Mac with no lid")
        XCTAssertFalse(clamshell.disableSleepCalls.contains(true),
                       "pmset disablesleep was run on a Mac with no lid")
        XCTAssertFalse(engine.clamshellActive)
    }

    /// Same, with the passwordless grant present: nothing to ask, still nothing
    /// to engage.
    @MainActor
    func testAStoredLidOptionOnAMacWithNoLidEngagesNothingEvenWithAGrant() async {
        clamshell.passwordlessGrantExists = true
        clamshell.sudoersInstalled = true
        lidInfo.lid = false
        engine.startSession(minutes: 0)
        XCTAssertTrue(engine.isActive, "precondition: the session is running")

        engine.settingsChanged()
        await engine.drainClamshellForTests()

        XCTAssertFalse(clamshell.disableSleepCalls.contains(true),
                       "pmset disablesleep was run on a Mac with no lid")
        XCTAssertFalse(engine.clamshellActive)
    }

    /// The control: the same with a lid and a grant does engage, or the two
    /// above pass with the lid rule deleted.
    @MainActor
    func testTheSameWithALidAndAGrantEngages() async {
        clamshell.passwordlessGrantExists = true
        clamshell.sudoersInstalled = true
        lidInfo.lid = true
        engine.startSession(minutes: 0)
        engine.settingsChanged()

        await waitUntil("the lid disabled sleep") { engine.clamshellActive }
        XCTAssertTrue(clamshell.disableSleepCalls.contains(true))
    }

    /// The per-app «only with an external display» condition on a Mac with no
    /// lid. With no built-in display, `[false]` — one display, not built-in — is
    /// the only display there is, so «external» must not be read as true.
    @MainActor
    func testAnExternalDisplayRuleDoesNotFireOnAMacWithNoLid() async {
        let app = "com.example.render"
        lidInfo.lid = false
        displayInfo.flags = [false]
        apps.ids = [app]
        KeepAwakeSettings(store: store).setAppTriggers([AppTrigger(bundleID: app, needsExternalDisplay: true)])

        engine.activate()
        engine.settingsChanged()

        XCTAssertFalse(engine.isActive,
                       "a display rule fired on a Mac with no lid, where every display is "
                       + "«external» by the raw reading")
    }

    /// The control: with a lid, an external display and the app, the rule holds.
    @MainActor
    func testAnExternalDisplayRuleFiresOnAMacWithALid() async {
        let app = "com.example.render"
        lidInfo.lid = true
        displayInfo.flags = [true, false]
        apps.ids = [app]
        KeepAwakeSettings(store: store).setAppTriggers([AppTrigger(bundleID: app, needsExternalDisplay: true)])

        engine.activate()
        engine.settingsChanged()

        XCTAssertTrue(engine.isActive)
    }

    // MARK: - Owner decision C: the global «external display» condition goes by «has a lid»

    /// The global rule switched on, an external display reported, a Mac with no
    /// lid: the rule does not fire and nothing holds the Mac.
    @MainActor
    func testTheGlobalExternalDisplayRuleDoesNotFireOnAMacWithNoLid() async {
        lidInfo.lid = false
        displayInfo.flags = [true, false]
        KeepAwakeSettings(store: store).setAutoExternalDisplay(true)

        engine.activate()
        engine.settingsChanged()

        XCTAssertFalse(engine.isActive,
                       "the global external-display rule held a Mac with no lid")
    }

    /// The control: the same with a lid holds, or the test above passes with
    /// the rule deleted.
    @MainActor
    func testTheGlobalExternalDisplayRuleFiresOnAMacWithALid() async {
        lidInfo.lid = true
        displayInfo.flags = [true, false]
        KeepAwakeSettings(store: store).setAutoExternalDisplay(true)

        engine.activate()
        engine.settingsChanged()

        XCTAssertTrue(engine.isActive, "the global external-display rule did not hold a Mac with a lid")
    }
}
