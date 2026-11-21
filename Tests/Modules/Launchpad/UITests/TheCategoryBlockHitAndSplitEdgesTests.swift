import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// Which icon of a category block a point is on (`LaunchpadHit.categoryIcon`), where the block draws them
/// (`LaunchpadCategoryMark.frame(ofQuadrant:)`), and what a press does when the block moved between its two halves.
@MainActor final class TheCategoryBlockHitAndSplitEdgesTests: XCTestCase {
    private let block = CGRect(x: 100, y: 100, width: 180, height: 180)
    private let mark: CGFloat = 120

    private func centre(_ q: Int) -> CGPoint {
        let f = LaunchpadCategoryMark.frame(ofQuadrant: q, size: mark)
        return CGPoint(x: block.midX - mark / 2 + f.midX, y: block.minY + LaunchpadMetrics.iconTop + f.midY)
    }

    private func hits(apps: Int) -> [Int?] { (0..<4).map { LaunchpadHit.categoryIcon(at: centre($0), block: block, mark: mark, apps: apps) } }

    func testTheSplitAtOneFourFiveAndEightAppsAndNothingForNone() {
        XCTAssertEqual(hits(apps: 1), [0, nil, nil, nil])
        XCTAssertEqual(hits(apps: 2), [0, 1, nil, nil])
        XCTAssertEqual(hits(apps: 4), [0, 1, 2, 3], "four or fewer are all large")
        XCTAssertEqual(hits(apps: 5), [0, 1, 2, nil], "from five the fourth quarter is the cluster, which launches nothing")
        XCTAssertEqual(hits(apps: 8), [0, 1, 2, nil])
        XCTAssertEqual(hits(apps: 10_000), [0, 1, 2, nil])
        XCTAssertEqual(hits(apps: 0), [nil, nil, nil, nil])
    }

    func testBetweenIconsOffTheMarkAndNonsensePointsHitNothing() {
        let a = LaunchpadCategoryMark.frame(ofQuadrant: 0, size: mark), b = LaunchpadCategoryMark.frame(ofQuadrant: 1, size: mark)
        XCTAssertGreaterThan(b.minX, a.maxX, "the control: there is a gap between two icons")
        let origin = CGPoint(x: block.midX - mark / 2, y: block.minY + LaunchpadMetrics.iconTop)
        XCTAssertEqual(LaunchpadHit.categoryIcon(at: CGPoint(x: origin.x + (a.maxX + b.minX) / 2, y: origin.y + a.midY), block: block, mark: mark, apps: 4), nil)
        for p in [CGPoint(x: block.minX - 1, y: block.midY), CGPoint(x: CGFloat.nan, y: 120), CGPoint(x: 120, y: CGFloat.infinity), CGPoint(x: -1e300, y: 1e300)] {
            XCTAssertNil(LaunchpadHit.categoryIcon(at: p, block: block, mark: mark, apps: 4))
        }
        for m in [CGFloat(0), -5, CGFloat.nan, CGFloat.infinity] {
            XCTAssertNil(LaunchpadHit.categoryIcon(at: centre(0), block: block, mark: m, apps: 4), "mark \(m)")
        }
    }

    // MARK: - The drawing

    private func colour(_ c: NSColor) -> NSImage {
        let i = NSImage(size: NSSize(width: 16, height: 16))
        i.lockFocus(); c.setFill(); NSRect(x: 0, y: 0, width: 16, height: 16).fill(); i.unlockFocus()
        return i
    }

    func testTheQuadrantsAreDrawnWhereTheirFramesSay() throws {
        let palette: [NSColor] = [.red, .blue, .black, .cyan]
        let side: CGFloat = 160
        let view = LaunchpadCategoryMark(large: palette.map(colour), cluster: [], size: side)
        let m = MountedRender(view.frame(width: side, height: side), width: side, height: side, appearance: .aqua)
        m.settle()
        let rep = try XCTUnwrap(m.host.bitmapImageRepForCachingDisplay(in: m.host.bounds))
        m.host.cacheDisplay(in: m.host.bounds, to: rep)
        let k = CGFloat(rep.pixelsWide) / side
        func dist(_ a: NSColor, _ b: NSColor) -> CGFloat {
            guard let a = a.usingColorSpace(.sRGB), let b = b.usingColorSpace(.sRGB) else { return 9 }
            return abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent) + abs(a.blueComponent - b.blueComponent)
        }
        for q in 0..<4 {
            let f = LaunchpadCategoryMark.frame(ofQuadrant: q, size: side)
            let read = try XCTUnwrap(rep.colorAt(x: Int(f.midX * k), y: Int(f.midY * k)))
            let nearest = palette.indices.min { dist(read, palette[$0]) < dist(read, palette[$1]) }
            XCTAssertEqual(nearest, q, "quadrant \(q) is drawn at its frame")
            let off = try XCTUnwrap(rep.colorAt(x: Int((f.midX + side / 2) * k) % rep.pixelsWide, y: Int(f.midY * k)))
            XCTAssertNotEqual(palette.indices.min { dist(off, palette[$0]) < dist(off, palette[$1]) }, q, "the control: half a mark away is another colour")
        }
    }

    // MARK: - A block that moved between press and release

    private func rig() -> LiftRig {
        let rig = LiftRig(self, apps: ["a", "b", "c", "f"])
        rig.categorize(["a": "public.app-category.music", "b": "public.app-category.music", "c": "public.app-category.music", "f": "public.app-category.weather"])
        rig.state.setView(.categories)
        return rig
    }

    private func point(_ rig: LiftRig, slot: Int, _ q: Int) -> CGPoint {
        let g = rig.state.geometry
        let b = g.frame(of: rig.state.slots[0][slot]).offsetBy(dx: 0, dy: g.gridTop)
        let f = LaunchpadCategoryMark.frame(ofQuadrant: q, size: g.largeMark)
        return CGPoint(x: b.midX - g.largeMark / 2 + f.midX, y: b.minY + LaunchpadMetrics.iconTop + f.midY)
    }

    func testABlockThatMovedUnderAPressOpensItsCardAndLaunchesNoWrongApp() throws {
        let rig = rig()
        let dir = rig.layoutFile.deletingLastPathComponent()
        let p = point(rig, slot: 0, 0)
        XCTAssertTrue(rig.state.pointerDown(p, time: 0))
        XCTAssertEqual(rig.state.pressedIcon, "a", "the control: Music is first and its first app is under the press")
        let counts = LaunchCountStore(directory: dir)
        for _ in 0..<5 { XCTAssertTrue(counts.record("f")) }
        rig.state.update(snapshot: rig.engine.read())
        XCTAssertEqual(rig.state.pages[0].first.map { if case .folder(_, let n, _, _) = $0 { n } else { "" } }, LaunchpadCategoryName.title(for: .category(.weather)),
                       "the block under the point is now Weather")
        rig.state.pointerUp(p, time: 0.05)
        XCTAssertTrue(rig.launched.isEmpty, "the press was on Music's app, and Weather's is under the point now: nothing is launched")
        XCTAssertNil(rig.state.openFolder, "a press that began on another block is no click on the one now there")
    }

    func testAPressOnTheClusterOrTheGapOpensTheCardAndLaunchesNothing() throws {
        let rig = LiftRig(self, apps: ["a", "b", "c", "d", "e"])
        rig.categorize(Dictionary(uniqueKeysWithValues: ["a", "b", "c", "d", "e"].map { ($0, "public.app-category.music") }))
        rig.state.setView(.categories)
        let p = point(rig, slot: 0, 3)
        XCTAssertTrue(rig.state.pointerDown(p, time: 0))
        XCTAssertNil(rig.state.pressedIcon, "the cluster is no icon")
        rig.state.pointerUp(p, time: 0.05)
        XCTAssertTrue(rig.launched.isEmpty)
        XCTAssertEqual(rig.state.folderApps.count, 5)
        // The control: the same press on the first large icon launches.
        rig.state.closeFolder()
        let q = point(rig, slot: 0, 0)
        XCTAssertTrue(rig.state.pointerDown(q, time: 1))
        rig.state.pointerUp(q, time: 1.05)
        XCTAssertEqual(rig.launched, ["a"])
    }
}
