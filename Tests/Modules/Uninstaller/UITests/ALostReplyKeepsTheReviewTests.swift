import HelmContract
import HelmRuntime
import HelmUI
import XCTest
import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// **A removal nobody answered was reported as a removal that worked — and it
/// took the review down with it.**
///
/// Measured with the engine answering `trashPaths` with empty `Data`: the page
/// ended holding «Moved to the Trash — 0 bytes», no failures, `step` back to
/// `.pick`, and `checked`, `groups` and `selectedLeftovers` all cleared. So the
/// person is told their applications are in the Trash — they are not — and the
/// scan of every ticked app, which this view model's own doc calls the thing
/// «nothing in the app can produce a second time», is thrown away on the
/// strength of an answer that never came.
///
/// The repair is the one Leftovers took: a lost reply is not a count and must
/// not be expressible as one. `HelmRemovalOutcome.unanswered` is what says it,
/// and the review stays, because the one thing that is true is that nobody
/// knows what moved.
@MainActor
final class ALostReplyKeepsTheReviewTests: XCTestCase {

    /// Both silences the wire has. Empty `Data` is the one this module reaches in
    /// the tree; a throw is what `EngineTransport.send` is declared to do, and
    /// `TransportClient` folds both to the same nil.
    private static let silences: [UninstallerWire.Answer] = [.refuse, .nothing]

    private let tool = InstalledApp(name: "Tool", bundleID: "com.acme.tool",
                                    path: "/Applications/Tool.app", sizeBytes: 4_096)

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
            .filter { $0.category == UninstallerEngine.moduleID }
            .map(\.message)
    }

    /// A leftover the scan found for the app, so the review has something in it
    /// worth losing.
    private var cache: Leftover {
        Leftover(path: "\(NSHomeDirectory())/Library/Caches/com.acme.tool",
                 kind: .caches, sizeBytes: 2_048, matchedByName: false)
    }

    private func reviewed(_ wire: UninstallerWire) async -> UninstallerViewModel {
        let model = UninstallerViewModel(vm: ModuleViewModel(transport: wire))
        await model.loadAppsIfNeeded()
        model.setChecked(tool.bundleID, true)
        await model.prepareReview()
        return model
    }

    private func wire(answering answer: UninstallerWire.Answer = .reply) -> UninstallerWire {
        UninstallerWire(
            apps: [tool],
            scans: [tool.bundleID: ScanResult(bundleID: tool.bundleID, appPath: tool.path,
                                              appSizeBytes: 0, leftovers: [cache],
                                              runningNow: false)],
            removal: UninstallResult(trashed: [tool.path, cache.path], freedBytes: 6_144),
            answering: answer)
    }

    // MARK: -

    /// The claim: nothing may say the applications are in the Trash.
    func testALostReplyDoesNotSayTheAppsAreInTheTrash() async {
        for silence in Self.silences {
            let wire = wire()
            let model = await reviewed(wire)
            XCTAssertEqual(model.groups.count, 1, "precondition: the review is up (\(silence))")

            wire.answers(silence)
            await model.removeSelection()

            XCTAssertTrue(wire.commands.contains(.trashPaths),
                          "precondition: the batch really was sent (\(silence))")
            XCTAssertNil(model.resultBanner, """
                «\(model.resultBanner ?? "")» over a removal the engine never answered \
                (\(silence)): the apps are where they were
                """)
            XCTAssertTrue(model.replyLost,
                          "and the page has nothing at all to say about a destructive press "
                          + "it just made (\(silence))")
            XCTAssertTrue(model.failures.isEmpty,
                          "nor may it call anything a failure (\(silence))")
        }
    }

    /// And the review — the scan of every ticked app — survives it.
    func testALostReplyKeepsTheReviewItWasAbout() async {
        for silence in Self.silences {
            let wire = wire()
            let model = await reviewed(wire)
            let selected = model.selectedLeftovers

            wire.answers(silence)
            await model.removeSelection()

            XCTAssertEqual(model.step, .review,
                           "the page went back to the picker over an answer that never came "
                           + "(\(silence))")
            XCTAssertEqual(model.groups.map(\.app.bundleID), [tool.bundleID],
                           "a scan of every ticked app was thrown away (\(silence))")
            XCTAssertEqual(model.selectedLeftovers, selected,
                           "and the person's ticks with it (\(silence))")
            XCTAssertEqual(model.checked, [tool.bundleID],
                           "and what they had picked (\(silence))")
        }
    }

    /// What the report over the review says is that the list under it is where
    /// the files are now, so the list is read again — the removal may well have
    /// happened and only the reply been lost.
    func testALostReplyReadsTheReviewAgainSoWhatItSaysIsTrue() async {
        let wire = wire()
        let model = await reviewed(wire)
        XCTAssertEqual(model.selectedLeftovers.count, 1, "precondition: a leftover is ticked")

        // The removal did happen; only the answer went missing.
        wire.answers(.nothing, to: .trashPaths)
        wire.setScans([tool.bundleID: ScanResult(bundleID: tool.bundleID, appPath: tool.path,
                                                 appSizeBytes: 0, leftovers: [],
                                                 runningNow: false)])
        await model.removeSelection()

        XCTAssertTrue(model.replyLost, "precondition: the reply was lost")
        XCTAssertEqual(model.groups.flatMap(\.leftovers), [], """
            the report says «the list above shows where the files are now» over a list that \
            was not read again — the one thing this screen still promises after a lost reply
            """)
        XCTAssertTrue(model.selectedLeftovers.isEmpty,
                      "and a path that has gone is still ticked for the next press")
    }

    /// The other half of the same rescan, and the reason it cannot be a plain
    /// reload: a scan that is *also* unanswered must leave the review alone.
    /// Folded to `[]` it would report «this app left nothing behind», which on
    /// this screen reads as the removal having worked.
    func testAScanThatIsAlsoUnansweredLeavesTheReviewAsItWas() async {
        let wire = wire()
        let model = await reviewed(wire)
        let before = model.groups.flatMap(\.leftovers)

        wire.answers(.nothing)
        await model.removeSelection()

        XCTAssertTrue(wire.commands.filter { $0 == .scan }.count >= 2,
                      "precondition: the review really was read again")
        XCTAssertEqual(model.groups.flatMap(\.leftovers), before,
                       "an unanswered scan emptied the review and called it a clean app")
    }

    /// The half that keeps the report from standing over every removal: one that
    /// was answered says so.
    func testAnAnsweredRemovalDoesNotSayTheReplyWasLost() async {
        let wire = wire()
        let model = await reviewed(wire)

        await model.removeSelection()

        XCTAssertTrue(wire.commands.contains(.trashPaths), "precondition: the batch was sent")
        XCTAssertFalse(model.replyLost,
                       "a removal that was answered reports a lost answer as well")
        XCTAssertNotNil(model.resultBanner, "and the sentence about what moved is drawn")
        XCTAssertEqual(model.step, .pick, "and the flow moved on")
    }

    /// A second round that *is* answered takes the report down, so the sentence
    /// does not outlive the press it was about.
    func testAnAnsweredRetryTakesTheLostReplyReportDown() async {
        let wire = wire()
        let model = await reviewed(wire)
        wire.answers(.nothing)
        await model.removeSelection()
        XCTAssertTrue(model.replyLost, "precondition: the first round's reply was lost")

        wire.answers(.reply)
        await model.removeSelection()

        XCTAssertFalse(model.replyLost,
                       "the sentence about a lost answer sits over a batch that was answered")
    }

    /// A press with nothing to remove is not a removal that worked either. The
    /// engine answers an empty batch with «moved 0 items, 0 bytes», which is the
    /// same cheerful sentence read out of a different silence.
    func testAnEmptyBatchIsNotSentAndClaimsNothing() async {
        let wire = wire()
        let model = UninstallerViewModel(vm: ModuleViewModel(transport: wire))
        await model.loadAppsIfNeeded()

        await model.removeSelection()

        XCTAssertFalse(wire.commands.contains(.trashPaths),
                       "a batch of nothing was sent to the engine")
        XCTAssertNil(model.resultBanner, "and «\(model.resultBanner ?? "")» was drawn over it")
    }

    /// And it reaches the log, which is what a person attaches to a bug report.
    /// Counts and outcomes only — nothing here names an application.
    func testALostReplySaysSoInTheLogToo() async {
        let wire = wire()
        let model = await reviewed(wire)

        wire.answers(.nothing)
        await model.removeSelection()

        XCTAssertTrue(model.replyLost, "precondition: the reply really was lost")
        XCTAssertTrue(logged.contains { $0.contains("trash reply lost") }, """
            a removal whose reply never came wrote nothing to the log, so the one place a \
            person can look afterwards has no record that it happened: \(logged)
            """)
        XCTAssertFalse(logged.contains { $0.contains(tool.bundleID) },
                       "and the line must not name the software: \(logged)")
    }
}
