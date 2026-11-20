import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// A changed grid cuts the same order into other pages and writes nothing: the layout stores order, not pages. A cell's address
/// is `page * capacity + slot`, so a lift held across the change ends first.
@MainActor final class ARegridRepagesAndWritesNothingTests: XCTestCase {
    private let manual = LaunchpadGridSettings(automatic: false, rows: 2, columns: 3, iconSize: 80)

    private func rig() -> LiftRig {
        let ids = (0..<30).map { String(format: "app%02d", $0) }
        let layout = LaunchpadLayout(items: ids[0..<4].map { .app($0) } + [.pageBreak, .folder(.init(id: UUID(), name: "F", apps: [ids[4], ids[5]]))]
            + ids[6...].map { .app($0) })
        return LiftRig(self, apps: ids, layout: layout)
    }

    private func flat(_ state: LaunchpadScreenState) -> [String] { state.pages.flatMap { $0.map(\.id) } }

    func testAnotherGridCutsTheSameOrderIntoOtherPagesAndWritesNothing() async throws {
        let r = rig()
        let (pages, order, capacity) = (r.state.pages, flat(r.state), r.g.capacity)
        let bytes = try Data(contentsOf: r.layoutFile)
        let stored = r.engine.read().layout

        r.state.regrid(manual)

        // The subject happened: the capacity and the pages are not the ones the window opened with.
        XCTAssertNotEqual(r.state.geometry.capacity, capacity)
        XCTAssertNotEqual(r.state.pages.count, pages.count)
        XCTAssertEqual(flat(r.state), order, "the same tiles in the same order")
        XCTAssertTrue(r.state.pages.allSatisfy { $0.count <= r.state.geometry.capacity })
        XCTAssertEqual(r.state.pages[0].map(\.id), ["app00", "app01", "app02", "app03"], "the stored break still ends a page")
        XCTAssertEqual(r.state.pages[1].count, r.state.geometry.capacity, "and the next page is cut by what a page holds")

        r.state.regrid(.standard)
        await grace()   // a write issued from the change runs on a task: look after it had its chance
        XCTAssertEqual(r.state.pages, pages, "back to the first grid, back to the first pages")

        XCTAssertEqual(try Data(contentsOf: r.layoutFile), bytes, "the layout file was not written")
        XCTAssertEqual(r.engine.read().layout, stored)
        XCTAssertTrue(r.placed.isEmpty)
    }

    func testAGridChangedMidLiftEndsTheLiftAndWritesNothing() async throws {
        let r = rig()
        let bytes = try Data(contentsOf: r.layoutFile)
        r.lift(0)
        XCTAssertNotNil(r.state.lift, "the subject: a tile is carried")
        r.state.regrid(manual)
        XCTAssertNil(r.state.lift)
        await grace()
        XCTAssertFalse(flat(r.state).contains(LaunchpadEntry.gap.id), "no gap is left behind")
        XCTAssertEqual(try Data(contentsOf: r.layoutFile), bytes)
        XCTAssertTrue(r.placed.isEmpty)
    }
}
