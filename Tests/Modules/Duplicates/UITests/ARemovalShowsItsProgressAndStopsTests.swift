import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// A removal a person can watch and stop, from the page's side of the wire.
///
/// The engine emits a tick per verified pair and obeys `stopRemoval` between
/// files — `ARemovalCanBeWatchedAndStoppedTests` proves that. This proves the
/// page's half: the event reaches the model, the Stop press reaches the wire,
/// and a stopped removal is a named outcome on screen rather than zeroes the
/// verdict reads as «nothing happened».
///
/// Until `DuplicatesWire` could emit, every fake's `events` was an empty
/// stream, so the progress branch the busy screen draws was exercised by
/// nothing — a state no test in this target could write down.
@MainActor
final class ARemovalShowsItsProgressAndStopsTests: XCTestCase {

    private var survivor: String { "\(home)/Downloads/keep.bin" }
    private var extra: String { "\(home)/Downloads/extra.bin" }

    private var group: DuplicateGroup {
        DuplicateGroup(copies: [.init(path: survivor, bytes: 9_000_000),
                                .init(path: extra, bytes: 9_000_000)])
    }

    // MARK: - The progress event reaches the page

    func testAProgressEventReachesTheModel() async {
        let wire = DuplicatesWire(groups: [group])
        let dvm = await searchedModel(over: wire)

        wire.emits(DuplicateProgress(candidates: 4, hashed: 1))
        for _ in 0..<1000 where dvm.progress == nil { await Task.yield() }

        XCTAssertEqual(dvm.progress?.hashed, 1,
                       "the tick the engine emits never reaches what the page draws")
        XCTAssertEqual(dvm.progress?.candidates, 4)
    }

    /// The sentence the busy screen draws, per state and per language — the
    /// branch the page takes is this one function, so the page cannot choose a
    /// sentence these cases do not cover.
    func testTheBusyLineNamesTheTickWhenThereIsOne() {
        for language in AppLanguage.allCases {
            XCTAssertEqual(DupStr.busyLine(nil, language: language),
                           DupStr.searching(language: language))
            XCTAssertEqual(DupStr.busyLine(DuplicateProgress(candidates: 0, hashed: 0),
                                           language: language),
                           DupStr.searching(language: language))
            XCTAssertEqual(DupStr.busyLine(DuplicateProgress(candidates: 4, hashed: 1),
                                           language: language),
                           DupStr.progressLine(1, 4, language: language))
        }
    }

    // MARK: - Stop

    /// Stop during a removal sends the engine its own command — not `cancel`,
    /// which reaches the search — and takes nothing off the screen: the reply
    /// decides what happened, not the press.
    func testStopSendsItsOwnCommandAndClaimsNothing() async {
        let wire = DuplicatesWire(groups: [group])
        let dvm = await searchedModel(over: wire)
        dvm.toggleBasket(extra)
        wire.answers(.park, to: .trash)
        let removal = Task { await dvm.emptyBasket() }
        for _ in 0..<1000 where wire.parkedCount < 1 { await Task.yield() }
        XCTAssertTrue(dvm.busy, "precondition: the removal is really in flight")

        dvm.stopRemoval()
        for _ in 0..<1000 where !wire.commands.contains(.stopRemoval) { await Task.yield() }

        XCTAssertTrue(wire.commands.contains(.stopRemoval))
        XCTAssertFalse(wire.commands.contains(.cancel),
                       "stopping a removal silently cancelled the search command too")
        XCTAssertTrue(dvm.busy, "the press claimed the removal was over before the reply said so")
        XCTAssertEqual(dvm.basket, [extra])

        wire.releaseParked()
        await removal.value
    }

    /// A reply that says «stopped» is a named outcome: not a success, not a
    /// refusal and not silence — and the list keeps every row, because nothing
    /// moved.
    func testAStoppedRemovalIsANamedOutcomeOnScreen() async {
        let wire = DuplicatesWire(groups: [group],
                                  removal: DuplicateRemoval(removed: [], refused: [],
                                                            freedBytes: 0, cancelled: true))
        let dvm = await searchedModel(over: wire)
        dvm.toggleBasket(extra)

        await dvm.emptyBasket()

        XCTAssertTrue(dvm.removalStopped, "a stopped removal said nothing at all")
        XCTAssertNil(dvm.banner, "nothing moved, so there is no success to announce")
        XCTAssertFalse(dvm.replyLost)
        XCTAssertEqual(dvm.groups.count, 1, "the list lost rows no reply accounted for")
        XCTAssertEqual(dvm.basket, [extra], "the marks outlive a stop, like a refusal's")
    }

    /// What moved before the stop is still counted — the banner and the stop
    /// note are both true at once, which is the state the reply exists to carry.
    func testWhatMovedBeforeTheStopIsStillCounted() async {
        let wire = DuplicatesWire(groups: [group],
                                  removal: DuplicateRemoval(removed: [extra], refused: [],
                                                            freedBytes: 9_000_000,
                                                            cancelled: true))
        let dvm = await searchedModel(over: wire)
        dvm.toggleBasket(extra)

        await dvm.emptyBasket()

        XCTAssertTrue(dvm.removalStopped)
        XCTAssertEqual(dvm.removedCount, 1, "what had already moved was un-counted by the stop")
        XCTAssertNotNil(dvm.banner)
    }

    /// A removal that ran to the end never says «stopped» — the note is read
    /// off the reply, not off the press.
    func testARemovalThatRanToTheEndDoesNotSayStopped() async {
        let wire = DuplicatesWire(groups: [group],
                                  removal: DuplicateRemoval(removed: [extra], refused: [],
                                                            freedBytes: 9_000_000))
        let dvm = await searchedModel(over: wire)
        dvm.toggleBasket(extra)

        await dvm.emptyBasket()

        XCTAssertFalse(dvm.removalStopped)
        XCTAssertNotNil(dvm.banner)
    }

    // MARK: - The report clears like a report

    func testTheStopNoteClearsWithTheReport() async {
        let wire = DuplicatesWire(groups: [group],
                                  removal: DuplicateRemoval(removed: [], refused: [],
                                                            freedBytes: 0, cancelled: true))
        let dvm = await searchedModel(over: wire)
        dvm.toggleBasket(extra)
        await dvm.emptyBasket()
        XCTAssertTrue(dvm.removalStopped, "precondition: the note is up")

        dvm.dismissBanner()

        XCTAssertFalse(dvm.removalStopped)
    }

    func testANewSearchPutsTheStopNoteDown() async {
        let wire = DuplicatesWire(groups: [group],
                                  removal: DuplicateRemoval(removed: [], refused: [],
                                                            freedBytes: 0, cancelled: true))
        let dvm = await searchedModel(over: wire)
        dvm.toggleBasket(extra)
        await dvm.emptyBasket()
        XCTAssertTrue(dvm.removalStopped, "precondition: the note is up")

        dvm.search()
        for _ in 0..<1000 where dvm.phase != .result { await Task.yield() }

        XCTAssertFalse(dvm.removalStopped,
                       "a note about a press two lists ago outlived the search")
    }

    /// The tick belongs to the removal that made it: the next press must not
    /// open on the last one's «N of M».
    func testProgressDoesNotOutliveTheRemoval() async {
        let wire = DuplicatesWire(groups: [group])
        let dvm = await searchedModel(over: wire)
        dvm.toggleBasket(extra)
        wire.emits(DuplicateProgress(candidates: 2, hashed: 1))
        for _ in 0..<1000 where dvm.progress == nil { await Task.yield() }
        XCTAssertNotNil(dvm.progress, "precondition: a tick arrived")

        await dvm.emptyBasket()

        XCTAssertNil(dvm.progress, "the last removal's tick is drawn over the next one")
    }
}
