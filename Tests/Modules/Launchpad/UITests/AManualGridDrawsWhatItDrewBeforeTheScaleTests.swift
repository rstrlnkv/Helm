import XCTest
import HelmRuntime
import HelmTestSupport
import HelmUI
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// Pass 22 changed the Automatic grid and left Manual alone: a Manual grid saved before it must draw the same numbers; the square pitch (a column as wide as a row is high) then moved the
/// numbers that follow the column: `cellWidth`, the icon where the width bound it, `largeMark`, the card, the grid's left edge. The oracle below is `LaunchpadGeometry.make`, `counts` and `fit`
/// as they were at base 9f1f1447 (the fixed `cellChrome`, side padding and offsets) with exactly those changed to the square pitch, written out here so the new code is compared with the
/// arithmetic and not with itself.
/// The multiplier's own ends and the regrid it causes while the window is open are checked at the bottom.
@MainActor final class AManualGridDrawsWhatItDrewBeforeTheScaleTests: XCTestCase {
    // MARK: The base's arithmetic

    private struct Old {
        let columns: Int, rows: Int, cellWidth: CGFloat, cellHeight: CGFloat, icon: CGFloat, gridTop: CGFloat, searchTop: CGFloat, largeMark: CGFloat, card: CGRect, gridLeft: CGFloat
    }

    private static func chrome(_ names: Bool) -> CGFloat { HelmSpace.s3 + (names ? 2 : 1) * 17 + 2 * HelmSpace.s3 }

    private static func old(_ size: CGSize, top topSafe: CGFloat, _ settings: LaunchpadGridSettings) -> Old {
        let usable = size.width.isFinite && size.height.isFinite && size.width >= 1 && size.height >= 1
        let screen = usable ? size : CGSize(width: 1280, height: 800)
        let top = topSafe.isFinite ? max(0, min(topSafe, screen.height / 4)) : 0
        let s = settings.normalized()
        let usableWidth = screen.width * (1 - 2 * 0.08)
        let searchTop = top + 28
        let gridStart = searchTop + 36 + 32
        let usableHeight = max(0, screen.height - gridStart - 64)
        let holds = max(2, Int(min(usableHeight / (24 + chrome(s.showNames)), 1000)))
        let columns = min(s.columns, max(3, Int(min(usableWidth / (24 + chrome(s.showNames)), 1000)))), rows = min(s.rows, holds)
        let icon = max(24, min(CGFloat(s.iconSize), usableWidth / CGFloat(columns) - chrome(s.showNames), usableHeight / CGFloat(rows) - chrome(s.showNames)))
        let cellHeight = icon + chrome(s.showNames)
        let cellWidth = cellHeight
        let gridTop = gridStart + max(0, usableHeight - CGFloat(rows) * cellHeight) / 2
        let large = max(0, 2 * cellHeight - chrome(s.showNames))
        let cardColumns = max(1, min(columns, columns - 1))
        let cardWidth = CGFloat(cardColumns) * cellWidth + 2 * HelmSpace.s6
        let cardHeight = CGFloat(max(1, rows - 1)) * cellHeight + 22 + HelmSpace.s5 + 2 * HelmSpace.s6
        let card = CGRect(x: (screen.width - cardWidth) / 2, y: (screen.height - cardHeight) / 2, width: cardWidth, height: cardHeight)
        return Old(columns: columns, rows: rows, cellWidth: cellWidth, cellHeight: cellHeight, icon: icon, gridTop: gridTop, searchTop: searchTop, largeMark: large, card: card,
                   gridLeft: (screen.width - CGFloat(columns) * cellWidth) / 2)
    }

    func testAManualGridDrawsTheNumbersBaseDrew() {
        let screens = [CGSize(width: 1280, height: 800), CGSize(width: 1440, height: 900), CGSize(width: 2560, height: 1440), CGSize(width: 1024, height: 640),
                       CGSize(width: 5120, height: 2880), CGSize(width: 640, height: 400), CGSize(width: 1080, height: 1920)]
        var compared = 0
        for size in screens {
            for top in [CGFloat(0), 24, 33] {
                for rows in [2, 4, 5, 8] {
                    for columns in [3, 7, 10] {
                        for icon in [48.0, 80, 128] {
                            for names in [true, false] {
                                var settings = LaunchpadGridSettings(automatic: false, rows: rows, columns: columns, iconSize: icon)
                                settings.showNames = names
                                // A multiplier left in the store from Automatic must change nothing under Manual.
                                settings.sizeMultiplier = 1.25
                                let g = LaunchpadGeometry.make(for: size, topSafe: top, settings: settings)
                                let o = Self.old(size, top: top, settings)
                                let tag = "\(size) top \(top) manual \(columns)x\(rows) icon \(icon) names \(names)"
                                XCTAssertEqual(g.columns, o.columns, tag); XCTAssertEqual(g.rows, o.rows, tag)
                                XCTAssertEqual(g.cellWidth, o.cellWidth, accuracy: 0.0001, tag); XCTAssertEqual(g.cellHeight, o.cellHeight, accuracy: 0.0001, tag)
                                XCTAssertEqual(g.icon, o.icon, accuracy: 0.0001, tag); XCTAssertEqual(g.gridTop, o.gridTop, accuracy: 0.0001, tag)
                                XCTAssertEqual(g.searchTop, o.searchTop, accuracy: 0.0001, tag); XCTAssertEqual(g.largeMark, o.largeMark, accuracy: 0.0001, tag)
                                XCTAssertEqual(g.gridLeft, o.gridLeft, accuracy: 0.0001, tag)
                                XCTAssertEqual(g.sideInset, o.gridLeft, accuracy: 0.0001, "the tabs begin where the grid does under Manual: \(tag)")
                                XCTAssertEqual(g.cellWidth, g.cellHeight, accuracy: 0.0001, tag)
                                XCTAssertEqual(g.dotsBottom, 28, tag); XCTAssertEqual(g.scale, 1, tag)
                                XCTAssertEqual(g.dotSize, 8, tag); XCTAssertEqual(g.dotHit, 24, tag)
                                XCTAssertEqual(g.cardPadding, HelmSpace.s6, tag); XCTAssertEqual(g.cardGap, HelmSpace.s5, tag)
                                XCTAssertEqual(g.card(columns: max(1, g.columns - 1), rows: max(1, g.rows - 1)), o.card, tag)
                                compared += 1
                            }
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(compared, 1500, "the subject: the manual grids were compared")
    }

    /// A person who turned Automatic off at base and never touched the steppers has no `grid.rows` in the store (`write(changedFrom:)` writes only what changed), so a read gives
    /// whatever the seed is now. At base that seed was 4: the grid they see is seven columns by four rows.
    func testAManualGridWhoseRowsWereNeverWrittenIsStillSevenByFour() {
        let store = NamespacedStore(namespace: "test", backing: InMemoryKeyValueStore())
        store.set(false, for: LaunchpadGridSettings.Key.automatic)       // the only key base wrote when Automatic was turned off
        let read = LaunchpadGridSettings.read(from: store)
        XCTAssertFalse(read.automatic)
        let size = CGSize(width: 1440, height: 900)
        let drawn = LaunchpadGeometry.make(for: size, topSafe: 24, settings: read)
        let before = Self.old(size, top: 24, LaunchpadGridSettings(automatic: false, rows: 4, columns: 7, iconSize: 80))
        XCTAssertEqual(drawn.rows, before.rows, "a Manual grid whose rows key was never written drew \(before.columns)x\(before.rows) at base; now \(drawn.columns)x\(drawn.rows)")
        XCTAssertEqual(drawn.columns, before.columns)
        XCTAssertEqual(drawn.icon, before.icon, accuracy: 0.0001)
    }

    // MARK: The multiplier

    func testAStoredMultiplierOfAnyTypeReadsInsideItsRange() {
        for value in [Int.max, Int.min, 0, 2, -1, "1.2", Double.nan, Double.infinity, -Double.infinity, 1e300, -1e300, true, [1.2] as [Double], Data([1, 2])] as [Any] {
            let store = NamespacedStore(namespace: "test", backing: InMemoryKeyValueStore())
            store.set(value, for: LaunchpadGridSettings.Key.sizeMultiplier)
            let read = LaunchpadGridSettings.read(from: store)
            XCTAssertTrue(LaunchpadGridSettings.multiplierRange.contains(read.sizeMultiplier), "\(value): \(read.sizeMultiplier)")
            for size in [CGSize(width: 1280, height: 800), CGSize(width: 5120, height: 2880)] {
                let g = LaunchpadGeometry.make(for: size, topSafe: 24, settings: read)
                XCTAssertTrue(g.icon.isFinite && g.icon >= LaunchpadMetrics.iconFloor && g.icon <= LaunchpadMetrics.automaticIconCeiling, "\(value) \(size): icon \(g.icon)")
            }
        }
    }

    private func rig() -> LiftRig {
        let ids = (0..<60).map { String(format: "app%02d", $0) }
        return LiftRig(self, apps: ids, layout: LaunchpadLayout(items: ids.map { .app($0) }), screen: CGSize(width: 2560, height: 1440))
    }

    private func flat(_ state: LaunchpadScreenState) -> [String] { state.pages.flatMap { $0.map(\.id) } }

    func testTheMultiplierChangedWhileTheWindowIsOpenRegridsOnceAndWritesNothing() async throws {
        let r = rig()
        let (order, pages, icon) = (flat(r.state), r.state.pages, r.state.geometry.icon)
        let bytes = try Data(contentsOf: r.layoutFile)
        var large = LaunchpadGridSettings.standard
        large.sizeMultiplier = 1.25
        r.countChanges()

        r.state.regrid(large)
        let after = r.changes

        XCTAssertGreaterThan(r.state.geometry.icon, icon, "the subject: the icon grew (\(icon) to \(r.state.geometry.icon))")
        XCTAssertGreaterThan(after, 0, "and the window was told")
        XCTAssertEqual(flat(r.state), order, "the same tiles in the same order")
        XCTAssertEqual(r.state.pages, pages, "capacity is seven by five on every multiplier: the pages are the same")
        r.state.regrid(large)
        XCTAssertEqual(r.changes, after, "the same grid again publishes nothing")

        var small = large
        small.sizeMultiplier = 0.8
        r.state.regrid(small)
        XCTAssertLessThan(r.state.geometry.icon, icon)
        r.state.regrid(.standard)
        XCTAssertEqual(r.state.geometry.icon, icon, "back to x1, back to the first icon")
        await grace()
        XCTAssertEqual(try Data(contentsOf: r.layoutFile), bytes, "the layout file was not written")
        XCTAssertTrue(r.placed.isEmpty)
    }

    func testTheMultiplierUnderManualRegridsNothing() {
        let r = rig()
        var manual = LaunchpadGridSettings.standard
        manual.automatic = false
        r.state.regrid(manual)
        let g = r.state.geometry
        r.countChanges()
        manual.sizeMultiplier = 1.25
        r.state.regrid(manual)
        XCTAssertEqual(r.state.geometry, g, "the multiplier means nothing under Manual")
        XCTAssertEqual(r.changes, 0, "and nothing is published")
    }

    /// The slider writes the multiplier's key alone: the points Manual asks for stay what they were.
    func testTheSliderWritesTheMultipliersKeyAndNoOther() {
        let store = NamespacedStore(namespace: "test", backing: InMemoryKeyValueStore())
        var next = LaunchpadGridSettings.standard
        next.sizeMultiplier = 1.15
        next.write(changedFrom: .standard, to: store)
        XCTAssertEqual(store.double(LaunchpadGridSettings.Key.sizeMultiplier, default: 0), 1.15)
        for key in [LaunchpadGridSettings.Key.iconSize, LaunchpadGridSettings.Key.rows, LaunchpadGridSettings.Key.columns, LaunchpadGridSettings.Key.automatic, LaunchpadGridSettings.Key.showNames] {
            XCTAssertNil(store.object(key), "\(key) was not written")
        }
    }
}
