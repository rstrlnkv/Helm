// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmTestSupport
import HelmRuntime
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// What the engine announces reaches the model on the one stream, in the order
/// it was said, and an operation that ended sends the model back to read the
/// machine.
///
/// The stream carries three kinds, a line (an edge, every one of them), a state
/// (a level) and where brew is (a seed), and the model's loop is the only
/// reader. What it holds: a line lost or reordered, an ending that re-reads
/// nothing, a re-read for a state that is not an ending, or a seed that
/// overwrites a status the engine has already answered.
@MainActor
final class AnOperationsNewsReachesTheModelTests: XCTestCase {

    private func running(_ label: String = "upgrade wget",
                         waiting: OpWait? = nil) -> OpState {
        OpState(phase: .running, label: label, waiting: waiting)
    }

    func testLinesReachTheConsoleInOrder() async {
        let work = FakeHomebrewWork()
        let model = HomebrewViewModel(work: work)
        let said = (1...6).map { "line \($0)" }
        for line in said { work.say(.line(line)) }
        await eventually("every line reaches the console") { model.consoleLines.count == said.count }
        XCTAssertEqual(model.consoleLines, said)
        XCTAssertEqual(model.consoleSequence, said.count)
        XCTAssertEqual(work.calls, ["stream"], "a line sent the model to read the machine")
    }

    func testAFinishedOperationReReadsTheMachine() async {
        for ending in [OpState(phase: .done, label: "upgrade wget", exitCode: 0),
                       OpState(phase: .failed, label: "upgrade wget", exitCode: 1)] {
            let work = FakeHomebrewWork()
            let model = HomebrewViewModel(work: work)

            // Control: a running state is drawn and asks the engine nothing.
            work.say(.state(running()))
            await eventually("the running state reaches the model") { model.op.phase == .running }
            await grace()
            XCTAssertEqual(work.calls, ["stream"],
                           "a state that is not an ending sent the model to read the machine")

            work.say(.state(ending))
            await eventually("\(ending.phase) is read again: status, lists") {
                work.completed.count >= 3
            }
            await grace()
            XCTAssertEqual(model.op, ending)
            XCTAssertEqual(work.calls, ["stream", "readStatus", "readInstalled", "readOutdated"],
                           "an operation that ended (\(ending.phase)) did not re-read, or read "
                           + "what nobody had asked for, or in another order")
        }
    }

    func testTheDoctorAndTheConfigAreReReadOnlyIfTheyWereEverAsked() async {
        let work = FakeHomebrewWork()
        work.config = BrewConfig(lines: [], text: "HOMEBREW_VERSION: 7")
        let model = HomebrewViewModel(work: work)
        await model.refreshDoctor()
        await model.refreshConfig()
        // `refreshDoctor` reads the installed list first when it was never read (the fix verdict is about it).
        XCTAssertEqual(work.calls, ["stream", "readInstalled", "readDoctor", "readConfig"],
                       "control: both were asked, the doctor after the list it is judged against")
        XCTAssertNotNil(model.config, "control: the config reading was kept")

        work.say(.state(OpState(phase: .done, label: "cleanup", exitCode: 0)))
        await eventually("the ending is read again, config last") {
            work.completed.filter { $0 == "readConfig" }.count == 2
        }
        await grace()
        XCTAssertEqual(work.calls, ["stream", "readInstalled", "readDoctor", "readConfig",
                                    "readStatus", "readInstalled", "readOutdated",
                                    "readDoctor", "readConfig"])
    }

    func testTheWaitForApplesToolsSaysItsLine() async {
        let work = FakeHomebrewWork()
        let model = HomebrewViewModel(work: work)
        let language = AppLanguage.current
        let waitingLine = HbStr.toolsWaitingConsole(language: language)
        let arrivedLine = HbStr.toolsArrivedConsole(language: language)
        XCTAssertNotEqual(waitingLine, arrivedLine, "control: the two sentences are one")

        work.say(.state(running("install Homebrew", waiting: .commandLineTools)))
        await eventually("the wait reaches the model") { model.op.waiting == .commandLineTools }
        XCTAssertEqual(model.consoleLines, [waitingLine])

        work.say(.state(running("install Homebrew")))
        await eventually("the arrival reaches the model") { model.op.waiting == nil }
        XCTAssertEqual(model.consoleLines, [waitingLine, arrivedLine])
    }

    func testWhereBrewIsSeedsTheStatusBeforeAnyRead() async {
        let work = FakeHomebrewWork()
        work.say(.brew(path: "/seed/bin/brew"))
        let model = HomebrewViewModel(work: work)
        await eventually("the seed reaches the model") { model.status.installed }
        XCTAssertEqual(model.status.brewPath, "/seed/bin/brew")
        XCTAssertEqual(work.calls, ["stream"], "a seed sent the model to read the machine")
    }

    func testASeedAfterTheReadLeavesTheReadStanding() async {
        let work = FakeHomebrewWork()
        work.status = BrewStatus(installed: true, brewPath: "/real/bin/brew",
                                 interruptedOp: "upgrade wget")
        let model = HomebrewViewModel(work: work)
        await model.refreshStatus()
        XCTAssertEqual(model.status.interruptedOp, "upgrade wget", "control: the read was not kept")

        work.say(.brew(path: "/seed/bin/brew"))
        work.say(.line("after the seed"))
        // The line is behind the seed on one stream: once it is shown, the seed was handled.
        await eventually("the line behind the seed reaches the console") {
            model.consoleLines.last == "after the seed"
        }
        XCTAssertEqual(model.status.brewPath, "/real/bin/brew")
        XCTAssertEqual(model.status.interruptedOp, "upgrade wget",
                       "a seed wrote over the status the engine had answered")
    }

    func testNoBrewSeedsNotInstalled() async {
        let work = FakeHomebrewWork()
        work.say(.brew(path: nil))
        work.say(.line("after the seed"))
        let model = HomebrewViewModel(work: work)
        await eventually("the line behind the seed reaches the console") {
            model.consoleLines.last == "after the seed"
        }
        XCTAssertFalse(model.status.installed)
        XCTAssertNil(model.status.brewPath)
    }
}
