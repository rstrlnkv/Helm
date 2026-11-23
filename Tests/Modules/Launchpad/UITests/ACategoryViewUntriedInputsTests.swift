import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// The inputs pass 14 did not feed: an app in two blocks, a category that Hide empties under its own card, a switch while a card
/// or a search is up, a clock that goes back, counts for apps that are gone or too many, an odd column count, a view setting that
/// is anything. Each case first proves the thing it acts on is there.
@MainActor final class ACategoryViewUntriedInputsTests: XCTestCase {
    private let music = "public.app-category.music", weather = "public.app-category.weather"

    private func rig(_ apps: [(String, String?, Date?)], clock: Date = Date()) -> LiftRig {
        let rig = LiftRig(self, apps: apps.map(\.0))
        rig.state.wallClock = { clock }
        rig.catalog.reading = CatalogReading(apps: apps.map { CatalogApp(id: $0.0, name: $0.0.capitalized, path: "/Applications/\($0.0).app", category: $0.1, added: $0.2) },
                                             complete: true)
        rig.state.update(snapshot: rig.engine.read(reason: .refresh))
        rig.state.setView(.categories)
        return rig
    }

    private func countsDir(_ rig: LiftRig) -> URL { rig.layoutFile.deletingLastPathComponent() }

    private func point(_ rig: LiftRig, slot: Int, quadrant q: Int) -> CGPoint {
        let g = rig.state.geometry
        let block = g.frame(of: rig.state.slots[0][slot]).offsetBy(dx: 0, dy: g.gridTop)
        let f = LaunchpadCategoryMark.frame(ofQuadrant: q, size: g.largeMark, edge: g.largeEdge)
        return CGPoint(x: block.midX - g.largeMark / 2 + f.midX, y: block.minY + g.iconTop + f.midY)
    }

    /// The screen reads a category's quadrants where `largeEdge` draws them: a press one point inside the first quadrant's top left or the fourth's bottom right takes its app, and one point
    /// outside either takes none (a hit test on the old, smaller 0.85-of-the-mark well would have missed the inside points).
    func testAPressAtTheCornersOfTheDrawnQuadrantsTakesTheAppAndJustOutsideTakesNone() {
        let apps = (0..<4).map { ("m\($0)", Optional(music), Optional<Date>.none) }
        let g0 = rig(apps).state.geometry
        XCTAssertGreaterThan(LaunchpadCategoryMark.frame(ofQuadrant: 0, size: g0.largeMark).minX,
                             LaunchpadCategoryMark.frame(ofQuadrant: 0, size: g0.largeMark, edge: g0.largeEdge).minX + 1, "subject: the old well's quadrant starts further in")
        for (quadrant, dx, dy) in [(0, 1.0, 1.0), (3, -1.0, -1.0)] as [(Int, CGFloat, CGFloat)] {
            for inside in [true, false] {
                let rig = rig(apps), g = rig.state.geometry
                let block = g.frame(of: rig.state.slots[0][0]).offsetBy(dx: 0, dy: g.gridTop)
                let f = LaunchpadCategoryMark.frame(ofQuadrant: quadrant, size: g.largeMark, edge: g.largeEdge)
                let corner = quadrant == 0 ? CGPoint(x: f.minX, y: f.minY) : CGPoint(x: f.maxX, y: f.maxY)
                let sign: CGFloat = inside ? 1 : -1
                let p = CGPoint(x: block.midX - g.largeMark / 2 + corner.x + sign * dx, y: block.minY + g.iconTop + corner.y + sign * dy)
                XCTAssertTrue(rig.state.pointerDown(p, time: 0))
                XCTAssertEqual(rig.state.pressedIcon, inside ? "m\(quadrant)" : nil, "quadrant \(quadrant), \(inside ? "inside" : "outside") its corner")
                rig.state.pointerUp(p, time: 0.05)
                XCTAssertEqual(rig.launched, inside ? ["m\(quadrant)"] : [], "quadrant \(quadrant), \(inside ? "inside" : "outside")")
            }
        }
    }

    func testAnAppInRecentlyAddedAndItsCategoryIsPressedInOneBlockOnly() {
        let rig = rig([("a", music, Date()), ("b", music, nil), ("c", weather, nil)])
        let ids = rig.state.pages[0].map(\.id)
        XCTAssertEqual(ids.count, 4, "the control: Recently Added, Music, Weather and the locked Hidden")
        guard case .folder(_, _, let recent, _) = rig.state.pages[0][0], case .folder(_, _, let music, _) = rig.state.pages[0][1] else { return XCTFail("blocks") }
        XCTAssertEqual(recent.map(\.id), ["a"])
        XCTAssertTrue(music.map(\.id).contains("a"), "the same app is in both blocks")
        for slot in [0, 1] {
            let p = point(rig, slot: slot, quadrant: slot == 0 ? 0 : music.firstIndex { $0.id == "a" }!)
            XCTAssertTrue(rig.state.pointerDown(p, time: Double(slot)))
            XCTAssertEqual(rig.state.pressedID, ids[slot], "the press belongs to the block it is on")
            XCTAssertEqual(rig.state.pressedIcon, "a")
            XCTAssertEqual(rig.state.pages[0].filter { $0.id == rig.state.pressedID }.count, 1, "one block takes the wash")
            rig.state.pointerUp(p, time: Double(slot) + 0.05)
        }
        XCTAssertEqual(rig.launched, ["a", "a"])
    }

    func testAnAppInTwoBlocksSwellsInTheBlockTheLaunchCameFromOnly() {
        let rig = rig([("a", music, Date()), ("b", music, nil)])
        let ids = rig.state.pages[0].map(\.id)
        XCTAssertEqual(ids.count, 3, "the control: Recently Added and Music both hold a, and the locked Hidden")
        XCTAssertNil(rig.state.launchingBlock)
        for slot in [0, 1] {
            rig.state.launchFailed()
            let p = point(rig, slot: slot, quadrant: 0)
            XCTAssertTrue(rig.state.pointerDown(p, time: Double(slot)))
            rig.state.pointerUp(p, time: Double(slot) + 0.05)
            rig.state.launched("a")
            XCTAssertEqual(rig.state.launching, "a")
            XCTAssertEqual(rig.state.launchingBlock, ids[slot], "the swell belongs to the block it came from")
            for (other, id) in ids.enumerated() {
                guard case .folder(_, _, let apps, _) = rig.state.pages[0][other] else { return XCTFail("a category block") }
                XCTAssertEqual(rig.state.popped(block: id, among: apps.prefix(4)), other == slot ? 0 : nil,
                               "the app swells in block \(slot) and in no other that holds it")
            }
        }
    }

    func testAFailedLaunchTakesTheSwellOffTheBlockItCameFrom() {
        let rig = rig([("a", music, Date()), ("b", music, nil)])
        let p = point(rig, slot: 1, quadrant: 0)
        XCTAssertTrue(rig.state.pointerDown(p, time: 0))
        rig.state.pointerUp(p, time: 0.05)
        rig.state.launched("a")
        XCTAssertEqual(rig.state.launchingBlock, rig.state.pages[0][1].id, "the control: the click set the block")
        rig.state.launchFailed()
        XCTAssertNil(rig.state.launching)
        XCTAssertNil(rig.state.launchingBlock, "a block left marked would swell on the next launch from anywhere")
    }

    func testANegativeAppCountTrapsNothing() {
        XCTAssertNil(LaunchpadHit.categoryIcon(at: .zero, block: CGRect(x: 0, y: 0, width: 180, height: 180), mark: 120, iconTop: 6, apps: -3))
        XCTAssertNil(LaunchpadHit.icon(at: .zero, block: CGRect(x: 0, y: 0, width: 180, height: 180), mark: 120, iconTop: 6, apps: -3))
    }

    func testACategoryEmptiedByHideWhileItsCardIsOpenClosesTheCardAndLeavesTheOthers() throws {
        let rig = rig([("a", music, nil), ("b", music, nil), ("f", weather, nil)])
        let weatherBlock = try XCTUnwrap(rig.state.pages[0].first { if case .folder(_, let n, _, _) = $0 { n == LaunchpadCategoryName.title(for: .category(.weather)) } else { false } })
        rig.state.open(folder: try XCTUnwrap(UUID(uuidString: weatherBlock.id)))
        XCTAssertNotNil(rig.state.openFolder)
        XCTAssertEqual(rig.state.folderApps.map(\.id), ["f"])
        let landed = try XCTUnwrap(rig.engine.apply(.hide("f")))
        rig.state.update(snapshot: landed)
        XCTAssertNil(rig.state.openFolder, "its block is gone, so is its card")
        XCTAssertTrue(rig.state.folderApps.isEmpty)
        XCTAssertNil(rig.state.selection)
        XCTAssertEqual(rig.state.pages[0].count, 2, "Music stays, and the locked Hidden")
        XCTAssertTrue(rig.state.categoriesShown)
    }

    func testASwitchWithACardOpenClosesItAndASwitchUnderASearchWaitsForTheSearch() throws {
        let rig = rig([("a", music, nil), ("b", music, nil), ("c", weather, nil)])
        rig.state.open(folder: try XCTUnwrap(UUID(uuidString: rig.state.pages[0][0].id)))
        XCTAssertNotNil(rig.state.openFolder)
        rig.state.setView(.apps)
        XCTAssertNil(rig.state.openFolder, "the card does not outlive its view")
        XCTAssertFalse(rig.state.categoriesShown)
        XCTAssertEqual(rig.state.pages[0].count, 3, "the control: the arrangement's three apps")
        rig.state.search = "a"
        rig.state.setView(.categories)
        XCTAssertEqual(rig.state.view, .categories, "the choice is taken")
        XCTAssertFalse(rig.state.categoriesShown, "but a search shows the apps flat")
        XCTAssertEqual(rig.state.search, "a", "and keeps its text")
        rig.state.search = ""
        XCTAssertTrue(rig.state.categoriesShown)
        XCTAssertEqual(rig.state.pages[0].count, 3, "the arrangement's blocks and the locked Hidden")
    }

    func testAClockThatGoesBackDropsTheRecentBlockAndOneThatGoesOnDropsItToo() {
        let added = Date(timeIntervalSince1970: 1_800_000_000)
        let rig = rig([("a", music, added), ("b", music, nil)], clock: added.addingTimeInterval(3_600))
        XCTAssertEqual(rig.state.pages[0].count, 3, "the control: Recently Added, Music and the locked Hidden")
        rig.state.wallClock = { added.addingTimeInterval(-86_400) }
        rig.state.update(snapshot: rig.engine.read(reason: .refresh))
        XCTAssertEqual(rig.state.pages[0].count, 2, "an app added after now is not recent")
        rig.state.wallClock = { added.addingTimeInterval(31 * 86_400) }
        rig.state.update(snapshot: rig.engine.read(reason: .refresh))
        XCTAssertEqual(rig.state.pages[0].count, 2, "thirty-one days on it is not recent either")
    }

    func testCountsForAppsThatAreGoneAndTenThousandAndOneCountsNeverBreakTheBlocks() throws {
        let rig = rig([("a", music, nil), ("b", music, nil), ("c", weather, nil)])
        let dir = countsDir(rig)
        let many = "{" + (0...10_000).map { "\"ghost\($0)\":\($0 + 2)" }.joined(separator: ",") + ",\"c\":1}"
        try Data(#"{"version":1,"counts":\#(many)}"#.utf8).write(to: dir.appendingPathComponent("launch-counts.json"))
        let snap = rig.engine.read(reason: .refresh)
        XCTAssertEqual(snap.launchCounts.count, LaunchpadLimits.maxCountedApps, "bounded, the lowest dropped")
        XCTAssertNil(snap.launchCounts["c"], "the count of 1 is the lowest, so it was dropped, not a ghost")
        rig.state.update(snapshot: snap)
        XCTAssertEqual(rig.state.pages[0].count, 3, "Music, Weather and the locked Hidden")
        let shown = rig.state.pages[0].flatMap { entry -> [String] in if case .folder(_, _, let apps, _) = entry { apps.map(\.id) } else { [] } }
        XCTAssertEqual(shown.sorted(), ["a", "b", "c"], "no ghost is shown, no installed app is lost")
    }

    func testAnOddColumnCountMakesAnEvenPairedGridThatFitsThePage() {
        for columns in 1...10 {
            let g = LaunchpadGeometry.make(for: CGSize(width: 1280, height: 800), topSafe: 0,
                                           settings: LaunchpadGridSettings(automatic: false, rows: 3, columns: columns, iconSize: 64))
            let p = g.pairedColumns
            XCTAssertEqual(p.columns % 2, 0, "columns \(columns)")
            XCTAssertEqual(p.capacity, p.columns * g.rows)
            XCTAssertEqual(p.rows, g.rows)
            XCTAssertEqual(p.cellWidth, g.cellWidth)
            if g.columns >= 2 { XCTAssertEqual(p.columns, g.columns - g.columns % 2); XCTAssertGreaterThanOrEqual(p.gridLeft, 0) }
        }
    }

    func testTheSwitchFitsAt1280ButNotInAWindowTooNarrowForIt() {
        XCTAssertTrue(LaunchpadGeometry.make(for: CGSize(width: 1280, height: 800), topSafe: 0).switchFits)
        let narrow = LaunchpadGeometry.make(for: CGSize(width: 700, height: 500), topSafe: 0)
        XCTAssertFalse(narrow.switchFits)
        let at1024 = LaunchpadGeometry.make(for: CGSize(width: 1024, height: 768), topSafe: 0).switchFits
        XCTAssertEqual(at1024, (1024 - LaunchpadMetrics.searchWidth) / 2 - LaunchpadMetrics.sideMargin * 1024 >= LaunchpadMetrics.switchRoom)
    }

    func testTheViewSettingReadsAppsForAnythingUnknownIsReadBeforeTheWindowOpensAndAnEqualSetIsRefused() async {
        let backing = InMemoryKeyValueStore()
        let store = NamespacedStore(namespace: "test", backing: backing)
        let engine = LaunchpadEngine(catalog: RigCatalog(["a"]), launcher: RigLauncher(), store: LayoutStore(directory: scratchDirectory("view")))
        for bad in ["", "Categories", "bogus", "categories "] {
            store.set(bad, for: LaunchpadViewMode.key)
            XCTAssertEqual(LaunchpadViewMode.read(from: store), .apps, "'\(bad)' reads as apps")
        }
        store.set(3, for: LaunchpadViewMode.key)
        XCTAssertEqual(LaunchpadViewMode.read(from: store), .apps, "a number is no view")
        store.set("categories", for: LaunchpadViewMode.key)
        let model = LaunchpadViewModel(work: engine, store: store)
        XCTAssertEqual(model.viewMode, .categories, "read when the model is made, before any window")
        store.set("apps", for: LaunchpadViewMode.key)
        model.setViewMode(.categories)
        XCTAssertEqual(store.string(LaunchpadViewMode.key, default: ""), "apps", "an equal view is refused: nothing was written")
        model.reloadViewMode()
        XCTAssertEqual(model.viewMode, .apps, "a window about to open reads the store again")
        model.setViewMode(.categories)
        XCTAssertEqual(store.string(LaunchpadViewMode.key, default: ""), "categories")
    }

    func testResetAnswersNilWhenTheWriteCannotLandAndTheCountsStay() throws {
        let rig = rig([("a", music, nil)])
        let dir = countsDir(rig)
        let store = LaunchCountStore(directory: dir)
        XCTAssertTrue(store.record("a"))
        let fileMode = (try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.posixPermissions] as? Int) ?? 0
        XCTAssertEqual(fileMode, 0o600, "the control: the file is there")
        // The folder's mode is repaired by every write, so a mode cannot refuse it: the immutable flag can.
        var folder = dir
        var flag = URLResourceValues(); flag.isUserImmutable = true
        try folder.setResourceValues(flag)
        defer { var free = URLResourceValues(); free.isUserImmutable = false; try? folder.setResourceValues(free) }
        XCTAssertNil(rig.engine.resetLaunchCounts(), "a failed write is nil, so the caller reads again")
        XCTAssertEqual(store.load().counts, ["a": 1])
    }

    func testTheArrowKeysAndTheCardWorkOverBlocksAndTheGridIsPaired() throws {
        let rig = rig([("a", music, nil), ("b", music, nil), ("c", weather, nil), ("d", nil, nil)])
        XCTAssertEqual(rig.state.pages[0].count, 4, "Music, Weather, Others and the locked Hidden")
        XCTAssertEqual(rig.state.geometry.columns % 2, 0)
        rig.state.move(dx: 1, dy: 0)
        XCTAssertEqual(rig.state.selection, 0)
        rig.state.move(dx: 1, dy: 0); rig.state.move(dx: 1, dy: 0); rig.state.move(dx: 1, dy: 0); rig.state.move(dx: 1, dy: 0)
        XCTAssertEqual(rig.state.selection, 3, "the locked Hidden is the last block and stops it")
        rig.state.move(dx: -1, dy: 0)
        XCTAssertEqual(rig.state.selection, 2)
        rig.state.activate()
        XCTAssertNotNil(rig.state.openFolder)
        XCTAssertEqual(rig.state.folderApps.map(\.id), ["d"])
        rig.state.escape()
        XCTAssertNil(rig.state.openFolder)
        XCTAssertTrue(rig.launched.isEmpty)
    }
}
