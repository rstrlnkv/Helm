import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// A removal a person can stop, from the page's side of the wire.
///
/// The engine obeys `stopRemoval` between files —
/// `ARemovalCanBeWatchedAndStoppedTests` proves that. This proves the page's
/// half: the Stop press reaches the wire as its own command, and the page claims
/// nothing until the reply says what happened.
@MainActor
final class ARemovalShowsItsProgressAndStopsTests: XCTestCase {

    private var survivor: String { "\(home)/Downloads/keep.bin" }
    private var extra: String { "\(home)/Downloads/extra.bin" }

    private var group: DuplicateGroup {
        DuplicateGroup(copies: [.init(path: survivor, bytes: 9_000_000),
                                .init(path: extra, bytes: 9_000_000)])
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
}
