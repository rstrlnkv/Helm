import HelmTestSupport
@testable import HelmUI
import XCTest
@testable import Module_Autopilot_Engine
@testable import Module_Autopilot_UI

/// **Deleting a record asks first.** A press of «Discard rules», «Clear» or «Discard history»
/// only calls `ask`, which sets `pendingDiscard`, and
/// `confirmDiscard()` is the one door to `dropRefusedRules` and `dropHistory`.
///
/// Held for the class a wrong build puts in front of somebody's data: a button
/// that calls the drop directly deletes a record on a stray click. The two drops
/// are `private` to the view model, so a view cannot reach them: the compiler holds it.
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
            await grace(0.05)
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
}
