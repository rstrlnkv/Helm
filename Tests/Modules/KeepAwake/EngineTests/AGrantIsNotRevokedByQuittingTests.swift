import XCTest
import HelmTestSupport
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// Taking the NOPASSWD rule back out at quit was a promise the process could not
/// keep, and it cost the one thing that could have kept it.
///
/// `tearDown()` ran `clamshell.removeSudoers { _ in }` — which hops to a global
/// queue and runs `osascript … with administrator privileges`. It is called from
/// `deactivate()`, and `applicationWillTerminate` calls that on every live
/// engine, so the sequence at quit was: dispatch to a background queue, put an
/// administrator password dialog on screen, and terminate. Nobody types a
/// password into a dialog belonging to an app that is already gone. The evidence
/// that it never ran is on the machine this was written on: `/etc/sudoers.d`
/// holds **two** abandoned rules from predecessors, and this app's own removal
/// was written the same way.
///
/// Worse, it ran *after* `if active { disengage() }` with nothing between them.
/// A refused restore leaves system sleep off machine-wide and keeps
/// `clamshellGuard` set precisely so the next launch comes back and looks — and
/// the recovery it comes back for needs `sudo -n pmset disablesleep 0`, which is
/// the grant this was removing on the way out. So the one path where the rule is
/// load-bearing is the one where it was being taken away.
///
/// The decision: **the grant's lifetime is the feature, not the process.**
/// `releaseIfUnneeded()` removes it on the lid option's falling edge and
/// `releaseOnModuleDisabled()` on the module's, both where there is a person
/// present to answer the dialog. Quitting leaves it, the same way a crash does —
/// and `ModuleEngine.willDisable` is what lets the host tell «somebody switched
/// this off» from «the process is ending», which `deactivate()` alone could not.
final class AGrantIsNotRevokedByQuittingTests: XCTestCase {
    private var backing: InMemoryKeyValueStore!
    private var store: NamespacedStore!
    private var settings: KeepAwakeSettings!
    private var clamshell: FakeClamshell!
    private var engine: KeepAwakeEngine!

    override func setUp() {
        super.setUp()
        backing = InMemoryKeyValueStore()
        store = NamespacedStore(namespace: "keep-awake", backing: backing)
        settings = KeepAwakeSettings(store: store)
        clamshell = FakeClamshell()
        clamshell.sudoersInstalled = true
        clamshell.passwordlessGrantExists = true
        settings.setClamshellEnabled(true)
        engine = KeepAwakeEngine(settings: settings, store: store,
                                 assertions: FakeAssertions(), displayInfo: FakeDisplayInfo(),
                                 displayObserver: FakeDisplayObserver(), power: FakePower(),
                                 apps: FakeApps(), pointer: FakePointer(),
                                 clamshell: clamshell, clock: FakeClock())
    }

    private var guardFlag: Bool {
        store.bool(KeepAwakeSettings.Key.clamshellGuard, default: false)
    }

    // MARK: - What quitting may do

    /// `applicationWillTerminate` reaches exactly this.
    @MainActor
    func testQuittingPutsSleepBackAndLeavesTheGrantAlone() async {
        engine.startSession(minutes: 0)
        await waitUntil("the lid disabled sleep") { engine.clamshellActive }
        XCTAssertTrue(engine.clamshellActive, "precondition: sleep is off and the lid is safe")

        engine.deactivate()

        XCTAssertTrue(clamshell.disableSleepCalls.contains(false),
                      "quitting has to put system sleep back — that part outlives the process")
        XCTAssertEqual(clamshell.removeCalls, 0,
                       "a terminating process asked for an administrator password and then "
                       + "exited; the rule stays, and the lid option is what takes it out")
        XCTAssertTrue(clamshell.isSudoersInstalled())
    }

    /// The expensive case, and the reason the order mattered: the restore was
    /// refused, so sleep is off machine-wide and the next launch is the only
    /// thing that can fix it — with the grant it needs still there.
    @MainActor
    func testARefusedRestoreLeavesBothHalvesOfItsOwnRecovery() async {
        engine.startSession(minutes: 0)
        await waitUntil("the lid disabled sleep") { engine.clamshellActive }
        XCTAssertTrue(guardFlag, "precondition: sleep was really disabled")

        clamshell.disableSleepSucceeds = false
        engine.deactivate()

        XCTAssertTrue(guardFlag,
                      "the note that brings the next launch back to look was erased")
        XCTAssertTrue(clamshell.isSudoersInstalled(),
                      "the restore refused, so the next launch has to run `sudo -n pmset "
                      + "disablesleep 0` — and the grant it needs was taken out on the way past")
    }

    /// And the next launch really does use them, so the two assertions above are
    /// guarding something that happens rather than a pair of stored values.
    @MainActor
    func testTheNextLaunchRestoresSleepWithTheGrantThatWasLeftThere() async {
        engine.startSession(minutes: 0)
        await waitUntil("the lid disabled sleep") { engine.clamshellActive }
        clamshell.disableSleepSucceeds = false
        // The person ended the session, the restore refused, and *then* Helm
        // quit. Ending it first is what keeps this about the recovery: a session
        // still running when `deactivate()` arrives is deliberately remembered
        // and resumed by the next launch, which engages the lid again — a second
        // `pmset` call that has nothing to do with what is being measured here.
        engine.stopSession()
        engine.deactivate()
        clamshell.pmset = "SleepDisabled 1"
        clamshell.disableSleepSucceeds = true
        clamshell.disableSleepCalls = []

        let next = atLaunch()
        next.activate()

        // The recovery is two child processes on the lid's own queue, and the
        // note is cleared last of all.
        await waitUntil("the lid put sleep back") { !guardFlag }
        XCTAssertEqual(clamshell.disableSleepCalls, [false],
                       "a launch that finds the guard set and sleep disabled puts it back")
        XCTAssertFalse(guardFlag, "…and only then is the note cleared")
    }

    // MARK: - Who does take it out

    /// The control: the grant's lifetime is the lid option, so switching *that*
    /// off still removes it. Without this, everything above is satisfied by a
    /// module that can never revoke anything.
    @MainActor
    func testTheLidOptionGoingOffStillTakesTheGrantOut() async {
        settings.setClamshellEnabled(false)

        engine.settingsChangedForTests()

        // Counted on the withdrawal, not on the dialog: the rule permits its own
        // removal, so the ordinary route asks nobody for anything.
        // `TheGrantDoesNotOutliveTheAppItNamesTests` argues both routes.
        await waitUntil("the rule came out") { !self.clamshell.isSudoersInstalled() }
        XCTAssertEqual(clamshell.passwordlessRemovals, 1,
                       "a NOPASSWD line for a feature that is off is a grant nobody is holding")
        XCTAssertEqual(clamshell.removeCalls, 0)
    }

    /// A second engine over the same store and the same lid, which is what the
    /// next launch is.
    private func atLaunch() -> KeepAwakeEngine {
        KeepAwakeEngine(settings: settings, store: store,
                        assertions: FakeAssertions(), displayInfo: FakeDisplayInfo(),
                        displayObserver: FakeDisplayObserver(), power: FakePower(),
                        apps: FakeApps(), pointer: FakePointer(),
                        clamshell: clamshell, clock: FakeClock())
    }
}
