import AppKit
import SwiftUI
import XCTest
import HelmTestSupport
import HelmContract
import HelmRuntime
import HelmUI
import Module_Disk_Engine
@testable import Module_Disk_UI

/// What a tick does while a removal is still in flight.
///
/// The basket is what the reply is about: `emptyBasket` sends the paths, waits,
/// and then writes `basket = []`. So a row ticked in between was **accepted and
/// then discarded** — never sent, never refused, never mentioned. Small in bytes
/// and exactly the wrong shape in trust, in a flow whose whole subject is
/// deletion: the app quietly un-picks what somebody picked.
///
/// `OneRemovalAtATimeEverywhereTests` cannot see it. That scan looks for
/// `guard !busy` in the four trashing view models and finds one — in
/// `emptyBasket`, which is the other method. ARCHITECTURE.md § One removal at a
/// time states the rule this breaks in a sentence about both halves: «The model
/// refuses; the page dims. Both, or neither is reliable.»
///
/// Every case here needs a removal that is *running*, which is a state
/// `HeldTransport` could not be in until it was given `holdTrash()`: a fake that
/// answers on the spot releases the gate before the call it is gating returns,
/// so a test built on one passes whether or not the guard exists.
@MainActor
final class TheBasketHoldsStillUnderARemovalTests: XCTestCase {

    private let sub = "/Volumes/Big/Sub"
    private let other = "/Volumes/Big/Other"

    private func tree() -> ScanResult {
        ScanResult(root: folder("/Volumes/Big", bytes: 900,
                                children: [folder(sub, bytes: 600),
                                           folder(other, bytes: 200)]),
                   freeBytes: 100, filesScanned: 10, seconds: 1)
    }

    /// A scanned volume with one folder ticked and a removal parked mid-flight.
    private func removing(_ transport: HeldTransport) async -> DiskViewModel {
        transport.holdTrash()
        transport.answerTrash(with: DiskRemoval(removed: [sub], refused: [], freedBytes: 600))
        let dvm = DiskViewModel(vm: ModuleViewModel(transport: transport),
                                store: ScanStore(directory: scratchDirectory("disk-busy")))
        Task { await dvm.scan(path: "/Volumes/Big") }
        await untilParked(transport, count: 1)
        transport.release(0, with: tree())
        await settle()
        dvm.toggleBasket(folder(sub, bytes: 600))
        XCTAssertEqual(dvm.basket.map(\.path), [sub], "precondition: one folder is ticked")

        Task { await dvm.emptyBasket() }
        await untilTrashing(transport)
        XCTAssertTrue(dvm.busy, "precondition: the removal is in flight")
        return dvm
    }

    // MARK: - The model refuses

    /// The finding. Before the guard the model accepted the second row — basket
    /// 2 — and the reply then emptied the basket over it: the folder is still on
    /// the ring and nothing ever asked for it.
    func testARowTickedWhileARemovalRunsIsNotTakenAndThrownAway() async {
        let transport = HeldTransport()
        let dvm = await removing(transport)

        dvm.toggleBasket(folder(other, bytes: 200))

        XCTAssertEqual(dvm.basket.map(\.path), [sub], """
            the basket took a row that the reply about to land is not about: \
            \(dvm.basket.map(\.path)). It is cleared wholesale when the answer comes back, \
            so this folder is dropped without being sent and without being mentioned.
            """)
        transport.releaseTrash()
        await settle()
    }

    /// The same guard from the other side, and it is not a lesser case: the bar's
    /// menu unticks by calling the same method, so a row taken *out* mid-flight
    /// leaves the person told that something they had just withdrawn was removed.
    func testARowUntickedWhileARemovalRunsStaysInTheBatchItWasSentIn() async {
        let transport = HeldTransport()
        let dvm = await removing(transport)

        dvm.toggleBasket(folder(sub, bytes: 600))

        XCTAssertEqual(dvm.basket.map(\.path), [sub],
                       "the basket lost the row the removal in flight is about")
        transport.releaseTrash()
        await settle()
    }

    /// The control, and the reason the two above are about a removal rather than
    /// about the basket: once the answer is in, the basket is a basket again.
    /// Without this a guard of «never» would pass both of them.
    func testTheBasketTakesRowsAgainOnceTheReplyLands() async {
        let transport = HeldTransport()
        let dvm = await removing(transport)
        transport.releaseTrash()
        await settle()
        XCTAssertFalse(dvm.busy, "precondition: the removal is over")

        dvm.toggleBasket(folder(other, bytes: 200))

        XCTAssertEqual(dvm.basket.map(\.path), [other],
                       "the guard outlived the removal it belongs to")
    }

    /// And the batch is the one that was sent: nothing added in the meantime got
    /// in, and nothing removed got out. Read off the wire rather than off the
    /// basket, because the wire is what the engine acts on.
    func testTheEngineIsHandedExactlyWhatWasTickedWhenThePressHappened() async {
        let transport = HeldTransport()
        let dvm = await removing(transport)
        dvm.toggleBasket(folder(other, bytes: 200))
        transport.releaseTrash()
        await settle()

        XCTAssertEqual(transport.trashRequests, [[sub]],
                       "the engine was handed a different batch from the one consented to")
    }

    // MARK: - And the page dims

    /// «The model refuses; the page dims. Both, or neither is reliable.» A model
    /// that refuses under a button that is still live is a press that does
    /// nothing at all, which is worse than the discard it replaced.
    ///
    /// Read off the drawing, not off the source: `.disabled` leaves no view to
    /// ask, and what a person sees is ink. The list is the whole reading — the
    /// ring is not drawn at this width (`DiskLayout.showsRing`) — and the two
    /// mounts hold the same tree with the same row ticked, so the mark buttons
    /// are the only thing in them that can differ.
    ///
    /// **Two mounts, not one read twice.** Reading the same mount before and
    /// after the reply compares two different pages: the answer prunes the tree
    /// and empties the basket, so the second reading is of a shorter list. It
    /// measured *more* ink busy than idle, which is a difference about the rows
    /// that had gone rather than about the button.
    func testTheMarkButtonGoesDimWhileARemovalRuns() async throws {
        for appearance in RenderedInk.bothAppearances {
            let atRest = await mountedRows(busy: false, appearance: appearance)
            defer { atRest.mount.drop() }
            let idle = try XCTUnwrap(atRest.mount.settledInk(), "the list was not drawn")
            XCTAssertGreaterThan(idle, 0, "precondition: the rows drew something at all")

            let running = await mountedRows(busy: true, appearance: appearance)
            defer { running.mount.drop() }
            XCTAssertTrue(running.model.busy, "precondition: the removal is in flight")
            let busy = try XCTUnwrap(running.mount.settledInk())

            XCTAssertLessThan(busy, idle, """
                the rows are drawn identically while a removal runs, in \
                \(RenderedInk.label(of: appearance)): the mark button is live under a press \
                the model now refuses, so pressing it does nothing and says nothing.
                """)
            running.transport.releaseTrash()
            await settle()
        }
    }

    /// A mounted page and what it was built on, kept together so the removal can
    /// be released afterwards — a batch left parked never finishes the task
    /// waiting on it.
    private struct Rows {
        let mount: MountedRender
        let transport: HeldTransport
        let model: DiskViewModel
    }

    /// The same page in the two states, each on a transport of its own.
    private func mountedRows(busy: Bool, appearance: NSAppearance.Name) async -> Rows {
        let transport = HeldTransport()
        let dvm = busy ? await removing(transport) : await ticked(transport)
        let mount = MountedRender(DiskResultView(dvm: dvm, hovered: .constant(nil))
            .environment(\.helmGrants, HelmGrants(accessibility: .granted, fullDisk: .granted)),
                                  width: 500, height: 400, appearance: appearance)
        return Rows(mount: mount, transport: transport, model: dvm)
    }

    /// The scanned volume with the same row ticked, and no removal started.
    private func ticked(_ transport: HeldTransport) async -> DiskViewModel {
        let dvm = DiskViewModel(vm: ModuleViewModel(transport: transport),
                                store: ScanStore(directory: scratchDirectory("disk-idle")))
        Task { await dvm.scan(path: "/Volumes/Big") }
        await untilParked(transport, count: 1)
        transport.release(0, with: tree())
        await settle()
        dvm.toggleBasket(folder(sub, bytes: 600))
        return dvm
    }
}
