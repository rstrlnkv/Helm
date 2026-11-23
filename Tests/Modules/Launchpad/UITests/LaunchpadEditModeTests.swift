import HelmUI
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// The edit mode's machine (a hold that begins it, fed by hand with time of the test's own), its state (what begins and ends it, what a click does in it), and its badges' places.
final class LaunchpadEditModeMachineTests: XCTestCase {
    private let g = LaunchpadGeometry.make(for: CGSize(width: 1280, height: 800), topSafe: 0)
    private func surface(holds: Bool = true) -> LaunchpadSurface {
        var s = LaunchpadSurface(geometry: g, page: 0, pageCounts: [10], gap: nil)
        s.holdsToEdit = holds
        return s
    }
    private func core(_ slot: Int) -> CGPoint { g.center(ofSlot: slot) }

    func testAHoldBeginsTheModeAndAMoveAfterItLiftsTheSameTile() {
        var m = LaunchpadLift()
        _ = m.feed(.down, at: core(2), surface: surface(), time: 0)
        XCTAssertEqual(m.wake, LaunchpadLiftTiming.editHold, "a timer is wanted for the hold")
        XCTAssertEqual(m.feed(.tick, at: core(2), surface: surface(), time: 0.49), .none, "not before")
        XCTAssertEqual(m.feed(.tick, at: core(2), surface: surface(), time: 0.5), .beginEditing(address: 2))
        XCTAssertNil(m.wake)
        XCTAssertTrue(m.isEngaged)
        XCTAssertEqual(m.feed(.moved, at: CGPoint(x: core(2).x + 4, y: core(2).y), surface: surface(holds: false), time: 0.6), .none, "under the threshold")
        XCTAssertEqual(m.feed(.moved, at: CGPoint(x: core(2).x + 6, y: core(2).y), surface: surface(holds: false), time: 0.7), .lift(address: 2))
        XCTAssertTrue(m.isLifted)
    }

    func testLettingGoAfterAHoldIsNoClick() {
        var m = LaunchpadLift()
        _ = m.feed(.down, at: core(2), surface: surface(), time: 0)
        _ = m.feed(.tick, at: core(2), surface: surface(), time: 0.5)
        XCTAssertEqual(m.feed(.up, at: core(2), surface: surface(holds: false), time: 0.9), .none)
        XCTAssertFalse(m.isEngaged)
    }

    func testNothingIsHeldWhereTheSurfaceDoesNotAskForIt() {
        var m = LaunchpadLift()
        _ = m.feed(.down, at: core(2), surface: surface(holds: false), time: 0)
        XCTAssertNil(m.wake, "in the category view and in the mode itself")
        XCTAssertEqual(m.feed(.tick, at: core(2), surface: surface(holds: false), time: 5), .none)
        XCTAssertEqual(m.feed(.up, at: core(2), surface: surface(holds: false), time: 5.1), .click(address: 2))
    }

    func testAMoveBeforeTheHoldLiftsAndAReleaseBeforeItClicksAsBefore() {
        var m = LaunchpadLift()
        _ = m.feed(.down, at: core(2), surface: surface(), time: 0)
        XCTAssertEqual(m.feed(.moved, at: CGPoint(x: core(2).x + 6, y: core(2).y), surface: surface(), time: 0.3), .lift(address: 2))
        var n = LaunchpadLift()
        _ = n.feed(.down, at: core(2), surface: surface(), time: 0)
        XCTAssertEqual(n.feed(.up, at: core(2), surface: surface(), time: 0.3), .click(address: 2))
    }
}

@MainActor final class LaunchpadEditModeTests: XCTestCase {
    private let folderID = UUID()
    /// a, a folder of b and c, d, e, f.
    private func rig(removable: Set<String> = []) -> LiftRig {
        let r = LiftRig(self, apps: ["a", "b", "c", "d", "e", "f"],
                        layout: LaunchpadLayout(items: [.app("a"), .folder(.init(id: folderID, name: "F", apps: ["b", "c"])), .app("d"), .app("e"), .app("f")]))
        r.state.onVerdicts = { candidates in candidates.map { removable.contains($0.bundleID) ? .removable : .refused(.notOffered) } }
        return r
    }
    private func cell(_ r: LiftRig, _ slot: Int) -> CGRect { r.g.frame(of: r.g.cell(slot)).offsetBy(dx: 0, dy: r.g.gridTop) }

    func testAHoldOnATileBeginsTheModeAndItsReleaseOpensNothing() {
        let r = rig()
        XCTAssertTrue(r.state.pointerDown(r.core(0), time: 0))
        XCTAssertFalse(r.state.editing)
        r.state.tick(at: 0.5)
        XCTAssertTrue(r.state.editing)
        r.state.pointerUp(r.core(0), time: 0.9)
        XCTAssertEqual(r.launched, [], "a release after a hold is no click")
        XCTAssertFalse(r.state.pointerBusy)
        XCTAssertNil(r.state.pressedID)
    }

    func testNoHoldInTheCategoryViewAndNoModeThere() {
        let r = rig()
        r.state.setView(.categories)
        XCTAssertFalse(r.state.editAllowed)
        _ = r.state.pointerDown(r.core(0), time: 0)
        r.state.tick(at: 0.5)
        XCTAssertFalse(r.state.editing)
        r.state.beginEditing()
        XCTAssertFalse(r.state.editing)
    }

    func testAClickInTheModeLaunchesNothingAndAFolderStillOpens() {
        let r = rig()
        r.state.beginEditing()
        XCTAssertTrue(r.state.pointerDown(r.core(0), time: 0))
        r.state.pointerUp(r.core(0), time: 0.1)
        XCTAssertEqual(r.launched, [])
        r.state.openApp("a", "A")
        XCTAssertEqual(r.launched, [], "Return and VoiceOver's default action too")
        XCTAssertTrue(r.state.pointerDown(r.core(1), time: 1))
        r.state.pointerUp(r.core(1), time: 1.1)
        XCTAssertEqual(r.state.openFolder, folderID)
        r.state.endEditing()
        r.state.openApp("a", "A")
        XCTAssertEqual(r.launched, ["a"], "the control: outside the mode it launches")
    }

    func testEveryExitEndsTheModeAndEscGoesFolderThenModeThenWindow() {
        let r = rig()
        r.state.beginEditing()
        r.state.open(folder: folderID)
        r.state.escape()
        XCTAssertNil(r.state.openFolder)
        XCTAssertTrue(r.state.editing, "the folder closed first")
        r.state.escape()
        XCTAssertFalse(r.state.editing)
        XCTAssertEqual(r.closes, 0)
        r.state.escape()
        XCTAssertEqual(r.closes, 1)

        r.state.beginEditing()
        r.state.open(folder: folderID)
        r.state.backgroundClicked()
        XCTAssertTrue(r.state.editing && r.state.openFolder == nil, "a click on the background closes the folder first")
        r.state.backgroundClicked()
        XCTAssertFalse(r.state.editing)
        XCTAssertEqual(r.closes, 1)

        r.state.beginEditing()
        r.state.search = "a"
        XCTAssertFalse(r.state.editing, "typing in the search")
        r.state.search = ""

        r.state.beginEditing()
        r.state.setView(.categories)
        XCTAssertFalse(r.state.editing, "the category view")
        r.state.setView(.apps)

        r.state.beginEditing()
        XCTAssertTrue(r.state.editing)
        r.state.shutdown()
        XCTAssertFalse(r.state.editing)
        XCTAssertTrue(r.state.removable.isEmpty)
    }

    func testTheDoorIsAskedOnceAtEntryAndAgainOnlyWhenAPathChangesAndNeverAboutMacOSOwn() async {
        let r = LiftRig(self, apps: ["a", "b", "com.apple.x"])
        var asked: [[String]] = []
        r.state.onVerdicts = { candidates in
            asked.append(candidates.map(\.bundleID).sorted())
            return candidates.map { $0.bundleID == "a" ? .removable : .refused(.notOffered) }
        }
        r.state.beginEditing()
        await waitUntil("the answer") { r.state.removable == ["a"] }
        XCTAssertEqual(asked, [["a", "b"]])
        r.state.update(snapshot: r.engine.read(reason: .refresh))
        XCTAssertEqual(asked.count, 1, "the same apps at the same paths ask nothing")
        r.catalog.reading = CatalogReading(apps: r.catalog.reading.apps.map {
            CatalogApp(id: $0.id, name: $0.name, path: $0.id == "a" ? "/Applications/Elsewhere/a.app" : $0.path)
        }, complete: true)
        r.state.update(snapshot: r.engine.read(reason: .refresh))
        await waitUntil("asked again") { asked.count == 2 }
        r.state.endEditing()
        XCTAssertTrue(r.state.removable.isEmpty)
    }

    func testABadgePressIsTheViewsAndNeitherLiftsNorClicks() async {
        let r = rig(removable: ["a"])
        r.state.beginEditing()
        await waitUntil("the answer") { r.state.removable == ["a"] }
        let at = cell(r, 0)
        for placed in LaunchpadBadge.frames(r.state.badges(for: CatalogApp(id: "a", name: "A", path: "")), cell: at.size, icon: r.g.icon, iconTop: r.g.iconTop) {
            let point = CGPoint(x: at.minX + placed.frame.midX, y: at.minY + placed.frame.midY)
            XCTAssertFalse(r.state.pointerDown(point, time: 0), "\(placed.kind)")
            XCTAssertFalse(r.state.pointerBusy)
            XCTAssertNil(r.state.pressedID)
        }
        XCTAssertTrue(r.state.pointerDown(r.core(0), time: 1), "the control: the tile's middle is the window's")
    }

    func testBadgesAreInsideTheirCellAtEveryScaleAndTheHitTestFindsEachWhereItIsDrawn() {
        var scales: [CGFloat] = []
        for size in [CGSize(width: 864, height: 600), CGSize(width: 1440, height: 900), CGSize(width: 2304, height: 1440)] {
            let g = LaunchpadGeometry.make(for: size, topSafe: 0)
            scales.append(g.scale)
            var s = LaunchpadSurface(geometry: g, page: 0, pageCounts: [10], gap: nil)
            s.badged = [3: [.remove, .hide], 4: .hide]
            let cell = g.frame(of: g.cell(3)).offsetBy(dx: 0, dy: g.gridTop)
            let placed = LaunchpadBadge.frames([.remove, .hide], cell: cell.size, icon: g.icon, iconTop: g.iconTop)
            XCTAssertEqual(placed.map(\.kind), [.remove, .hide])
            for badge in placed {
                XCTAssertTrue(CGRect(origin: .zero, size: cell.size).contains(badge.frame), "scale \(g.scale): \(badge.kind) is in its cell")
                XCTAssertGreaterThanOrEqual(badge.frame.width, 24)
                let centre = CGPoint(x: cell.minX + badge.frame.midX, y: cell.minY + badge.frame.midY)
                let hit = LaunchpadHit.badge(at: centre, in: s)
                XCTAssertEqual(hit?.address, 3, "scale \(g.scale)")
                XCTAssertEqual(hit?.kind, badge.kind, "scale \(g.scale)")
            }
            XCTAssertLessThan(placed[0].frame.midX, placed[1].frame.midX, "the × is at the left, the eye at the right")
            XCTAssertNil(LaunchpadHit.badge(at: g.center(ofSlot: 3), in: s), "the icon's middle is no badge")
            XCTAssertNil(LaunchpadHit.badge(at: CGPoint(x: g.center(ofSlot: 5).x - g.icon / 2 + 8, y: g.center(ofSlot: 5).y - g.icon / 2 + 8), in: s), "a tile with none")
            var open = s
            open.card = LaunchpadSurface.Card(geometry: g, count: 4)
            open.badged = [1: .hide]
            let c = open.card!.center(ofSlot: 1)
            let eye = LaunchpadBadge.frames(.hide, cell: CGSize(width: g.cellWidth, height: g.cellHeight), icon: g.icon, iconTop: g.iconTop)[0].frame
            XCTAssertEqual(LaunchpadHit.badge(at: CGPoint(x: c.x - g.cellWidth / 2 + eye.midX, y: c.y - g.cellHeight / 2 + eye.midY), in: open)?.kind, .hide, "in the card")
        }
        XCTAssertEqual(scales, [0.6, 1, 1.6], "the three scales were the ones asked for")
    }

    func testTheWigglePausesUnderReduceMotionAndAnIdsStepIsTheSameEveryTime() {
        XCTAssertEqual(HelmMotion.wiggle(seed: 3) == nil, HelmMotion.reduceMotion)
        XCTAssertEqual(LaunchpadTileEdit.seed(of: "com.example.app"), LaunchpadTileEdit.seed(of: "com.example.app"))
        XCTAssertNotEqual(LaunchpadTileEdit.seed(of: "a"), LaunchpadTileEdit.seed(of: "b"))
    }
}
