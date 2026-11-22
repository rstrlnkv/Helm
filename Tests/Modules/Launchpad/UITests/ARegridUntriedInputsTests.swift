import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// Inputs the grid change was not fed: an open card at the smallest and the largest grid, a drop still being written, the
/// page after a grid that cuts fewer pages, a store that holds the wrong thing, a press that changes nothing.
@MainActor final class ARegridUntriedInputsTests: XCTestCase {
    private let small = LaunchpadGridSettings(automatic: false, rows: 2, columns: 3, iconSize: 80)
    private let large = LaunchpadGridSettings(automatic: false, rows: 8, columns: 10, iconSize: 128)
    private let folderID = UUID()

    private func rig(count: Int = 40, folderApps: Int = 12, screen: CGSize = CGSize(width: 1280, height: 800)) -> LiftRig {
        let ids = (0..<count).map { String(format: "app%02d", $0) }
        let inside = Array(ids[0..<folderApps])
        let layout = LaunchpadLayout(items: [.folder(.init(id: folderID, name: "F", apps: inside))] + ids[folderApps...].map { .app($0) })
        return LiftRig(self, apps: ids, layout: layout, screen: screen)
    }

    private func flat(_ state: LaunchpadScreenState) -> [String] { state.pages.flatMap { $0.map(\.id) } }

    func testAnOpenCardStaysInsideTheWindowAtTheSmallestAndLargestGrid() {
        for screen in [CGSize(width: 1280, height: 800), CGSize(width: 1024, height: 640), CGSize(width: 640, height: 400)] {
            for settings in [small, large, .standard, small] {
                let r = rig(screen: screen)
                r.state.open(folder: folderID)
                r.state.move(dx: 1, dy: 0)
                r.state.regrid(settings)
                XCTAssertNotNil(r.state.openFolder, "\(screen) \(settings)")
                XCTAssertEqual(r.state.folderApps.count, 12)
                let card = LaunchpadSurface.Card(geometry: r.state.geometry, count: r.state.folderApps.count)
                XCTAssertTrue(CGRect(origin: .zero, size: r.state.geometry.size).contains(card.rect), "\(screen) \(settings): \(card.rect)")
                let origin = r.state.folderOrigin
                XCTAssertTrue(origin.x.isFinite && origin.y.isFinite)
                XCTAssertTrue(CGRect(origin: .zero, size: r.state.geometry.size).contains(origin), "\(screen) \(settings): \(origin)")
                XCTAssertTrue(r.state.selection.map { $0 < r.state.folderApps.count } ?? true)
            }
        }
    }

    func testADropStillBeingWrittenLandsOnTheNewGridInTheOrderTheEngineAnswered() async {
        let r = rig(count: 30, folderApps: 2)
        var release: CheckedContinuation<Void, Never>?
        var written = 0
        r.state.onPlace = { edit in
            await withCheckedContinuation { release = $0 }
            written += 1
            return r.engine.apply(edit)
        }
        r.lift(2)
        r.state.pointerMoved(r.margin(6), time: 1)
        r.state.tick(at: 1.2)
        r.state.pointerUp(r.margin(6), time: 1.3)
        await waitUntil("the write is out") { release != nil }
        r.state.regrid(small)
        XCTAssertNil(r.state.lift)
        release?.resume()
        await waitUntil("the edit was written") { written == 1 }
        func stored() -> [String] {
            r.engine.read(reason: .refresh).layout.items.compactMap { item -> String? in
                switch item { case .app(let id): id; case .folder(let f): f.id.uuidString; case .pageBreak: nil }
            }
        }
        await waitUntil("the pages show what was stored") { flat(r.state) == stored() && stored()[6] == "app03" }
        XCTAssertEqual(flat(r.state), stored(), "on the new capacity")
        XCTAssertTrue(r.state.pages.allSatisfy { $0.count <= r.state.geometry.capacity })
        XCTAssertEqual(Set(flat(r.state)).count, flat(r.state).count, "no tile twice")
    }

    func testThePageStaysOnTheChosenTileAndNeverBeyondTheLastPage() {
        let r = rig(count: 40, folderApps: 2)
        r.state.regrid(small)                        // capacity 6: many pages
        let many = r.state.pageCount
        XCTAssertGreaterThan(many, 4)
        r.state.go(to: many - 1)
        r.state.move(dx: 1, dy: 0)                   // a choice on the last page
        let chosen = r.state.selection
        XCTAssertNotNil(chosen)
        let id = r.state.pages[many - 1].first!.id
        r.state.regrid(large)                         // capacity 80: one page
        XCTAssertEqual(r.state.pageCount, 1)
        XCTAssertEqual(r.state.page, 0)
        XCTAssertEqual(r.state.selection, chosen, "the choice is the same tile")
        XCTAssertTrue(flat(r.state).contains(id))
        // no choice: the page the shown one began with
        let q = rig(count: 40, folderApps: 2)
        q.state.regrid(small)
        q.state.go(to: 3)
        let first = q.state.pages[3].first!.id
        q.state.regrid(.standard)
        XCTAssertTrue(q.state.pages[q.state.page].map(\.id).contains(first), "the page shows the tile the old page began with")
        XCTAssertLessThan(q.state.page, q.state.pageCount)
    }

    func testARegridWhileSearchingAndWhileTheSnapshotIsNotThereYet() {
        let r = rig()
        r.state.update(snapshot: nil)
        r.state.regrid(small)
        r.state.regrid(large)
        XCTAssertEqual(r.state.page, 0)
        r.state.update(snapshot: r.engine.read(reason: .refresh))
        XCTAssertEqual(r.state.pages[0].count, min(29, r.state.geometry.capacity))
    }

    func testTheSameGridTwiceChangesNothingTheSecondTime() {
        let r = rig()
        r.state.regrid(small)
        r.countChanges()
        r.state.regrid(small)
        XCTAssertEqual(r.changes, 0)
    }


    func testAPressHeldAcrossAGridChangeLaunchesNothingElseAndWritesNothing() throws {
        for slot in [1, 7] {
            let r = rig(count: 40, folderApps: 2)
            let bytes = try Data(contentsOf: r.layoutFile)
            let pressed = r.state.pages[0][slot].id
            XCTAssertTrue(r.state.pointerDown(r.core(slot), time: 0))
            r.state.regrid(small)
            r.state.pointerUp(r.core(slot), time: 0.1)
            XCTAssertTrue(r.launched.isEmpty || r.launched == [pressed], "slot \(slot): launched \(r.launched), pressed \(pressed)")
            XCTAssertNil(r.state.pressedID)
            XCTAssertTrue(r.placed.isEmpty)
            XCTAssertEqual(try Data(contentsOf: r.layoutFile), bytes)
        }
    }

    func testARegridWhileTheNameIsBeingEditedKeepsTheDraft() {
        let r = rig()
        r.state.open(folder: folderID)
        r.state.beginRenaming(selectAll: false)
        r.state.nameDraft = "Draft"
        r.state.regrid(small)
        XCTAssertTrue(r.state.renaming)
        XCTAssertEqual(r.state.nameDraft, "Draft")
        XCTAssertTrue(r.renamed.isEmpty, "a grid change renames nothing")
    }

    // MARK: - The model

    private final class CountingBacking: KeyValueStore {
        let inner = InMemoryKeyValueStore()
        private(set) var writes: [String] = []
        func object(forKey k: String) -> Any? { inner.object(forKey: k) }
        func set(_ v: Any?, forKey k: String) { writes.append(k); inner.set(v, forKey: k) }
    }

    private func model(_ backing: KeyValueStore) -> LaunchpadViewModel {
        let catalog = RigCatalog(["a"])
        let engine = LaunchpadEngine(catalog: catalog, launcher: RigLauncher(), store: LayoutStore(directory: scratchDirectory("grid-model")))
        return LaunchpadViewModel(work: engine, store: NamespacedStore(namespace: "test", backing: backing))
    }

    func testResetOnTheStandardGridAndTheSameGridTwiceWriteNothing() {
        let backing = CountingBacking()
        let m = model(backing)
        m.resetGrid()
        m.setGrid(.standard)
        XCTAssertTrue(backing.writes.isEmpty, "\(backing.writes)")
        var next = LaunchpadGridSettings.standard
        next.iconSize = 90.4
        m.setGrid(next)
        XCTAssertEqual(backing.writes, ["module.test." + LaunchpadGridSettings.Key.iconSize])
        next.iconSize = 89.6                           // rounds to the same 90
        m.setGrid(next)
        XCTAssertEqual(backing.writes.count, 1, "the same whole point is the same grid")
        m.resetGrid()
        XCTAssertEqual(backing.writes.count, 2)
        XCTAssertEqual(m.grid, .standard)
        m.resetGrid()
        XCTAssertEqual(backing.writes.count, 2, "a second reset writes nothing")
    }

    func testADragOfTheSliderWritesOnceWhenItEnds() {
        let backing = CountingBacking()
        let m = model(backing)
        var value = 48.0
        while value <= 128 {
            var next = m.grid
            next.iconSize = value
            m.setGrid(next, live: true)
            value += 0.25                             // a finer drag than the slider's step
        }
        XCTAssertEqual(m.grid.iconSize, 128, "the grid followed the drag")
        XCTAssertTrue(backing.writes.isEmpty, "nothing is written while the drag goes on")
        m.commitGrid()
        XCTAssertEqual(backing.writes, ["module.test." + LaunchpadGridSettings.Key.iconSize], "one write when it ends")
        m.commitGrid()
        XCTAssertEqual(backing.writes.count, 1, "a second commit has nothing to write")
    }

    func testAStoreHoldingWrongTypesUnderTheKeysReadsTheStandardGrid() {
        let wrong: [Any] = ["yes", [1, 2], ["a": 1], Data([1]), Date(), 2.5, NSNull()]
        for value in wrong {
            let backing = InMemoryKeyValueStore()
            for key in [LaunchpadGridSettings.Key.automatic, LaunchpadGridSettings.Key.rows, LaunchpadGridSettings.Key.columns,
                        LaunchpadGridSettings.Key.iconSize] { backing.set(value, forKey: "module.test." + key) }
            let m = model(backing)
            XCTAssertTrue(LaunchpadGridSettings.rowRange.contains(m.grid.rows), "\(value)")
            XCTAssertTrue(LaunchpadGridSettings.columnRange.contains(m.grid.columns), "\(value)")
            XCTAssertTrue(LaunchpadGridSettings.iconRange.contains(m.grid.iconSize), "\(value)")
            if !(value is Double) { XCTAssertTrue(m.grid.automatic, "\(value): a wrong type for the switch is the default") }
        }
    }

    func testTheStoreEditedBehindTheModelsBackShowsAtTheNextOpenAndWritesNothingBack() {
        let backing = CountingBacking()
        let m = model(backing)
        backing.inner.set(false, forKey: "module.test." + LaunchpadGridSettings.Key.automatic)
        backing.inner.set(99, forKey: "module.test." + LaunchpadGridSettings.Key.rows)
        m.reloadGrid()
        XCTAssertFalse(m.grid.automatic)
        XCTAssertEqual(m.grid.rows, 8, "clamped")
        XCTAssertTrue(backing.writes.isEmpty, "a read writes nothing back")
        m.stop()
        m.setGrid(.standard)
        XCTAssertFalse(m.grid.automatic, "a stopped model takes nothing")
    }
}

final class AGridFuzzTests: XCTestCase {
    func testEveryScreenAndEverySettingKeepsTheGridInsideTheWindow() {
        var bad: [String] = []
        for w in stride(from: 800.0, through: 1600, by: 160) { for h in stride(from: 480.0, through: 1000, by: 40) {
            for rows in [2, 5, 8] { for columns in [3, 6, 10] { for icon in [48.0, 80, 128] { for auto in [true, false] {
                let s = LaunchpadGridSettings(automatic: auto, rows: rows, columns: columns, iconSize: icon)
                let g = LaunchpadGeometry.make(for: CGSize(width: w, height: h), topSafe: 0, settings: s)
                let bottom = g.gridTop + g.pageHeight
                if bottom > g.size.height - g.dotsRoom + 0.5 || g.icon > g.cellWidth - g.chrome + 0.5 {
                    bad.append("\(Int(w))x\(Int(h)) \(s.automatic ? "auto" : "\(columns)x\(rows)") icon \(Int(icon)): bottom \(Int(bottom)) of \(Int(h - g.dotsRoom)), icon \(Int(g.icon)) cell \(Int(g.cellWidth))")
                }
                let card = LaunchpadSurface.Card(geometry: g, count: 200)
                if !CGRect(origin: .zero, size: g.size).contains(card.rect) { bad.append("card \(Int(w))x\(Int(h)) \(columns)x\(rows)") }
            } } } }
        } }
        XCTAssertTrue(bad.isEmpty, "\(bad.count) outside; first: \(bad.prefix(3))")
    }
}
