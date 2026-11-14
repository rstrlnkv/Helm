import HelmTestSupport
@testable import HelmUI
import XCTest
@testable import Module_Autopilot_Engine
@testable import Module_Autopilot_UI

/// **Deleting a record asks first.** «Discard rules», «Clear» and «Discard history»
/// each used to act on the press; the press now only calls `ask`, which sets `pendingDiscard`, and
/// `confirmDiscard()` is the one door to `dropRefusedRules` and `dropHistory`.
///
/// Held for the class a wrong build puts in front of somebody's data: a button
/// that calls the drop directly deletes a record on a stray click.
@MainActor
final class DiscardingAsksFirstTests: XCTestCase {

    private func model(_ work: FakeAutopilotWork) -> AutopilotViewModel {
        AutopilotViewModel(work: work, historyChanges: AsyncStream { _ in })
    }

    private let gestures: [(AutopilotViewModel.Discard, String)] = [
        (.rules, "dropRefusedRules"), (.history, "dropHistory"), (.refusedHistory, "dropHistory"),
    ]

    /// Asserted first: the fake records a drop at all, so "none recorded" below means none was sent.
    func testTheFakeRecordsDrops() async {
        let work = FakeAutopilotWork()
        let model = model(work)
        model.ask(.rules)
        await model.confirmDiscard()
        model.ask(.history)
        await model.confirmDiscard()
        XCTAssertEqual(work.count("dropRefusedRules"), 1, "precondition")
        XCTAssertEqual(work.count("dropHistory"), 1, "precondition")
    }

    func testPressingAsksAndDropsNothing() async {
        for (gesture, drop) in gestures {
            let work = FakeAutopilotWork()
            let model = model(work)
            model.ask(gesture)
            try? await Task.sleep(nanoseconds: 50_000_000)
            XCTAssertEqual(work.count(drop), 0, "\(gesture) dropped on the press")
            XCTAssertEqual(model.pendingDiscard, gesture)
        }
    }

    func testConfirmingDropsExactlyOnce() async {
        for (gesture, drop) in gestures {
            let work = FakeAutopilotWork()
            let model = model(work)
            model.ask(gesture)
            await model.confirmDiscard()
            XCTAssertEqual(work.count(drop), 1, "\(gesture)")
            XCTAssertNil(model.pendingDiscard)
            await model.confirmDiscard()
            XCTAssertEqual(work.count(drop), 1, "\(gesture): a second confirm with nothing asked dropped again")
        }
    }

    /// The dialog may clear `pendingDiscard` before the button's task runs; the button hands over
    /// what it read on the press.
    func testConfirmingWhatTheButtonReadDropsAfterTheDialogClearedIt() async {
        for (gesture, drop) in gestures {
            let work = FakeAutopilotWork()
            let model = model(work)
            model.ask(gesture)
            let read = model.pendingDiscard
            model.pendingDiscard = nil
            await model.confirmDiscard(read)
            XCTAssertEqual(work.count(drop), 1, "\(gesture)")
        }
    }

    func testCancellingDropsNothing() async {
        for (gesture, _) in gestures {
            let work = FakeAutopilotWork()
            let model = model(work)
            model.ask(gesture)
            model.pendingDiscard = nil
            await model.confirmDiscard()
            XCTAssertEqual(work.count("dropRefusedRules") + work.count("dropHistory"), 0, "\(gesture)")
        }
    }

    func testAClosedModelAsksNothing() {
        let model = model(FakeAutopilotWork())
        model.stop()
        model.ask(.rules)
        XCTAssertNil(model.pendingDiscard)
    }

    func testEachQuestionIsItsOwnSentenceInEveryLanguage() {
        let all: [AutopilotViewModel.Discard] = [.rules, .history, .refusedHistory]
        AppLanguage.each { language in
            XCTAssertEqual(Set(all.map { ApStr.discardQuestion($0) }).count, 3, "\(language)")
        }
    }

    /// The three buttons are views, which a model test cannot press, so the
    /// wiring is read from the source: each press says `ask`, and the only
    /// call to a drop in the views is the dialog's `confirmDiscard`.
    func testTheButtonsOnlyAsk() throws {
        let ui = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Modules/Autopilot/UI")
        func source(_ name: String) throws -> String {
            try String(contentsOf: ui.appendingPathComponent(name), encoding: .utf8)
        }
        let page = try source("AutopilotSettingsPage.swift")
        let history = try source("HistorySection.swift")
        XCTAssertTrue(page.contains("Button(ApStr.discardRules, role: .destructive) {\n                        rvm.ask(.rules)"),
                      "the banner button no longer only asks")
        XCTAssertTrue(history.contains("Button(ApStr.historyClear) { clear(.history) }"))
        XCTAssertTrue(history.contains("Button(ApStr.discardHistory) { clear(.refusedHistory) }"))
        XCTAssertTrue(page.contains("clear: { rvm.ask($0) }"), "the history section's clear no longer only asks")
        // The confirm button hands over what the dialog showed, read before the dialog clears it.
        // The capture is in the synchronous closure, before the Task that awaits the drop.
        XCTAssertTrue(page.contains("let asked = rvm.pendingDiscard\n                Task { await rvm.confirmDiscard(asked) }"),
                      "the confirm button no longer captures what was asked before the Task, or no longer passes it")
        XCTAssertFalse(page.contains("confirmDiscard()"), "the confirm button reads pendingDiscard after the dialog cleared it")
        for name in ["AutopilotSettingsPage.swift", "HistorySection.swift"] {
            let text = try source(name)
            for drop in ["discardRefusedRules", "clearHistory", "dropHistory"] {
                XCTAssertFalse(text.contains(drop), "\(name) calls \(drop) without asking")
            }
        }
    }
}
