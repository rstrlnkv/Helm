import XCTest
import Module_Leftovers_Engine
@testable import Module_Leftovers_UI

/// A row ticked while the list showed everything, then hidden by switching the
/// filter back, is not sent to the Trash.
///
/// **Why this is a test.** The tick survives the filter: the row disappears,
/// `selected` keeps its path, and `removeSelected` once trashed it anyway
/// (`LeftoversViewModel.swift`, the comment in `removeSelected`; fixed in
/// `8fd559be`). Deleting something the person cannot see is the one thing this
/// module must not do. The in-use row is the one a hidden tick would put at
/// risk, so it is the one asserted on.
@MainActor
final class AHiddenTickNeverReachesTheTrashTests: XCTestCase {

    /// Records the paths `trash` is handed, and answers nothing was moved.
    private final class RecordingWork: LeftoversWork, @unchecked Sendable {
        private(set) var trashed: [[String]] = []
        let items: [StaleItem]
        init(items: [StaleItem]) { self.items = items }
        func scan() async -> [StaleItem] { items }
        func trash(_ paths: [String]) async -> LeftoversRemoval {
            trashed.append(paths)
            return LeftoversRemoval(removed: [], refused: [], freedBytes: 0)
        }
        func setDisabled(_ request: LeftoversToggle) async {}
    }

    private let orphaned = StaleItem(path: "/tmp/orphaned.plist", identifier: "com.acme.orphaned",
                                     kind: .launchAgent, sizeBytes: 4_096, status: .orphaned)
    private let inUse = StaleItem(path: "/tmp/in-use.plist", identifier: "com.acme.inuse",
                                  kind: .launchAgent, sizeBytes: 8_192, status: .inUse)

    /// The control: a tick on a row that is shown is sent, so the absence below
    /// is not a `trash` that never runs.
    func testAVisibleTickIsSent() async {
        let work = RecordingWork(items: [orphaned, inUse])
        let model = LeftoversViewModel(work: work)
        model.showAll = true
        await model.scan()
        model.selected = [orphaned.path, inUse.path]

        await model.removeSelected()

        XCTAssertEqual(work.trashed.flatMap { $0 }.sorted(), [inUse.path, orphaned.path])
    }

    func testAHiddenTickIsNotSent() async {
        let work = RecordingWork(items: [orphaned, inUse])
        let model = LeftoversViewModel(work: work)
        model.showAll = true
        await model.scan()
        model.selected = [orphaned.path, inUse.path]
        model.showAll = false

        await model.removeSelected()

        XCTAssertEqual(work.trashed, [[orphaned.path]],
                       "a row the list no longer shows went to the Trash with the rest")
    }

    /// Nothing ticked is nothing sent: the press must not reach `trash` with an
    /// empty list, which would still run a removal and replace the banner.
    func testNothingTickedSendsNothing() async {
        let work = RecordingWork(items: [orphaned, inUse])
        let model = LeftoversViewModel(work: work)
        await model.scan()

        await model.removeSelected()

        XCTAssertEqual(work.trashed, [])
    }
}
