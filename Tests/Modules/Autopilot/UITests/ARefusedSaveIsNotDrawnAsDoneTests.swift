import HelmRuntime
import XCTest
@testable import Module_Autopilot_Engine
@testable import Module_Autopilot_UI

/// **The rule set can stop being Helm's while the page is open, and nothing
/// tells the page.** The rules are JSON in a plist any process running as the
/// user can rewrite, and `SealedRules.write` refuses to save over a set it did
/// not write, so a save can be turned down at any moment by something the page
/// never saw happen.
///
/// `refusal` is a local flag standing in for that live fact
/// (Architecture/ModulePattern.md § Ports and logic), and `AutopilotWork.save`
/// answers nothing whether the write landed or was refused. So the page asks
/// again after every write, as `discardRefusedRules()` does; otherwise it would
/// draw somebody's configuration as saved when the engine dropped it, refuse
/// every later edit in silence, and keep the card that offers the way out off
/// the screen.
@MainActor
final class ARefusedSaveIsNotDrawnAsDoneTests: XCTestCase {

    private func model(on work: FakeAutopilotWork) -> AutopilotViewModel {
        AutopilotViewModel(work: work, historyChanges: AsyncStream { _ in },
                           presetFolders: FakePresetFolders([:]),
                           home: NSHomeDirectory())
    }

    private var rule: Rule {
        Rule(id: "r", name: "sort them", enabled: true, match: .all,
             conditions: [.fileExtension(["pdf"])], action: .sortIntoSubfolder(.kind))
    }

    private var folder: WatchedFolder {
        WatchedFolder(id: "downloads", path: NSHomeDirectory() + "/Downloads",
                      enabled: true, rules: [], depth: 1)
    }

    /// The control, first: the same gesture over a rule set the engine accepts
    /// hands the rule over and leaves the page on the folder list. Asserted on
    /// **what was sent**, not on what the page lists afterwards: the page
    /// re-reads after a write, and `FakeAutopilotWork` applies a save it was not
    /// refused, so the list is the fake's echo rather than evidence of the page.
    func testARuleSavedOverARuleSetTheEngineAcceptsIsHandedOver() async {
        let work = FakeAutopilotWork()
        let rvm = model(on: work)
        await rvm.appear()

        await rvm.save(rule, in: folder)

        XCTAssertEqual(work.saved.last?.count, 1, "the premise: the folder was sent")
        XCTAssertEqual(work.saved.last?.first?.rules.map(\.id), ["r"],
                       "the premise: with the rule in it")
        XCTAssertNotEqual(rvm.screen, .rulesRefused(.tampered),
                          "a page whose save was taken must not draw the refusal")
    }

    /// The same gesture when the engine refused it draws the refusal. The
    /// engine's half, the stored rules surviving, is
    /// `ARefusedRuleSetIsNotOverwrittenTests`.
    func testAPageWhoseSaveWasRefusedDoesNotGoOnDrawingItAsSaved() async {
        let work = FakeAutopilotWork()
        let rvm = model(on: work)
        await rvm.appear()
        XCTAssertNil(rvm.refusal, "the premise: the page opened on a rule set that was running")

        // Something rewrites the plist while the page is open. From here the
        // engine refuses every write and hands out `[]` — the same two answers
        // `SealedRules` gives for a rule set it did not write.
        work.answers(AutopilotStatus(refusal: .tampered))
        work.holds([WatchedFolder]())

        await rvm.save(rule, in: folder)

        XCTAssertTrue(work.calls.contains("save"),
                      "the premise: the page did send the save that was refused")
        XCTAssertEqual(rvm.screen, .rulesRefused(.tampered), """
            the page is still drawing the folder list after a write the engine refused, so \
            somebody's rule is on screen and is not in the store — and every edit after it is \
            refused too, in silence, with the card that offers the way out on a screen the page \
            is not showing
            """)
    }

    /// After any write the page asks `AutopilotWork.readStatus`, the only thing
    /// that reports a refusal, so the test above is not about one gesture.
    func testAWriteIsNeverFollowedByAskingWhatBecameOfIt() async {
        let work = FakeAutopilotWork()
        let rvm = model(on: work)
        await rvm.appear()

        await rvm.save(rule, in: folder)
        let afterTheSave = work.calls.drop { $0 != "save" }

        XCTAssertTrue(afterTheSave.contains("readStatus"), """
            nothing after the write asks the engine what it did with it — \(Array(afterTheSave)) \
            — and the engine's save answers nothing whether it saved or refused, so \
            there is nothing in the answer either
            """)
    }
}
