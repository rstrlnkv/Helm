import HelmContract
import HelmRuntime
import HelmUI
import XCTest
import Module_Leftovers_Engine
@testable import Module_Leftovers_UI

/// The removal nobody answered, said out loud.
///
/// `AnUnansweredRequestIsNotAnAnswerTests` closed the half that mattered first:
/// a lost reply must not *claim* that anything moved. What it left is a screen
/// that says nothing at all — the report is cleared, so
/// `HelmRemovalOutcome.verdict(removed: 0, failed: 0)` is `.silent` and the row
/// draws `EmptyView`. The person pressed a destructive button, waited, and the
/// app has no comment; and the rescan underneath has quietly moved the list.
///
/// So there is a fourth verdict. It claims nothing moved, claims nothing stayed,
/// and calls nothing a failure — no warning triangle, no list of refusals, no
/// Grant button. It says what is true: the answer was lost, and the list above
/// is where the files are now.
@MainActor
final class ARemovalNobodyAnsweredSaysSoTests: XCTestCase {

    /// Both silences the wire has. Empty `Data` is the one this module reaches in
    /// the tree; a throw is what `EngineTransport.send` is declared to do, and
    /// `TransportClient` folds both to the same nil.
    private static let silences: [LeftoversWire.Answer] = [.refuse, .nothing]

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

    /// A batch whose reply was lost says so, and the three fields that would make
    /// a claim are empty beside it.
    func testALostReplyIsSaidRatherThanDrawnAsNothing() async {
        for silence in Self.silences {
            let item = agent("com.vendor.updater")
            let wire = LeftoversWire(items: [item])
            let model = LeftoversViewModel(vm: ModuleViewModel(transport: wire))
            await model.scan()
            model.selected = [item.path]

            wire.answers(silence)
            await model.removeSelected()

            XCTAssertTrue(wire.commands.contains(.trash),
                          "precondition: the batch really was sent (\(silence))")
            XCTAssertTrue(model.replyLost, """
                a removal the engine never answered (\(silence)) leaves the page with nothing to \
                say: `banner` is nil, there are no refusals, and the outcome row draws \
                `EmptyView` over files that are still where they were.
                """)
            XCTAssertNil(model.banner, "and it must not claim anything moved (\(silence))")
            XCTAssertTrue(model.failures.isEmpty,
                          "nor call anything a failure (\(silence))")
            XCTAssertEqual(model.removedCount, 0, "nor count anything moved (\(silence))")
        }
    }

    /// And an answered removal does not say the answer was lost — the half that
    /// keeps the flag from being always true, which is a report nobody can act on
    /// standing over every successful batch.
    func testAnAnsweredRemovalDoesNotSayTheReplyWasLost() async {
        let item = agent("com.vendor.updater")
        let wire = LeftoversWire(items: [item],
                                 removal: LeftoversRemoval(removed: [item.path], refused: [],
                                                           freedBytes: 4_096))
        let model = LeftoversViewModel(vm: ModuleViewModel(transport: wire))
        await model.scan()
        model.selected = [item.path]

        await model.removeSelected()

        XCTAssertTrue(wire.commands.contains(.trash), "precondition: the batch was sent")
        XCTAssertEqual(model.removedCount, 1, "precondition: the reply arrived and was read")
        XCTAssertFalse(model.replyLost,
                       "a removal that was answered reports a lost answer as well")
        XCTAssertNotNil(model.banner, "and the sentence about what moved is still drawn")
    }

    /// And it reaches the log, which was the one branch in this module that
    /// reached the screen without reaching the file a person attaches to a bug
    /// report. Counts and outcomes only — nothing here names a file.
    func testALostReplySaysSoInTheLogToo() async {
        let item = agent("com.vendor.updater")
        let wire = LeftoversWire(items: [item])
        let model = LeftoversViewModel(vm: ModuleViewModel(transport: wire))
        await model.scan()
        model.selected = [item.path]

        wire.answers(.nothing)
        await model.removeSelected()

        XCTAssertTrue(model.replyLost, "precondition: the reply really was lost")
        XCTAssertTrue(logged.contains { $0.contains("trash reply lost") }, """
            a removal whose reply never came wrote nothing to the log, so the one place a \
            person could look afterwards has no record that it happened: \(logged)
            """)
        XCTAssertFalse(logged.contains { $0.contains(item.identifier) },
                       "and the line must not name the software: \(logged)")
    }

    /// A second batch that *is* answered clears the lost-reply report, so the
    /// sentence does not outlive the round it was about.
    func testAnAnsweredRetryTakesTheLostReplyReportDown() async {
        let item = agent("com.vendor.updater")
        let wire = LeftoversWire(items: [item],
                                 removal: LeftoversRemoval(removed: [item.path], refused: [],
                                                           freedBytes: 4_096))
        let model = LeftoversViewModel(vm: ModuleViewModel(transport: wire))
        await model.scan()
        model.selected = [item.path]
        wire.answers(.nothing)
        await model.removeSelected()
        XCTAssertTrue(model.replyLost, "precondition: the first round's reply was lost")

        wire.answers(.reply)
        model.selected = [item.path]
        await model.removeSelected()

        XCTAssertFalse(model.replyLost,
                       "the sentence about a lost answer sits over a batch that was answered")
    }
}
