// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmTestSupport
import HelmContract
@testable import Module_Homebrew_Engine

/// The engine's door for the model (`perform(_:)` and the `read…` members) runs
/// what an act names, judges a fix again at the press, and never runs on the
/// caller's thread.
///
/// Three things the door could get wrong without any other test noticing:
/// `uninstall` wired to `install`'s arm (every other test calls the sync
/// methods directly); `runDoctorFix` bypassed by the door
/// (`AFixIsJudgedAgainstTheCellarAtThePressTests` calls it directly); and a press
/// that runs where it was made — `runOp` writes a file and launches a child, on
/// the main actor if it was pressed there. An `async` requirement is satisfied by
/// a sync method of the same name, so the last one compiles either way and is
/// only visible from the thread the runner sees.
final class TheDoorRunsWhatItNamesTests: XCTestCase {

    /// A brew whose operations never exit, as a real `brew install` does not, and whose
    /// Cellar holds `wget` as the fix is judged (`brew list --versions --formula`).
    private func doorRunner() -> ScriptedRunner {
        ScriptedRunner(streams: .hold, answers: [BrewAnswer(["list", "--formula"], 0, "wget 1.25.0\n")])
    }

    func testEachActStartsItsOwnCommand() async {
        let wget = PackageRef(name: "wget", isCask: false)
        let iterm = PackageRef(name: "iterm2", isCask: true)
        let table: [(HomebrewAct, [String])] = [
            (.install(wget), ["install", "--", "wget"]),
            (.install(iterm), ["install", "--cask", "--", "iterm2"]),
            (.uninstall(wget), ["uninstall", "--", "wget"]),
            (.uninstall(iterm), ["uninstall", "--cask", "--", "iterm2"]),
            (.upgrade(name: "wget"), ["upgrade", "--", "wget"]),
            (.upgradeAll, ["upgrade"]),
            (.doctorFix(argv: ["cleanup"]), ["cleanup"]),
            (.doctorFix(argv: ["uninstall", "wget"]), ["uninstall", "--", "wget"]),
        ]
        for (act, argv) in table {
            let runner = doorRunner()
            let engine = brewEngine(runner)
            engine.perform(act)
            await waitUntilReached("\(act) launches") { !runner.streamed.isEmpty }
            XCTAssertEqual(runner.streamed, [argv], "\(act) started another command")
        }
    }

    func testAFixThroughTheDoorIsStillJudged() async {
        // Control: a fix the Cellar admits launches through the door.
        let admitted = doorRunner()
        brewEngine(admitted).perform(.doctorFix(argv: ["uninstall", "wget"]))
        await waitUntilReached("the admitted fix launches") { !admitted.streamed.isEmpty }
        XCTAssertEqual(admitted.streamed, [["uninstall", "--", "wget"]])

        // A name the Cellar does not hold: refused with its reason, nothing launched.
        let runner = doorRunner()
        let engine = brewEngine(runner)
        let news = engine.stream()
        engine.perform(.doctorFix(argv: ["uninstall", "not-installed"]))
        let got = await collect(news, through: { if case .state(let s) = $0, s.phase == .failed { true } else { false } })
        let refusal = got.states.last
        XCTAssertEqual(refusal?.reason, .fixRefused,
                       "the door ran, or failed, a fix without judging it against the Cellar")
        XCTAssertEqual(refusal?.label, "uninstall not-installed")
        XCTAssertTrue(runner.streamed.isEmpty, "a fix the Cellar does not admit was launched")
        // The judgement read the Cellar: the refusal is of this reading, not a default.
        XCTAssertTrue(runner.calls.contains { $0.kind == .run && $0.args.first == "list" })
    }

    @MainActor
    func testAPressAndAReadLeaveTheCallersThread() async {
        XCTAssertTrue(Thread.isMainThread, "control: the test itself runs on the main thread, where a press must not run")

        let pressed = doorRunner()
        let engine = brewEngine(pressed)
        engine.perform(.install(PackageRef(name: "wget", isCask: false)))
        await waitUntilReached("the press launches") { !pressed.streamed.isEmpty }

        let fixed = doorRunner()
        let fixEngine = brewEngine(fixed)
        fixEngine.perform(.doctorFix(argv: ["cleanup"]))
        await waitUntilReached("the fix launches") { !fixed.streamed.isEmpty }

        let read = doorRunner()
        let readEngine = brewEngine(read)
        _ = await readEngine.readInstalled()
        _ = await readEngine.readOutdated()
        _ = await readEngine.find("wget")
        _ = await readEngine.readDescriptions(of: ["wget"], isCask: false, stillWanted: { true })
        _ = await readEngine.readDoctor()
        _ = await readEngine.readConfig()

        let all = pressed.calls + fixed.calls + read.calls
        XCTAssertTrue(all.contains { $0.kind == .stream } && all.contains { $0.kind == .run },
                      "control: the runners saw no launch and no read")
        for seen in all {
            XCTAssertFalse(seen.onMain, "\(seen.kind) \(seen.args) ran on the main thread")
            XCTAssertFalse(seen.queue.contains("cooperative"),
                           "\(seen.kind) \(seen.args) parked a thread of the cooperative pool "
                           + "(\(seen.queue))")
        }
    }
}
