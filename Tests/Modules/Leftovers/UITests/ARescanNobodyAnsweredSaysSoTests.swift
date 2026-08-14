import HelmContract
import HelmRuntime
import XCTest
import Module_Leftovers_Engine
@testable import HelmUI
@testable import Module_Leftovers_UI

/// **A rescan nobody answered left the old list on screen in silence.**
///
/// `reload`'s `guard let found else { return }` is the right thing to do — an
/// unanswered request is not an answer, and folding it to `[]` threw away the
/// list somebody was working through — and it is mute. The Scan button dims,
/// spins and comes back, the rows are exactly as they were, and nothing says the
/// machine never replied.
///
/// And the two silences this page can be in meet on the first press that fails:
/// `trash` rescans on its own lost-reply path, so a removal nobody answered is
/// followed by a scan that may not answer either. There the removal's sentence
/// covers both, and this one must not also be drawn.
@MainActor
final class ARescanNobodyAnsweredSaysSoTests: XCTestCase {

    override func setUp() {
        super.setUp()
        HelmLog.shared.setEnabled(true)
        HelmLog.shared.clearTail()
    }

    override func tearDown() {
        HelmLog.shared.clearTail()
        HelmLog.shared.setEnabled(false)
        super.tearDown()
    }

    private var logged: [String] {
        HelmLog.shared.recentEntries()
            .filter { $0.category == LeftoversEngine.moduleID }
            .map(\.message)
    }

    private func agent(_ name: String) -> StaleItem {
        StaleItem(path: "\(NSHomeDirectory())/Library/LaunchAgents/\(name).plist",
                  identifier: name, kind: .launchAgent, sizeBytes: 4_096, status: .orphaned)
    }

    // MARK: - The scan that went unanswered

    /// Both silences the wire has: empty `Data`, which this module reaches in the
    /// tree when its engine has gone under a page that is still up, and a throw.
    func testARescanThatWasNeverAnsweredSaysSoAndKeepsTheList() async {
        for silence in [LeftoversWire.Answer.nothing, .refuse] {
            let item = agent("com.vendor.updater")
            let wire = LeftoversWire(items: [item])
            let model = LeftoversViewModel(vm: ModuleViewModel(transport: wire))
            await model.scan()
            XCTAssertEqual(model.items.count, 1, "precondition: the first scan answered")

            wire.answers(silence)
            await model.scan()

            XCTAssertEqual(wire.commands.filter { $0 == .scan }.count, 2,
                           "precondition: the rescan really was sent (\(silence))")
            XCTAssertEqual(model.items.count, 1,
                           "the list is kept, which is the half that was already right")
            XCTAssertTrue(model.scanReplyLost, """
                the rescan was never answered and the page says nothing: the button dims, spins \
                and comes back, and the rows are the previous scan's with nothing to say so \
                (\(silence)).
                """)
        }
    }

    /// And a scan that *was* answered puts the sentence down again, or it stands
    /// over every list from then on.
    func testAnAnsweredScanTakesTheSentenceDown() async {
        let item = agent("com.vendor.updater")
        let wire = LeftoversWire(items: [item])
        let model = LeftoversViewModel(vm: ModuleViewModel(transport: wire))
        await model.scan()
        wire.answers(.nothing)
        await model.scan()
        XCTAssertTrue(model.scanReplyLost, "precondition: a rescan was lost")

        wire.answers(.reply)
        await model.scan()

        XCTAssertFalse(model.scanReplyLost,
                       "the sentence about a lost answer outlived the scan it was about")
    }

    /// It reaches the log too — the same reason the lost removal does: this is
    /// the branch a person would be attaching a log to. Counts and outcomes
    /// only; nothing here names a file.
    func testALostRescanSaysSoInTheLog() async {
        let item = agent("com.vendor.updater")
        let wire = LeftoversWire(items: [item])
        let model = LeftoversViewModel(vm: ModuleViewModel(transport: wire))
        await model.scan()
        wire.answers(.nothing)
        await model.scan()

        XCTAssertTrue(model.scanReplyLost, "precondition: the reply really was lost")
        XCTAssertTrue(logged.contains { $0.contains("scan reply lost") },
                      "a scan whose reply never came wrote nothing to the log: \(logged)")
        XCTAssertFalse(logged.contains { $0.contains(item.identifier) },
                       "and the line must not name the software: \(logged)")
    }

    /// **The first scan of a session going unanswered names no previous list.**
    /// The page is still on its invitation there.
    func testAFirstScanThatWasLostDrawsNoSentenceAboutAPreviousList() async {
        let wire = LeftoversWire(items: [agent("com.vendor.updater")], answering: .nothing)
        let model = LeftoversViewModel(vm: ModuleViewModel(transport: wire))

        await model.scan()

        XCTAssertTrue(model.scanReplyLost, "precondition: the only scan was lost")
        XCTAssertFalse(model.scanned, "precondition: no list has ever been drawn")
        XCTAssertNil(LeftoversSilence.note(removalUnanswered: model.replyLost,
                                           rescanUnanswered: model.scanReplyLost,
                                           scanned: model.scanned))
    }

    // MARK: - Where the two silences meet

    /// A removal nobody answered, whose rescan was not answered either: one
    /// sentence, and it is the removal's — carrying the fact that the list is
    /// from before the press.
    func testARemovalAndItsRescanBothLostDrawOneSentence() async {
        let item = agent("com.vendor.updater")
        let wire = LeftoversWire(items: [item])
        let model = LeftoversViewModel(vm: ModuleViewModel(transport: wire))
        await model.scan()
        model.selected = [item.path]

        wire.answers(.nothing)
        await model.removeSelected()

        XCTAssertTrue(model.replyLost, "precondition: the removal's reply was lost")
        XCTAssertTrue(model.scanReplyLost, "precondition: the rescan it made was lost too")
        let note = LeftoversSilence.note(removalUnanswered: model.replyLost,
                                         rescanUnanswered: model.scanReplyLost,
                                         scanned: model.scanned)
        XCTAssertEqual(note, .removalAndListLost)
        XCTAssertEqual(LeftoversSettingsPage.silenceOutcome(note)?.verdict, .unansweredStaleList, """
            the report promises «the list above shows where the files are now» over a list \
            nothing has refreshed since before the press.
            """)
    }

    /// And the round the existing sentence was written for: the removal's reply
    /// was lost and the rescan came back, so the list under it really is where
    /// the files are now. Silent for `trash` and answering for `scan` — the state
    /// every working retry passes through, and one the wire could not be in until
    /// it could be told which command to lose.
    func testARemovalWhoseRescanAnsweredKeepsTheSentenceItWasWrittenFor() async {
        let item = agent("com.vendor.updater")
        let wire = LeftoversWire(items: [item])
        let model = LeftoversViewModel(vm: ModuleViewModel(transport: wire))
        await model.scan()
        model.selected = [item.path]

        wire.answers(.nothing, to: .trash)
        wire.setItems([])
        await model.removeSelected()

        XCTAssertTrue(model.replyLost, "precondition: the removal's reply was lost")
        XCTAssertFalse(model.scanReplyLost, "precondition: and its rescan answered")
        XCTAssertTrue(model.items.isEmpty, "precondition: the rescan's list is the one on screen")
        let note = LeftoversSilence.note(removalUnanswered: model.replyLost,
                                         rescanUnanswered: model.scanReplyLost,
                                         scanned: model.scanned)
        XCTAssertEqual(note, .removalLost)
        XCTAssertEqual(LeftoversSettingsPage.silenceOutcome(note)?.verdict, .unanswered)
    }
}
