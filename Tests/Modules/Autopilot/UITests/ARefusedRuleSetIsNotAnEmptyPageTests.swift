import HelmContract
import HelmRuntime
import HelmUI
import XCTest
import Module_Autopilot_Engine
@testable import Module_Autopilot_UI

/// **«You have no folders» is what a tampered rule set looks like on screen.**
///
/// The engine refuses a rule set something else wrote and hands out `[]`, which
/// is the same value a Mac that has never had a rule hands out — so the page
/// draws its "point Helm at a folder" empty state, whose one control is «Add
/// folder…», and the press that follows used to write an empty list over rules
/// nothing can rebuild.
///
/// The engine's half of that is `ARefusedRuleSetIsNotOverwrittenTests`. This is
/// the half a person sees: the page has to say the rules could not be read, and
/// say which of the two reasons it is, because only one of them can be answered
/// by throwing them away.
@MainActor
final class ARefusedRuleSetIsNotAnEmptyPageTests: XCTestCase {

    private func model(on wire: AutopilotWire) -> AutopilotViewModel {
        AutopilotViewModel(vm: ModuleViewModel(transport: wire))
    }

    // MARK: - The control

    /// Asserted first: a Mac with no rules really does reach the empty state,
    /// so the assertions below are about a page that would otherwise draw it.
    func testAMacWithNoRulesDrawsTheEmptyState() async {
        let wire = AutopilotWire()
        let model = model(on: wire)

        await model.load()

        XCTAssertTrue(wire.commands.contains(.status), "precondition: the status was asked for")
        XCTAssertEqual(model.screen, .noFolders)
    }

    func testAMacWithRulesDrawsThem() async {
        let wire = AutopilotWire(folders: [WatchedFolder(path: "/tmp/watched")])
        let model = model(on: wire)

        await model.load()

        XCTAssertEqual(model.screen, .folders)
    }

    // MARK: - The refusal

    func testARuleSetSomebodyElseWroteIsNotDrawnAsAnEmptyMac() async {
        let wire = AutopilotWire(status: AutopilotStatus(refusal: .tampered))
        let model = model(on: wire)

        await model.load()

        XCTAssertEqual(model.screen, .rulesRefused(.tampered), """
            the page draws «\(ApStr.startHint)» over a rule set that was not written by Helm, \
            and its one control writes an empty list over it.
            """)
    }

    /// The other refusal, which is not the same sentence and must not be
    /// answered by deleting anything: the rules are very probably the person's
    /// own and the keychain is locked.
    func testAKeyThatCouldNotBeReadIsItsOwnScreen() async {
        let wire = AutopilotWire(status: AutopilotStatus(refusal: .noKey))
        let model = model(on: wire)

        await model.load()

        XCTAssertEqual(model.screen, .rulesRefused(.noKey))
        XCTAssertNotEqual(ApStr.rulesTampered, ApStr.rulesUnreadable,
                          "one sentence for two states the person can do different things about")
    }

    // MARK: - What the page may send

    /// A refused page must not be able to save. The engine refuses the write as
    /// well — belt and braces, and deliberately: the engine's guard is what makes
    /// it true for every caller, and this is what stops the page offering a
    /// gesture that will not work.
    ///
    /// **The folder list and the refusal are two requests, and this is the state
    /// between them.** Written first with an empty list and a folder the page had
    /// never heard of, which passed with the guard deleted: `update` drops a
    /// folder it cannot find long before `save` is reached, so the test asserted
    /// that a save nothing had attempted did not happen. The engine answers
    /// `folders` and `status` one after the other, and a plist rewritten between
    /// the two leaves exactly this page — a list it may no longer write back.
    func testTheRefusedPageDoesNotSendAFolderList() async {
        let watched = WatchedFolder(id: "downloads", path: "/tmp/watched")
        let wire = AutopilotWire(folders: [watched],
                                 status: AutopilotStatus(refusal: .tampered))
        let model = model(on: wire)
        await model.load()
        XCTAssertEqual(model.folders.map(\.id), ["downloads"],
                       "precondition: the page is holding the folder the gesture is about")

        model.setEnabled(false, folder: watched)

        XCTAssertEqual(wire.saved, [], "a refused page wrote a folder list over the refused rules")
    }

    /// And the one thing it may send. It is the only way out: while the rules
    /// are refused every save is refused too, so a page with no discard is a page
    /// that never takes another edit.
    func testDiscardingIsSentAndTheScreenComesBack() async {
        let wire = AutopilotWire(status: AutopilotStatus(refusal: .tampered))
        let model = model(on: wire)
        await model.load()
        XCTAssertEqual(model.screen, .rulesRefused(.tampered), "precondition")

        wire.answers(AutopilotStatus(refusal: nil))
        await model.discardRefusedRules()

        XCTAssertTrue(wire.commands.contains(.discardRefusedRules),
                      "the button drew and sent nothing")
        XCTAssertEqual(model.screen, .noFolders, "the page did not read the state back")
    }

    // MARK: - The silences

    /// A status nobody answered is not «your rules are fine». Both silences,
    /// because the wire has two and `TransportClient` folds them to one nil.
    func testAStatusNobodyAnsweredIsNotAnAllClear() async {
        for silence in [AutopilotWire.Answer.refuse, .nothing] {
            let wire = AutopilotWire(status: AutopilotStatus(refusal: .tampered),
                                     answering: silence)
            let model = model(on: wire)

            await model.load()

            XCTAssertTrue(wire.commands.contains(.status),
                          "precondition: the status really was asked for (\(silence))")
            XCTAssertNotEqual(model.screen, .rulesRefused(.tampered),
                              "a lost reply cannot be read as a refusal it never carried")
        }
    }
}
