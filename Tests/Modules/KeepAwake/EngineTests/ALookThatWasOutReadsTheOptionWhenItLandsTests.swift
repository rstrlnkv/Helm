import XCTest
import HelmTestSupport
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// The lid row's «a rule is still installed» verdict is made from two facts —
/// the file, looked for off the main thread, and the option, which the person
/// can flip while the look is out. The option is read in the block that lands
/// on main, so the verdict follows the value current *then*; read before the
/// hop, a rule the person has just started using would be reported as
/// forgotten.
///
/// Past defect guarded: `lookForTheRule` taking `settings.clamshellEnabled`
/// before the hop to `main`.
final class ALookThatWasOutReadsTheOptionWhenItLandsTests: XCTestCase {

    @MainActor
    func testTheOptionSwitchedOnWhileTheLookIsOutSilencesTheGrantNotice() async {
        let store = NamespacedStore(namespace: "keep-awake", backing: InMemoryKeyValueStore())
        let settings = KeepAwakeSettings(store: store)
        let clamshell = FakeClamshell()
        clamshell.sudoersInstalled = true
        clamshell.passwordlessGrantExists = true
        settings.setClamshellEnabled(false)
        let engine = KeepAwakeEngine(settings: settings, store: store,
                                     assertions: FakeAssertions(), displayInfo: FakeDisplayInfo(),
                                     displayObserver: FakeDisplayObserver(), power: FakePower(),
                                     apps: FakeApps(), pointer: FakePointer(),
                                     clamshell: clamshell, clock: FakeClock(), lidInfo: FakeLidInfo())
        let release = DispatchSemaphore(value: 0)
        let began = expectation(description: "the look read the file and is parked")
        clamshell.lookBegan = began
        clamshell.holdNextLook = release

        engine.activate() // the launch looks on `shell`
        await fulfillment(of: [began], timeout: 10)
        XCTAssertEqual(clamshell.installedChecks, 1, "precondition: the look is out, the file already read as present")

        let past = DispatchSemaphore(value: 0)
        clamshell.pmsetEntered = past
        release.signal()
        // `shell` has now read the file, and queued the verdict's hop behind
        // this blocked thread: a read of the option before the hop has already
        // happened, one in the hop block has not. Only now does the person
        // switch it on.
        XCTAssertEqual(past.wait(timeout: .now() + 10), .success, "the look went on to pmset")
        settings.setClamshellEnabled(true)
        await drainMainActor()
        XCTAssertFalse(engine.lidGrantRemains,
                       "the option was on when the look landed: the rule is the feature working")
    }
}
