// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmTestSupport
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// A model built asks the engine nothing; after `stop()` a press, a re-read or
/// news the engine still yields reaches nothing, is not drawn and starts nothing.
///
/// The host calls the descriptor's `stop(_:)` before the engine's `deactivate()`,
/// on the person's switch and on quit. A page still on screen, or a task already
/// queued, may press a control after that. A stopped model reaches no work, a
/// stream task left running keeps a subscriber on a stream nobody reads, and an
/// answer that was already out must not raise an irreversible
/// question over a page that is gone. Defect class kept: a stopped model still
/// talks to the engine, still listens to it, or still asks on an answer it
/// heard late.
///
/// Every absence rests on a control in this file.
@MainActor
final class AStoppedHomebrewModelReachesNoWorkTests: XCTestCase {

    private let wget = BrewPackage(name: "wget", version: "1.25", isCask: false)
    private let jq = BrewPackage(name: "jq", version: "1.8", isCask: false)
    private let outdatedWget = OutdatedPackage(name: "wget", installed: "1.24",
                                               latest: "1.25", isCask: false)

    /// The Stop button of the running operation, as the page presses it. One
    /// line so the name the model gives that press (its own `stop()` is the
    /// seam's close) is written in one place.
    private func pressStopButton(_ model: HomebrewViewModel) { model.stopOperation() }

    func testBuildingTheModelAsksTheEngineNothing() {
        let work = FakeHomebrewWork()
        let model = HomebrewViewModel(work: work)
        XCTAssertEqual(work.calls, ["stream"],
                       "the model asked the engine for something beside its stream when built")
        XCTAssertTrue(work.acts.isEmpty)
        model.stop()
    }

    func testAPressAfterStopReachesNoWork() async {
        let work = FakeHomebrewWork()
        work.dependents = []
        let model = HomebrewViewModel(work: work)

        // Control: every press reaches the work while the model lives.
        model.install(SearchHit(name: "wget", isCask: false))
        await model.askToUninstall(wget)
        model.confirmUninstall()
        model.upgrade(outdatedWget)
        model.upgradeAll()
        model.installBrew()
        pressStopButton(model)
        model.askToRunFix(DoctorFix(argv: ["cleanup"], kind: .runnable))
        model.askToRunFix(DoctorFix(argv: ["uninstall", "wget"], kind: .runnable))
        model.confirmFix()
        let live: [HomebrewAct] = [
            .install(PackageRef(name: "wget", isCask: false)),
            .uninstall(PackageRef(name: "wget", isCask: false)),
            .upgrade(name: "wget"), .upgradeAll, .installBrew, .stop,
            .doctorFix(argv: ["cleanup"]),
            .doctorFix(argv: ["uninstall", "wget"]),
        ]
        XCTAssertEqual(work.acts, live, "control: the presses did not reach the work")

        // The console has something in it, so «installBrew cleared it» is visible.
        work.say(.line("==> downloading"))
        await eventually("a line reaches the console") { model.consoleLines == ["==> downloading"] }

        model.stop()
        let before = work.calls
        model.install(SearchHit(name: "wget", isCask: false))
        await model.askToUninstall(wget)
        model.confirmUninstall()
        model.upgrade(outdatedWget)
        model.upgradeAll()
        model.installBrew()
        pressStopButton(model)
        model.askToRunFix(DoctorFix(argv: ["cleanup"], kind: .runnable))
        model.askToRunFix(DoctorFix(argv: ["uninstall", "wget"], kind: .runnable))
        model.confirmFix()
        await grace()
        XCTAssertEqual(work.acts, live, "a stopped model pressed something on the engine")
        XCTAssertEqual(work.calls, before, "a stopped model reached the engine")
        XCTAssertNil(model.pendingUninstall, "a stopped model raised the uninstall question")
        XCTAssertEqual(model.consoleLines, ["==> downloading"],
                       "a stopped model wiped a console it will never write to again")
    }

    func testAQueryAfterStopReachesNoWork() async {
        let work = FakeHomebrewWork()
        work.installed = [wget, jq]
        work.outdated = [outdatedWget]
        work.hits = [SearchHit(name: "wget2", isCask: false)]
        work.config = BrewConfig(lines: [], text: "HOMEBREW_VERSION: 7")
        let model = HomebrewViewModel(work: work)

        // Control: every reading reaches the work while the model lives, the two
        // the inspector asks for (info, then the walk) included.
        work.info = PackageInfo(name: "wget", isCask: false, desc: nil, homepage: nil,
                                license: nil, tap: nil, latestVersion: "1.25",
                                installedVersion: "1.25", installedAt: nil,
                                installedOnRequest: nil, deprecationReason: nil,
                                replacement: nil, siblings: [], dependencies: [],
                                caveats: nil)
        work.bytes = 4096
        await model.loadIfNeeded()
        await model.refreshOutdated()
        await model.refreshDoctor()
        await model.refreshConfig()
        await model.search("wget")
        await model.askToUninstall(wget)
        model.cancelUninstall()
        model.select(wget.id)
        await eventually("the inspector's two reads reach the work") {
            work.calls.contains("readInfo wget") && work.calls.contains("measure wget")
        }
        for call in ["readStatus", "readInstalled", "readOutdated", "readDoctor", "readConfig",
                     "find wget", "readDependents wget", "readDescriptions"] {
            XCTAssertTrue(work.calls.contains(call), "control: \(call) never reached the work")
        }

        model.stop()
        let before = work.calls
        await model.loadIfNeeded()
        await model.refreshStatus()
        await model.refreshInstalled()
        await model.refreshOutdated()
        await model.refreshDoctor()
        await model.refreshConfig()
        await model.search("jq")
        await model.askToUninstall(jq)
        model.select(jq.id)
        await grace()
        XCTAssertEqual(work.calls, before, "a stopped model read from the engine")
        XCTAssertNil(model.pendingUninstall, "a nil from a closed door was read as an answer")
    }

    func testANewsAfterStopIsNotDrawn() async {
        let work = FakeHomebrewWork()
        let model = HomebrewViewModel(work: work)

        // Control: news reaches the console and the state while the model lives,
        // and a finished operation asks the engine to be read again.
        work.say(.line("==> upgrading"))
        work.say(.state(OpState(phase: .running, label: "upgrade wget")))
        await eventually("the news reaches the model") {
            model.consoleLines == ["==> upgrading"] && model.op.phase == .running
        }

        model.stop()
        await eventually("the stream is given back") { work.subscribers == 0 }
        XCTAssertEqual(work.finishedStreams, 1)
        let before = work.calls

        work.say(.line("==> after the stop"))
        work.say(.state(OpState(phase: .done, label: "upgrade wget", exitCode: 0)))
        await grace()
        XCTAssertEqual(model.consoleLines, ["==> upgrading"],
                       "a stopped model went on drawing what the engine said")
        XCTAssertEqual(model.op.phase, .running, "a stopped model took a state after the stop")
        XCTAssertEqual(work.calls, before,
                       "a stopped model re-read the machine for an operation it was not told of")
    }

    /// `AsyncStream` hands over what it had buffered even after its consumer is
    /// cancelled, so a loop that must go quiet keeps its own flag (`closed`). The
    /// news and the stop come in one main-actor turn: the loop has not run yet,
    /// so the line and the state are buffered when `stop()` cancels it.
    func testNewsBufferedInTheTurnOfTheStopIsNotDrawn() async {
        let work = FakeHomebrewWork()
        let model = HomebrewViewModel(work: work)
        work.say(.line("==> upgrading"))
        work.say(.state(OpState(phase: .running, label: "upgrade wget")))
        model.stop()
        await grace()
        XCTAssertEqual(model.consoleLines, [], "news buffered before the stop was drawn after it")
        XCTAssertEqual(model.op, OpState.idle, "a state buffered before the stop was taken after it")
        XCTAssertEqual(work.calls, ["stream"], "a stopped model re-read the machine")
    }

    func testAnAnswerLandingAfterStopRaisesNoDialog() async {
        // Control: the same ask, not stopped, raises the question.
        let live = FakeHomebrewWork()
        live.dependents = ["aria2"]
        let liveModel = HomebrewViewModel(work: live)
        await liveModel.askToUninstall(wget)
        XCTAssertEqual(liveModel.pendingUninstall, wget, "control: the ask raised nothing")
        XCTAssertEqual(liveModel.dependentsOfPending, ["aria2"])
        liveModel.stop()

        let work = FakeHomebrewWork()
        work.dependents = ["aria2"]
        work.park("readDependents")
        let model = HomebrewViewModel(work: work)
        let ask = Task { await model.askToUninstall(wget) }
        await eventually("the read is out") { work.calls.contains("readDependents wget") }
        model.stop()
        work.release("readDependents")
        await ask.value
        XCTAssertTrue(work.completed.contains("readDependents wget"), "the read never answered")
        XCTAssertNil(model.pendingUninstall,
                     "an answer that landed after the stop raised the uninstall question")
        XCTAssertEqual(model.dependentsOfPending, [])
    }
}
