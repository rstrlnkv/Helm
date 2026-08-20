import HelmContract
import HelmRuntime
import HelmUI
import XCTest
import Module_Autopilot_Engine
@testable import Module_Autopilot_UI

/// **The rule set can stop being Helm's while the page is open, and nothing
/// tells the page.**
///
/// The refusal is a live external fact: the rules are JSON in a plist any
/// process running as this user can rewrite, and `SealedRules.write` refuses to
/// save over a set it did not write — deliberately, because «the refusal must
/// not be the thing that destroys the rules». So a save can be turned down at
/// any moment by something the page never saw happen.
///
/// What the page has instead is `refusal`, read once at load and consulted by
/// `save()` as `guard refusal == nil`, which is CLAUDE.md's family by name: a
/// local flag standing in for a live external fact, with no reverse channel from
/// the port that knows. And there is no channel to have: `AutopilotEvent` has
/// exactly one case, `history`; `AutopilotCommand.setFolders` is answered with
/// `Data()` whether the write landed or was refused, so even the two save paths
/// that *are* `async` and awaited cannot learn; and nothing re-reads the status
/// after a write.
///
/// The result is the one thing a settings page must never do: show somebody
/// their own configuration as saved when the engine dropped it. Every later edit
/// is refused too, silently, for as long as the page stays open — and the card
/// that offers the one way out (`discardRefusedRules`) is on the screen the page
/// is not drawing.
///
/// The module already has the shape of the answer and uses it one method away:
/// `discardRefusedRules()` sends and then `await load()`s. This is the same
/// gesture on the write path.
@MainActor
final class ARefusedSaveIsNotDrawnAsDoneTests: XCTestCase {

    private func model(on wire: AutopilotWire) -> AutopilotViewModel {
        AutopilotViewModel(vm: ModuleViewModel(transport: wire),
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

    /// The control, and it has to come first: this same gesture over a rule set
    /// the engine accepts hands the rule over and leaves the page on the folder
    /// list, so the assertion below is about a page that would otherwise stay
    /// there.
    ///
    /// Asserted on **what was sent** rather than on what the page lists
    /// afterwards. `AutopilotWire` records a save without applying it, which is
    /// a state the real engine cannot be in — it accepted the write, so its next
    /// `folders` holds it — and a control resting on that echo would fail for
    /// the fake's reasons the moment the page learned to re-read after a write.
    func testARuleSavedOverARuleSetTheEngineAcceptsIsHandedOver() async {
        let wire = AutopilotWire()
        let rvm = model(on: wire)
        await rvm.firstLoad?.value

        await rvm.save(rule, in: folder)

        XCTAssertEqual(wire.saved.last?.count, 1, "the premise: the folder was sent")
        XCTAssertEqual(wire.saved.last?.first?.rules.map(\.id), ["r"],
                       "the premise: with the rule in it")
        XCTAssertNotEqual(rvm.screen, .rulesRefused(.tampered),
                          "a page whose save was taken must not draw the refusal")
    }

    /// And the same gesture when the engine refused it.
    ///
    /// The engine's half is `ARefusedRuleSetIsNotOverwrittenTests`: the write is
    /// turned down and the stored rules survive. This is the half a person sees
    /// — and what they see is the folder they just added, listed, on a page that
    /// still believes the rules are running.
    func testAPageWhoseSaveWasRefusedDoesNotGoOnDrawingItAsSaved() async {
        let wire = AutopilotWire()
        let rvm = model(on: wire)
        await rvm.firstLoad?.value
        XCTAssertNil(rvm.refusal, "the premise: the page opened on a rule set that was running")

        // Something rewrites the plist while the page is open. From here the
        // engine refuses every write and hands out `[]` — the same two answers
        // `SealedRules` gives for a rule set it did not write.
        wire.answers(AutopilotStatus(refusal: .tampered))
        wire.holds([WatchedFolder]())

        await rvm.save(rule, in: folder)

        XCTAssertTrue(wire.commands.contains(.setFolders),
                      "the premise: the page did send the save that was refused")
        XCTAssertEqual(rvm.screen, .rulesRefused(.tampered), """
            the page is still drawing the folder list after a write the engine refused, so \
            somebody's rule is on screen and is not in the store — and every edit after it is \
            refused too, in silence, with the card that offers the way out on a screen the page \
            is not showing
            """)
    }

    /// The mechanism behind it, stated separately so the finding above cannot be
    /// read as being about one gesture: after a write, the page asks nothing.
    ///
    /// A refusal is a fact about the store, and the only thing that ever reports
    /// it is `AutopilotCommand.status` — which the page sends when it loads and
    /// never again on this path. `discardRefusedRules()` is the counter-example
    /// in the same file: it sends, then loads.
    func testAWriteIsNeverFollowedByAskingWhatBecameOfIt() async {
        let wire = AutopilotWire()
        let rvm = model(on: wire)
        await rvm.firstLoad?.value

        await rvm.save(rule, in: folder)
        let afterTheSave = wire.commands.drop { $0 != .setFolders }

        XCTAssertTrue(afterTheSave.contains(.status), """
            nothing after the write asks the engine what it did with it — \(Array(afterTheSave)) \
            — and the engine answers setFolders with empty Data whether it saved or refused, so \
            there is nothing in the reply either
            """)
    }
}
