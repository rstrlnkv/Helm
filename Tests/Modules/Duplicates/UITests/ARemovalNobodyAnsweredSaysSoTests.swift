import HelmContract
import HelmRuntime
import HelmUI
import XCTest
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// The removal nobody answered, said out loud — the fourth module with the same
/// nil.
///
/// Measured before this existed: the page after a press whose reply was empty
/// `Data` was pixel-identical to the page before it, and a *second* press
/// changed nothing either — `banner` nil, no refusals, `removedCount` 0, so
/// `HelmRemovalOutcome.verdict(removed: 0, failed: 0)` is `.silent` and the row
/// draws `EmptyView`. The person marked copies across a list that took minutes
/// of hashing, pressed a destructive button, and the app had no comment.
///
/// What this module keeps that Disk did not is the basket and the groups: they
/// survive the silence, so nothing is lost. The one thing that is true is that
/// the person does not know what moved — and because the list is only ever
/// pruned from the reply that never came, it is also **stale**, which is why the
/// page draws `unansweredWithStaleList` rather than the plain sentence that ends
/// by pointing at the list.
@MainActor
final class ARemovalNobodyAnsweredSaysSoTests: XCTestCase {

    /// Both silences the wire has. Empty `Data` is the one this module reaches in
    /// the tree; a throw is what `EngineTransport.send` is declared to do, and
    /// `TransportClient` folds both to the same nil.
    private static let silences: [DuplicatesWire.Answer] = [.refuse, .nothing]

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
            .filter { $0.category == DuplicatesEngine.moduleID }
            .map(\.message)
    }

    private var survivor: String { "\(home)/Downloads/keep.bin" }
    private var extra: String { "\(home)/Downloads/extra.bin" }

    private var group: DuplicateGroup {
        DuplicateGroup(copies: [.init(path: survivor, bytes: 4_000_000),
                                .init(path: extra, bytes: 4_000_000)])
    }

    /// A removal whose reply was lost says so, and the three fields that would
    /// make a claim are empty beside it.
    func testALostReplyIsSaidRatherThanDrawnAsNothing() async {
        for silence in Self.silences {
            let wire = DuplicatesWire(groups: [group])
            let dvm = await searchedModel(over: wire)
            dvm.toggleBasket(extra)
            XCTAssertEqual(dvm.basket, [extra], "precondition: the copy is marked (\(silence))")

            wire.answers(silence)
            await dvm.emptyBasket()

            XCTAssertTrue(wire.commands.contains(.trash),
                          "precondition: the removal really was sent (\(silence))")
            XCTAssertTrue(dvm.replyLost, """
                a removal the engine never answered (\(silence)) leaves the page with nothing to \
                say: no banner, no refusal, no change to the list — the same screen, twice.
                """)
            XCTAssertNil(dvm.banner, "and it must not claim anything moved (\(silence))")
            XCTAssertTrue(dvm.failures.isEmpty, "nor call anything a failure (\(silence))")
            XCTAssertEqual(dvm.removedCount, 0, "nor count anything moved (\(silence))")
        }
    }

    /// **The basket survives**, and so does the list. There is nothing to rescan
    /// here — the groups are pruned from the reply and no reply came — so the one
    /// safe thing to do with a selection that took minutes to make is keep it.
    func testALostReplyKeepsTheSelectionAndTheList() async {
        let wire = DuplicatesWire(groups: [group])
        let dvm = await searchedModel(over: wire)
        XCTAssertEqual(dvm.groups.count, 1, "precondition: the search answered")
        dvm.toggleBasket(extra)
        wire.answers(.nothing, to: .trash)

        await dvm.emptyBasket()

        XCTAssertTrue(dvm.replyLost, "precondition: the reply really was lost")
        XCTAssertEqual(dvm.basket, [extra], "the marked copy was dropped from the basket")
        XCTAssertEqual(dvm.groups.count, 1, "the list was pruned on the strength of no answer")
    }

    /// And it reaches the log, which is the file a person attaches to a report.
    /// Counts and outcomes are free; nothing here names a file.
    func testALostReplySaysSoInTheLogToo() async {
        let wire = DuplicatesWire(groups: [group])
        let dvm = await searchedModel(over: wire)
        dvm.toggleBasket(extra)
        wire.answers(.nothing, to: .trash)

        await dvm.emptyBasket()

        XCTAssertTrue(dvm.replyLost, "precondition: the reply really was lost")
        XCTAssertTrue(logged.contains { $0.contains("trash reply lost") }, """
            a removal whose reply never came wrote nothing to the log, so the one place a person \
            could look afterwards has no record that it happened: \(logged)
            """)
        XCTAssertFalse(logged.contains { $0.contains("extra.bin") },
                       "and the line must not name the file: \(logged)")
    }

    /// An answered removal does not say the answer was lost — the half that keeps
    /// the flag from being true for ever, standing over every batch that worked.
    func testAnAnsweredRemovalDoesNotSayTheReplyWasLost() async {
        let wire = DuplicatesWire(groups: [group],
                                  removal: DuplicateRemoval(removed: [extra], refused: [],
                                                            freedBytes: 4_000_000))
        let dvm = await searchedModel(over: wire)
        dvm.toggleBasket(extra)
        wire.answers(.nothing, to: .trash)
        await dvm.emptyBasket()
        XCTAssertTrue(dvm.replyLost, "precondition: the first round's reply was lost")

        wire.answers(.reply, to: .trash)
        XCTAssertEqual(dvm.basket, [extra], "precondition: the retry has something to send")
        await dvm.emptyBasket()

        XCTAssertEqual(dvm.removedCount, 1, "precondition: the reply arrived and was read")
        XCTAssertFalse(dvm.replyLost,
                       "the sentence about a lost answer sits over a batch that was answered")
    }

    /// And a fresh search takes it down: it is a report about a press, and the
    /// press it was about is two screens ago.
    func testASearchTakesTheLostReplyReportDown() async {
        let wire = DuplicatesWire(groups: [group])
        let dvm = await searchedModel(over: wire)
        dvm.toggleBasket(extra)
        wire.answers(.nothing, to: .trash)
        await dvm.emptyBasket()
        XCTAssertTrue(dvm.replyLost, "precondition: the reply was lost")

        dvm.search()
        for _ in 0..<200 where dvm.phase != .result { await Task.yield() }

        XCTAssertEqual(dvm.phase, .result, "precondition: the search came back")
        XCTAssertFalse(dvm.replyLost, "the report outlived the list it was about")
    }

    /// Closing the report takes it down too, the way it takes the banner and the
    /// refusals down: the four fields are one report.
    func testCloseTakesTheLostReplyReportDown() async {
        let wire = DuplicatesWire(groups: [group])
        let dvm = await searchedModel(over: wire)
        dvm.toggleBasket(extra)
        wire.answers(.nothing, to: .trash)
        await dvm.emptyBasket()
        XCTAssertTrue(dvm.replyLost, "precondition: the reply was lost")

        dvm.dismissBanner()

        XCTAssertFalse(dvm.replyLost)
    }
}
