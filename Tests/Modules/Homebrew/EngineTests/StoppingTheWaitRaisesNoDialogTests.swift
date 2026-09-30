import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Homebrew_Engine

/// Ending the wait for Apple's tools by any road — Stop, a module switched off,
/// an engine that is going — releases the tick, and a tick that lands anyway
/// finds nothing to act on. The road it must never lead to is a password dialog:
/// from a page the person stopped, from a module that is off, or on behalf of an
/// operation that is over.
final class StoppingTheWaitRaisesNoDialogTests: XCTestCase {

    /// «Stop waiting» is the existing `.stop`: no new command on the wire. The
    /// operation ends as stopped, the tick is released, and a tick that was
    /// already in flight does not go on to the dialog.
    func testStopWaitingEndsTheOperationAndNoTickRaisesTheDialog() async {
        let rig = WaitRig()
        rig.engine.installBrew()
        XCTAssertEqual(rig.ticker.live, 1, "precondition: the wait is armed")

        rig.engine.stop()

        let (state, _) = await rig.replayed()
        XCTAssertEqual(state?.phase, .failed)
        XCTAssertEqual(state?.reason, .stopped)
        XCTAssertNil(state?.waiting)
        XCTAssertEqual(rig.ticker.live, 0, "Stop left a tick armed")

        rig.tools.gitExecutable = true          // Apple's window finishes anyway
        rig.ticker.fireInFlight(0)              // the tick that was already on its way
        XCTAssertTrue(rig.privileged.scripts.isEmpty,
                      "the password dialog rose after the person stopped waiting")
        XCTAssertTrue(rig.runner.calls.isEmpty)

        rig.engine.installBrew()
        XCTAssertEqual(rig.privileged.scripts.count, 1,
                       "the stopped operation left the gate shut, or the next press was not admitted")
    }

    /// A tick from an old wait, in flight when the person stopped and pressed
    /// again, must not act for the new one: the token in the field is the *new*
    /// wait's, and only the generation says the tick is not its own.
    func testATickFromAnEarlierWaitCannotActForTheNextOne() {
        let rig = WaitRig()
        rig.engine.installBrew()
        rig.engine.stop()
        rig.engine.installBrew()
        XCTAssertEqual(rig.ticker.live, 1, "precondition: a second wait is armed")
        rig.tools.gitExecutable = true

        rig.ticker.fireInFlight(0)

        XCTAssertTrue(rig.privileged.scripts.isEmpty,
                      "a tick of the stopped wait ended the new one and raised its dialog")
        XCTAssertEqual(rig.ticker.live, 1, "the old tick disarmed the new wait")
    }

    /// A module switched off in the middle of the wait: the same ending, the
    /// gate opens, and no tick is left to raise a dialog from a module that is off.
    func testSwitchingTheModuleOffMidWaitEndsItAndOpensTheGate() async {
        let rig = WaitRig()
        rig.engine.installBrew()

        rig.engine.deactivate()

        let (state, _) = await rig.replayed()
        XCTAssertEqual(state?.phase, .failed)
        XCTAssertEqual(state?.reason, .stopped)
        XCTAssertEqual(rig.ticker.live, 0, "a tick outlived the module's deactivation")
        rig.tools.gitExecutable = true
        rig.ticker.fireInFlight(0)
        XCTAssertTrue(rig.privileged.scripts.isEmpty,
                      "a module that is switched off raised the administrator dialog")

        rig.engine.installBrew()
        XCTAssertEqual(rig.privileged.scripts.count, 1, "deactivation left the gate shut")
    }

    /// The backstop for the routes that never call `deactivate()`: an engine
    /// that is dropped releases its tick, and a tick that lands afterwards
    /// finds no engine.
    func testDroppingTheEngineMidWaitReleasesTheTick() {
        let tools = FakeCommandLineTools()
        let ticker = FakeWaitTicker()
        let privileged = ScriptedPrivileged(reply: .done)
        weak var weakEngine: HomebrewEngine?
        autoreleasepool {
            let engine = HomebrewEngine(locator: WaitRig.FixedLocator(), runner: RecordingStreamRunner(),
                                        privileged: privileged, user: "tester",
                                        transport: LocalTransport(), marker: InMemoryOpMarker(),
                                        tools: tools, ticker: ticker)
            engine.installBrew()
            weakEngine = engine
            XCTAssertEqual(ticker.live, 1, "precondition: the wait is armed")
        }

        XCTAssertNil(weakEngine, "the wait keeps the engine alive: the token's block holds it strongly")
        XCTAssertEqual(ticker.live, 0, "the engine went and its tick is still armed")
        tools.gitExecutable = true
        ticker.fireInFlight(0)
        XCTAssertTrue(privileged.scripts.isEmpty, "a tick reached a dialog through an engine that was gone")
    }

    /// A Stop that lands while the request is still being filed — before the
    /// wait exists, so there is no token to take. It leaves the flag, and the
    /// press reads it: no wait is armed, and the operation ends as stopped.
    func testAStopWhileTheRequestIsBeingFiledArmsNoWait() async {
        let rig = WaitRig()
        rig.tools.onRequest = { [engine = rig.engine] in engine.stop() }

        rig.engine.installBrew()

        let (state, _) = await rig.replayed()
        XCTAssertEqual(state?.reason, .stopped)
        XCTAssertEqual(rig.ticker.scheduled, 0, "a wait was armed after the person had stopped")
        XCTAssertTrue(rig.privileged.scripts.isEmpty)
    }

    /// A Stop that lands while a tick is reading — the token is the tick's to
    /// keep or the press's to take, and whoever loses does nothing.
    func testAStopWhileATickIsReadingEndsTheOperationAndTheTickDoesNothing() async {
        let rig = WaitRig()
        rig.engine.installBrew()
        rig.tools.installerRunning = true
        rig.tools.gitExecutable = true
        rig.tools.onInstallerRead = { [engine = rig.engine] in engine.stop() }

        rig.ticker.fire()

        XCTAssertTrue(rig.privileged.scripts.isEmpty,
                      "a Stop pressed during the tick did not stop the dialog")
        let (state, _) = await rig.replayed()
        XCTAssertEqual(state?.reason, .stopped)
        XCTAssertEqual(rig.ticker.live, 0)
    }

    /// A Stop that lands after the busy gate is taken and before the dialog,
    /// with the tools already there — no wait exists and no token can be taken,
    /// so the press leaves only the flag. The dialog is still not to be raised.
    func testAStopBetweenThePressAndTheDialogRaisesNoDialog() async {
        let rig = WaitRig()
        rig.tools.gitExecutable = true
        rig.tools.onRead = { [engine = rig.engine, tools = rig.tools] in
            tools.onRead = nil
            engine.stop()
        }

        rig.engine.installBrew()

        XCTAssertTrue(rig.privileged.scripts.isEmpty,
                      "a Stop pressed before the dialog did not stop the dialog")
        let (state, _) = await rig.replayed()
        XCTAssertEqual(state?.reason, .stopped)
    }
}
