import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// A press on a large folder is the panel's, so what it means is read from the press point at the click: an icon of the
/// block launches its app (the first eight, or nine when there are no more than nine), the gaps between icons, the ninth
/// cell of a folder of more than nine and the block's margin open the folder, and a block that moved since the press
/// launches its app only if that same app is under the press's point at the release, else it opens the folder.
@MainActor final class AClickOnALargeFolderLaunchesTheIconOrOpensTheFolderTests: XCTestCase {
    private let folderID = UUID()
    private func members(_ n: Int) -> [String] { (0..<n).map { "m\($0)" } }

    private func rig(apps n: Int, before: [String] = []) -> LiftRig {
        let rest = (0..<12).map { "t\($0)" }
        let items: [LaunchpadLayout.Item] = before.map { .app($0) } + [.folder(.init(id: folderID, name: "F", apps: members(n), large: true))] + rest.map { .app($0) }
        return LiftRig(self, apps: before + members(n) + rest, layout: LaunchpadLayout(items: items))
    }

    private func block(_ r: LiftRig) -> CGRect {
        let at = r.state.pages[0].firstIndex { $0.id == folderID.uuidString }!
        return r.g.frame(of: r.state.slots[0][at]).offsetBy(dx: 0, dy: r.g.gridTop)
    }

    private func markOrigin(_ r: LiftRig) -> CGPoint {
        let b = block(r)
        return CGPoint(x: b.midX - r.g.largeMark / 2, y: b.minY + LaunchpadMetrics.iconTop)
    }

    private func centre(_ r: LiftRig, icon i: Int) -> CGPoint {
        let f = LaunchpadFolderMark.frame(ofIcon: i, size: r.g.largeMark), o = markOrigin(r)
        return CGPoint(x: o.x + f.midX, y: o.y + f.midY)
    }

    private func click(_ r: LiftRig, at p: CGPoint) {
        XCTAssertTrue(r.state.pointerDown(p, time: 0), "subject: the press is taken")
        r.state.pointerUp(p, time: 0.05)
    }

    func testEachIconOfAFolderOfNineOrFewerLaunchesItsOwnApp() {
        for n in [9, 5] {
            for i in 0..<n {
                let r = rig(apps: n)
                XCTAssertEqual(r.state.slots[0].first?.span, 2, "subject: large")
                click(r, at: centre(r, icon: i))
                XCTAssertEqual(r.launched, ["m\(i)"], "\(n) apps, icon \(i)")
                XCTAssertNil(r.state.openFolder)
            }
        }
    }

    func testPastNineTheFirstEightLaunchAndTheNinthCellOpensTheFolder() {
        for i in 0..<8 {
            let r = rig(apps: 12)
            click(r, at: centre(r, icon: i))
            XCTAssertEqual(r.launched, ["m\(i)"], "icon \(i)")
        }
        let r = rig(apps: 12)
        click(r, at: centre(r, icon: 8))
        XCTAssertEqual(r.launched, [], "the ninth cell launches nothing")
        XCTAssertEqual(r.state.openFolder, folderID, "the ninth cell opens the folder")
    }

    func testTheGapsBetweenIconsTheEmptyCellsAndTheMarginOpenTheFolder() {
        let r0 = rig(apps: 9)
        let size = r0.g.largeMark
        let a = LaunchpadFolderMark.frame(ofIcon: 0, size: size), b = LaunchpadFolderMark.frame(ofIcon: 1, size: size), d = LaunchpadFolderMark.frame(ofIcon: 3, size: size)
        XCTAssertGreaterThan(b.minX - a.maxX, 0.5, "subject: the icons have a gap")
        let o = markOrigin(r0)
        var points = [CGPoint(x: o.x + (a.maxX + b.minX) / 2, y: o.y + a.midY),
                      CGPoint(x: o.x + a.midX, y: o.y + (a.maxY + d.minY) / 2),
                      CGPoint(x: o.x + 1, y: o.y + 1)]
        let b0 = block(r0)
        points += [CGPoint(x: b0.minX + 2, y: b0.minY + 2), CGPoint(x: b0.maxX - 2, y: b0.maxY - 2), CGPoint(x: b0.midX, y: b0.maxY - 2)]
        for p in points {
            let r = rig(apps: 9)
            click(r, at: p)
            XCTAssertEqual(r.launched, [], "\(p)")
            XCTAssertEqual(r.state.openFolder, folderID, "\(p) opens")
        }
        // Empty cells of a folder of five.
        for i in 5..<9 {
            let r = rig(apps: 5)
            click(r, at: centre(r, icon: i))
            XCTAssertEqual(r.launched, [], "empty cell \(i)")
            XCTAssertEqual(r.state.openFolder, folderID)
        }
    }

    /// The folder in front of the block changes size while the press is down: the block keeps its place in the list (so the
    /// release is still its click) and moves on the page.
    func testABlockThatMovedUnderThePressNeverLaunchesAnAppThePressWasNotOn() {
        let other = UUID()
        var answered = 0, shifted = 0
        for startsLarge in [true, false] {
            for i in 0..<8 {
                let items: [LaunchpadLayout.Item] = [.folder(.init(id: other, name: "G", apps: ["g0", "g1"], large: startsLarge)),
                    .folder(.init(id: folderID, name: "F", apps: members(12), large: true))] + (0..<12).map { .app("t\($0)") }
                let r = LiftRig(self, apps: ["g0", "g1"] + members(12) + (0..<12).map { "t\($0)" }, layout: LaunchpadLayout(items: items))
                let at = r.state.pages[0].firstIndex { $0.id == folderID.uuidString }!
                let from = r.g.frame(of: r.state.slots[0][at])
                let o = CGPoint(x: from.midX - r.g.largeMark / 2, y: from.minY + r.g.gridTop + LaunchpadMetrics.iconTop)
                let f = LaunchpadFolderMark.frame(ofIcon: i, size: r.g.largeMark)
                let p = CGPoint(x: o.x + f.midX, y: o.y + f.midY)
                XCTAssertTrue(r.state.pointerDown(p, time: 0), "subject: the press is taken")
                guard let moved = r.engine.apply(.resize(other, large: !startsLarge)) else { XCTFail("resize refused"); continue }
                r.state.update(snapshot: moved)
                let now = r.state.slots[0][r.state.pages[0].firstIndex { $0.id == folderID.uuidString }!]
                if now != r.state.slots[0][at] || r.g.frame(of: now) != from { shifted += 1 }
                r.state.pointerUp(p, time: 0.05)
                if !r.launched.isEmpty || r.state.openFolder != nil { answered += 1 }
                XCTAssertTrue(r.launched.isEmpty || r.launched == ["m\(i)"],
                              "pressed icon \(i) with the folder before it \(startsLarge ? "shrunk" : "grown"): launched \(r.launched)")
            }
        }
        XCTAssertGreaterThan(shifted, 0, "subject: the block moved")
        XCTAssertGreaterThan(answered, 0, "subject: some release was still answered on the moved block")
    }

    /// The per-icon wash follows the press: `pressedIcon` is the app of the icon the press is on, nil for a press on the block's
    /// margin or on a small tile, and gone with `pressedID` at the release.
    func testPressedIconIsSetOnlyForAPressOnAnIconAndClearedWithThePress() {
        let r = rig(apps: 9)
        XCTAssertNil(r.state.pressedIcon, "subject: nothing pressed")
        let p = centre(r, icon: 4)
        XCTAssertTrue(r.state.pointerDown(p, time: 0))
        XCTAssertEqual(r.state.pressedIcon, "m4")
        XCTAssertEqual(r.state.pressedID, folderID.uuidString)
        r.state.pointerUp(p, time: 0.05)
        XCTAssertNil(r.state.pressedID, "subject: the press ended")
        XCTAssertNil(r.state.pressedIcon, "the icon's wash goes with the press")

        let b = block(r)
        XCTAssertTrue(r.state.pointerDown(CGPoint(x: b.minX + 2, y: b.minY + 2), time: 1))
        XCTAssertEqual(r.state.pressedID, folderID.uuidString, "subject: the block is pressed")
        XCTAssertNil(r.state.pressedIcon, "the margin washes the whole tile, no icon")

        let t = rig(apps: 9)
        let at = t.state.pages[0].firstIndex { $0.id == "t0" }!
        let f = t.g.frame(of: t.state.slots[0][at]).offsetBy(dx: 0, dy: t.g.gridTop)
        XCTAssertTrue(t.state.pointerDown(CGPoint(x: f.midX, y: f.midY), time: 0))
        XCTAssertEqual(t.state.pressedID, "t0", "subject: the small tile is pressed")
        XCTAssertNil(t.state.pressedIcon)
    }
}
