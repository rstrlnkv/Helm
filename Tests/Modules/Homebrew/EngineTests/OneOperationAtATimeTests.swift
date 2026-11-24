import Foundation
import XCTest
import HelmContract
@testable import Module_Homebrew_Engine

/// One long operation at a time — the engine's own first sentence, and nothing
/// held it.
///
/// `beginBusy`/`endBusy` guard every `brew install`, `uninstall`, `upgrade` and
/// `upgrade all` behind one flag, and the module's doc comment opens by
/// promising it. The refusal is quiet by design: the second press writes a line
/// to the console and returns, so a broken flag does not throw, does not fail a
/// build, and does not look like anything on screen — it runs two `brew`
/// processes against one prefix, which is the state Homebrew's own lock exists
/// to prevent.
///
/// **The runner has to be one that does not answer.** With a fake that calls
/// `onExit` synchronously, the flag is released before the first call returns
/// and a second one is admitted correctly — so a test built on such a fake
/// passes whether the guard exists or not. `ScriptedRunner` never exits, which
/// is what a real `brew install` looks like for the seconds that matter.
final class OneOperationAtATimeTests: XCTestCase {

    func testASecondOperationIsRefusedWhileTheFirstIsStillRunning() {
        let runner = ScriptedRunner(streams: .hold)
        let engine = brewEngine(runner)

        engine.install(name: "wget", isCask: false)
        XCTAssertEqual(runner.streamed.count, 1, "precondition: the first operation started")

        engine.uninstall(name: "jq", isCask: false)

        XCTAssertEqual(runner.streamed.count, 1,
                       "a second brew ran against the same prefix while the first was "
                       + "still going: \(runner.streamed)")
    }

    /// Every verb goes through the same gate, so none of them may be the one
    /// that slips past a running operation.
    func testEveryLongOperationRespectsTheGate() {
        for second in ["install", "uninstall", "upgrade", "upgradeAll"] {
            let runner = ScriptedRunner(streams: .hold)
            let engine = brewEngine(runner)
            engine.install(name: "wget", isCask: false)

            switch second {
            case "install": engine.install(name: "jq", isCask: true)
            case "uninstall": engine.uninstall(name: "jq", isCask: false)
            case "upgrade": engine.upgrade(name: "jq")
            default: engine.upgradeAll()
            }

            XCTAssertEqual(runner.streamed.count, 1, "\(second) ran beside a live operation")
        }
    }

    /// The other half: the flag is *released*. A guard that never lets go is a
    /// module that works once per launch, and it would pass the test above.
    func testTheNextOperationIsAdmittedOnceTheFirstHasFinished() {
        let runner = ScriptedRunner(streams: .hold)
        let engine = brewEngine(runner)

        engine.install(name: "wget", isCask: false)
        runner.finishAll()
        engine.uninstall(name: "jq", isCask: false)

        XCTAssertEqual(runner.streamed.count, 2,
                       "the operation ended and the gate stayed shut: \(runner.streamed)")
    }

    /// And a failure releases it too. `endBusy` runs before the exit code is
    /// looked at, so a `brew` that exits non-zero must not wedge the module.
    func testAFailedOperationAlsoReleasesTheGate() {
        let runner = ScriptedRunner(streams: .hold)
        let engine = brewEngine(runner)

        engine.install(name: "wget", isCask: false)
        runner.finishAll(code: 1)
        engine.upgradeAll()

        XCTAssertEqual(runner.streamed.count, 2, "a failed operation left the gate shut")
    }

    /// A second confirmed fix that is refused (its name left the Cellar) must
    /// not write `.failed` over the first fix's `.running`: Stop would go and
    /// the gate would look open while the child runs.
    func testARefusedSecondFixNeverOverwritesTheRunningOne() async {
        let runner = ScriptedRunner(streams: .hold, answers: [BrewAnswer(["list", "--formula"], 0, "ghost 1.0\n")])
        let news = EngineNews<HomebrewNews>()
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: NoPrivileges(), user: "tester", news: news)

        engine.runDoctorFix(["uninstall", "ghost"])
        XCTAssertEqual(runner.streamed.count, 1, "precondition: the first fix started")
        let first = await lastOpState(news)
        XCTAssertEqual(first?.phase, .running, "precondition: the first fix reached .running")

        engine.runDoctorFix(["uninstall", "ghost2"])

        let drained = await replayedState(news)
        let after = drained.state
        XCTAssertTrue(drained.busy,
                      "the refused press did not say so in the console")
        XCTAssertEqual(after?.phase, .running, "the refused press overwrote the running fix: \(String(describing: after))")
        XCTAssertEqual(after?.label, "uninstall ghost")
        engine.install(name: "wget", isCask: false)
        XCTAssertEqual(runner.streamed.count, 1, "the gate was open while the first fix ran")
    }

    private final class SwitchableLocator: BrewLocator, @unchecked Sendable {
        private let lock = NSLock()
        private var _path: String?
        init(_ path: String?) { _path = path }
        var path: String? {
            get { lock.lock(); defer { lock.unlock() }; return _path }
            set { lock.lock(); _path = newValue; lock.unlock() }
        }
        func brewPath() -> String? { path }
    }

    /// A press with brew gone is refused inside the gate: it must not
    /// overwrite a running operation, and it must hand the gate back.
    func testABrewMissingRefusalKeepsTheGateAndReleasesIt() async {
        let runner = ScriptedRunner(streams: .hold)
        let locator = SwitchableLocator("/opt/homebrew/bin/brew")
        let news = EngineNews<HomebrewNews>()
        let engine = HomebrewEngine(locator: locator, runner: runner,
                                    privileged: NoPrivileges(), user: "tester", news: news)

        engine.install(name: "wget", isCask: false)
        let first = await lastOpState(news)
        XCTAssertEqual(first?.phase, .running, "precondition: the install reached .running")

        locator.path = nil
        engine.install(name: "jq", isCask: false)
        let drained = await replayedState(news)
        let during = drained.state
        XCTAssertTrue(drained.busy,
                      "the refused press did not say so in the console")
        XCTAssertEqual(during?.phase, .running, "a brew-missing press overwrote the running install: \(String(describing: during))")
        XCTAssertEqual(during?.label, first?.label)

        runner.finishAll()
        engine.install(name: "jq", isCask: false)
        let refused = await lastOpState(news)
        XCTAssertEqual(refused?.phase, .failed)
        XCTAssertEqual(refused?.reason, .brewMissing)

        locator.path = "/opt/homebrew/bin/brew"
        engine.install(name: "jq", isCask: false)
        XCTAssertEqual(runner.streamed.count, 2, "a refused press left the gate shut")
    }
}
