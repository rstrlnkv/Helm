import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// Turning app names off (or on) changes the cell's height and so the capacity. The window is open: the same order is cut again, the
/// choice and the page follow the tile, an open card stays, and the layout file is not written.
@MainActor final class AGridWithoutNamesRegridsWhereItWasTests: XCTestCase {
    private let folderID = UUID()
    /// Names off, on a grid of fewer rows: under Automatic the rows are five whatever the names, so a cell's height alone no longer changes the capacity,
    /// and this test is about the order being cut again at the new one.
    private var off: LaunchpadGridSettings { var s = LaunchpadGridSettings.standard; s.showNames = false; s.automatic = false; s.rows = 4; return s }

    private func rig(count: Int = 80, large: Bool = true) -> LiftRig {
        let ids = (0..<count).map { String(format: "app%02d", $0) }
        let layout = LaunchpadLayout(items: [.app(ids[0]), .app(ids[1]), .folder(.init(id: folderID, name: "F", apps: Array(ids[2..<8]), large: large))]
            + ids[8...].map { .app($0) })
        return LiftRig(self, apps: ids, layout: layout)
    }
    private func flat(_ s: LaunchpadScreenState) -> [String] { s.pages.flatMap { $0.map(\.id) } }

    func testTheChoiceOnTheLastPageSurvivesNamesOffAndOnAndNothingIsWritten() async throws {
        let r = rig()
        let bytes = try Data(contentsOf: r.layoutFile), order = flat(r.state), capacity = r.state.geometry.capacity
        for _ in 0..<(order.count) where r.state.page < r.state.pages.count - 1 || r.state.selection == nil { r.state.move(dx: 1, dy: 0) }
        r.state.move(dx: 1, dy: 0)
        let lastPage = r.state.pages.count - 1
        guard let chosen = r.state.selection else { return XCTFail("the subject: a tile is chosen") }
        let chosenID = flat(r.state)[chosen]
        XCTAssertEqual(r.state.page, lastPage, "the subject: on the last page")

        r.state.regrid(off)
        XCTAssertNotEqual(r.state.geometry.capacity, capacity, "the subject: the capacity changed")
        XCTAssertEqual(flat(r.state), order)
        XCTAssertEqual(flat(r.state)[r.state.selection ?? -1], chosenID, "still on the same tile")
        XCTAssertTrue(r.state.pages.indices.contains(r.state.page))
        XCTAssertTrue(r.state.pages[r.state.page].map(\.id).contains(chosenID) || r.state.pages[r.state.page].contains { entry in
            if case .folder(_, _, let apps, _) = entry { return apps.contains { $0.id == chosenID } }; return false }, "and on its page")

        r.state.regrid(.standard)
        XCTAssertEqual(flat(r.state)[r.state.selection ?? -1], chosenID)
        await grace()
        XCTAssertEqual(try Data(contentsOf: r.layoutFile), bytes, "the layout file was not written")
        XCTAssertTrue(r.placed.isEmpty)
    }

    func testAnOpenCardStaysOpenAndInsideTheWindowWhenNamesGoOff() {
        let r = rig()
        r.state.open(folder: folderID)
        r.state.move(dx: 1, dy: 0)
        r.state.regrid(off)
        XCTAssertEqual(r.state.openFolder, folderID)
        XCTAssertEqual(r.state.folderApps.count, 6)
        let card = LaunchpadSurface.Card(geometry: r.state.geometry, count: 6)
        XCTAssertTrue(CGRect(origin: .zero, size: r.state.geometry.size).contains(card.rect))
        XCTAssertTrue(r.state.selection.map { $0 < 6 } ?? true)
        XCTAssertFalse(r.state.geometry.names)
    }

    func testALargeFolderBlockIsAsHighAsTwoCellsAndStaysInsideItsCellsWithoutNames() {
        let g = LaunchpadGeometry.make(for: CGSize(width: 1280, height: 800), topSafe: 0, settings: off)
        XCTAssertFalse(g.names)
        // The block holds a mark, the gap, one line, the paddings: no more than two cells.
        XCTAssertLessThanOrEqual(g.largeMark + LaunchpadMetrics.cellChrome(names: false, scale: g.scale), 2 * g.cellHeight + 0.001)
        XCTAssertGreaterThan(g.largeMark, g.icon)
    }

    func testResetGridRestoresTheNamesAndWritesTheKey() {
        let r = LaunchpadRig(self, label: "names")
        var s = r.model.grid; s.showNames = false
        r.model.setGrid(s)
        XCTAssertFalse(LaunchpadGridSettings.read(from: r.model.store).showNames, "the subject: stored off")
        r.model.resetGrid()
        XCTAssertTrue(r.model.grid.showNames)
        XCTAssertTrue(LaunchpadGridSettings.read(from: r.model.store).showNames, "and stored on")
    }
}
