import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine

/// Gestures nobody planned for: edits on ids that vanished, an app dropped onto itself, a drop between two
/// folders, a folder shrunk to one, hidden apps that sit in a folder, and a reconcile run twice.
final class LaunchpadHostileEditsTests: XCTestCase {
    private func flat(_ ids: [String]) -> LaunchpadLayout { LaunchpadLayout(items: ids.map { .app($0) }) }

    private func folder(_ l: LaunchpadLayout, at i: Int, file: StaticString = #filePath, line: UInt = #line) -> LaunchpadLayout.Folder {
        guard i < l.items.count, case .folder(let f) = l.items[i] else {
            XCTFail("no folder at \(i): \(l.items)", file: file, line: line)
            return .init(id: UUID(), name: "", apps: [])
        }
        return f
    }

    private func everyIDOnce(_ l: LaunchpadLayout, file: StaticString = #filePath, line: UInt = #line) {
        var all = l.hidden.sorted()
        for item in l.items {
            switch item {
            case .app(let id): all.append(id)
            case .folder(let f): all += f.apps
            }
        }
        XCTAssertEqual(all.count, Set(all).count, "an id stands twice: \(all)", file: file, line: line)
    }

    // MARK: Refusals

    func testADropOntoItselfIsRefused() {
        XCTAssertNil(flat(["a", "b"]).applying(.makeFolder(drop: "a", onto: "a", name: "F")))
    }

    func testADropOntoAFolderOrOfAFolderOrOfAHiddenAppIsRefused() throws {
        var l = try XCTUnwrap(flat(["a", "b", "c"]).applying(.makeFolder(drop: "a", onto: "b", name: "F")))
        let f = folder(l, at: 0)
        XCTAssertNil(l.applying(.makeFolder(drop: "c", onto: f.id.uuidString, name: "G")), "a folder id is not an app")
        XCTAssertNil(l.applying(.makeFolder(drop: f.id.uuidString, onto: "c", name: "G")), "a folder id is not an app")
        l = try XCTUnwrap(l.applying(.hide("c")))
        XCTAssertNil(l.applying(.makeFolder(drop: "c", onto: "b", name: "G")), "a hidden app is not on the grid")
    }

    func testEditsNamingTheWrongFolderOrTheWrongAppAreRefused() throws {
        let l = try XCTUnwrap(flat(["a", "b", "c", "d"]).applying(.makeFolder(drop: "a", onto: "b", name: "F")))
        let f = folder(l, at: 0)
        let ghost = UUID()
        XCTAssertNil(l.applying(.add("c", toFolder: ghost, at: nil)))
        XCTAssertNil(l.applying(.add("zz", toFolder: f.id, at: nil)))
        XCTAssertNil(l.applying(.add("a", toFolder: f.id, at: nil)), "already inside")
        XCTAssertNil(l.applying(.remove("c", fromFolder: f.id)), "c is not in that folder")
        XCTAssertNil(l.applying(.remove("a", fromFolder: ghost)))
        XCTAssertNil(l.applying(.moveInFolder("c", toIndex: 0)), "c is not in any folder")
        XCTAssertNil(l.applying(.rename(ghost, to: "x")))
        XCTAssertNil(l.applying(.unhide("c")), "c is not hidden")
        XCTAssertNil(l.applying(.hide("zz")))
        let hidden = try XCTUnwrap(l.applying(.hide("c")))
        XCTAssertNil(hidden.applying(.hide("c")), "hiding twice")
        XCTAssertNil(hidden.applying(.move("c", toIndex: 0)), "a hidden app does not move")
    }

    // MARK: Folders between each other

    func testAnAppDroppedIntoAnotherFolderLeavesTheFirstAndTheFirstDissolvesWhenOneIsLeft() throws {
        var l = try XCTUnwrap(flat(["a", "b", "c", "d"]).applying(.makeFolder(drop: "a", onto: "b", name: "F1")))
        l = try XCTUnwrap(l.applying(.makeFolder(drop: "c", onto: "d", name: "F2")))
        XCTAssertEqual(l.items.count, 2)
        let f1 = folder(l, at: 0), f2 = folder(l, at: 1)
        XCTAssertEqual(f1.apps, ["b", "a"])
        let out = try XCTUnwrap(l.applying(.add("a", toFolder: f2.id, at: 0)))
        XCTAssertEqual(out.items.count, 2)
        XCTAssertEqual(out.items[0], .app("b"), "F1 was left with one app and dissolved in place")
        XCTAssertEqual(folder(out, at: 1).apps, ["a", "d", "c"])
        everyIDOnce(out)
    }

    func testTakingTheSecondLastAppOutOfAFolderLeavesTheAppsInPlaceNotLost() throws {
        let l = try XCTUnwrap(flat(["a", "b", "c"]).applying(.makeFolder(drop: "a", onto: "b", name: "F")))
        let f = folder(l, at: 0)
        let out = try XCTUnwrap(l.applying(.remove("b", fromFolder: f.id)))
        XCTAssertEqual(out.items, [.app("a"), .app("b"), .app("c")])
        XCTAssertNil(out.applying(.rename(f.id, to: "x")), "the folder is gone")
        XCTAssertNil(out.applying(.remove("a", fromFolder: f.id)), "and its id is stale")
        everyIDOnce(out)
    }

    func testADropFromInsideAFolderOntoAnAppDissolvesTheFolderAndKeepsEachIdOnce() throws {
        let l = try XCTUnwrap(flat(["a", "b", "c"]).applying(.makeFolder(drop: "a", onto: "b", name: "F")))
        let out = try XCTUnwrap(l.applying(.makeFolder(drop: "a", onto: "c", name: "G")))
        XCTAssertEqual(out.items.count, 2)
        XCTAssertEqual(out.items[0], .app("b"))
        XCTAssertEqual(folder(out, at: 1).apps, ["c", "a"])
        everyIDOnce(out)
    }

    func testAFolderMovesByItsUUIDString() throws {
        let l = try XCTUnwrap(flat(["a", "b", "c"]).applying(.makeFolder(drop: "a", onto: "b", name: "F")))
        let f = folder(l, at: 0)
        let out = try XCTUnwrap(l.applying(.move(f.id.uuidString, toIndex: 5)))
        XCTAssertEqual(out.items.map(\.itemID), ["c", f.id.uuidString])
    }

    // MARK: Hidden inside a folder

    func testHidingAnAppInAFolderThenUnhidingPutsItOnTheGridNotBackInTheFolder() throws {
        var l = try XCTUnwrap(flat(["a", "b", "c", "d"]).applying(.makeFolder(drop: "a", onto: "b", name: "F")))
        let f = folder(l, at: 0)
        l = try XCTUnwrap(l.applying(.add("c", toFolder: f.id, at: nil)))
        l = try XCTUnwrap(l.applying(.hide("a")))
        XCTAssertEqual(folder(l, at: 0).apps, ["b", "c"])
        XCTAssertEqual(l.hidden, ["a"])
        l = try XCTUnwrap(l.applying(.unhide("a")))
        XCTAssertEqual(folder(l, at: 0).apps, ["b", "c"])
        XCTAssertEqual(l.items.last, .app("a"))
        XCTAssertTrue(l.hidden.isEmpty)
        everyIDOnce(l)
    }

    func testHidingTheTwoAppsOfAFolderOneAfterTheOtherLeavesNoFolderAndNothingLost() throws {
        var l = try XCTUnwrap(flat(["a", "b", "c"]).applying(.makeFolder(drop: "a", onto: "b", name: "F")))
        l = try XCTUnwrap(l.applying(.hide("a")))
        XCTAssertEqual(l.items, [.app("b"), .app("c")])
        l = try XCTUnwrap(l.applying(.hide("b")))
        XCTAssertEqual(l.items, [.app("c")])
        XCTAssertEqual(l.hidden, ["a", "b"])
    }

    // MARK: A file nobody wrote by hand

    private func engine(reading ids: [String], file json: String, complete: Bool = true) throws -> (LaunchpadEngine, URL) {
        let dir = scratchDirectory("hostile")
        try Data(json.utf8).write(to: dir.appendingPathComponent("layout.json"))
        return (LaunchpadEngine(catalog: FakeAppCatalog(ids, complete: complete), store: LayoutStore(directory: dir)), dir)
    }

    func testAFolderWhoseAppsAreAllHiddenIsGoneAndTheAppsStayHidden() throws {
        let (engine, _) = try engine(reading: ["x", "y", "z"],
                                     file: #"{"items":[{"folder":{"id":"\#(UUID().uuidString)","name":"F","apps":["x","y"]}},{"app":"z"}],"hidden":["x","y"]}"#)
        let snap = engine.read()
        XCTAssertEqual(snap.layout.items, [.app("z")])
        XCTAssertEqual(snap.layout.hidden, ["x", "y"])
        XCTAssertEqual(snap.search("x"), [], "a hidden app is not found (the fake names are capitalised ids)")
        XCTAssertEqual(snap.search("z"), ["z"])
    }

    func testAFolderWithOneVisibleAppLeftByTheHiddenListDissolves() throws {
        let (engine, _) = try engine(reading: ["x", "y"],
                                     file: #"{"items":[{"folder":{"id":"\#(UUID().uuidString)","name":"F","apps":["x","y"]}}],"hidden":["x"]}"#)
        XCTAssertEqual(engine.read().layout.items, [.app("y")])
    }

    func testTwoFoldersWithTheSameIdInTheFileGetDistinctIds() throws {
        let id = UUID().uuidString
        let (engine, _) = try engine(reading: ["a", "b", "c", "d"],
                                     file: #"{"items":[{"folder":{"id":"\#(id)","name":"One","apps":["a","b"]}},{"folder":{"id":"\#(id)","name":"Two","apps":["c","d"]}}]}"#)
        let ids = engine.read().layout.items.map(\.itemID)
        XCTAssertEqual(ids.count, 2)
        XCTAssertEqual(Set(ids).count, 2, "a rename or an add by folder id must reach one folder only: \(ids)")
    }

    // MARK: Reconcile twice

    func testReconcileIsIdempotentOverFoldersHiddenAndEveryCatalogShape() throws {
        var l = try XCTUnwrap(flat(["a", "b", "c", "d", "e"]).applying(.makeFolder(drop: "a", onto: "b", name: "F")))
        l = try XCTUnwrap(l.applying(.hide("e")))
        let catalogs: [[String]] = [[], ["c"], ["a", "b", "c", "d", "e"], ["b", "z", "c"], ["a", "a", "z", "z"], ["e", "d"]]
        for catalog in catalogs {
            for complete in [true, false] {
                let once = l.reconciled(catalog: catalog, complete: complete)
                XCTAssertEqual(once.reconciled(catalog: catalog, complete: complete), once, "\(catalog) complete=\(complete)")
                everyIDOnce(once)
            }
        }
    }

    func testReconcileDissolvesAFolderWhoseAppsWentAwayAndStaysPut() {
        let id = UUID()
        let l = LaunchpadLayout(items: [.app("x"), .folder(.init(id: id, name: "F", apps: ["a", "gone"]))])
        let out = l.reconciled(catalog: ["x", "a"], complete: true)
        XCTAssertEqual(out.items, [.app("x"), .app("a")])
        XCTAssertEqual(out.reconciled(catalog: ["x", "a"], complete: true), out)
        XCTAssertEqual(l.reconciled(catalog: ["x"], complete: true).items, [.app("x")], "a folder with nothing left goes")
    }

    func testAnEngineReadTwiceAnswersTheSame() throws {
        let (engine, dir) = try engine(reading: ["a", "b"], file: #"{"items":[{"app":"b"}]}"#)
        let first = engine.read(), second = engine.read()
        XCTAssertEqual(first.layout, second.layout)
        XCTAssertEqual(first.layout.items, [.app("b"), .app("a")])
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("layout.json")), Data(#"{"items":[{"app":"b"}]}"#.utf8))
    }

    // MARK: Through the engine

    func testAnEditOnAnIdThatLeftTheCatalogIsRefusedAndWritesNothing() throws {
        let dir = scratchDirectory("hostile-vanished")
        let store = LayoutStore(directory: dir)
        XCTAssertTrue(store.save(flat(["a", "gone"])))
        let before = try Data(contentsOf: store.fileURL)
        let engine = LaunchpadEngine(catalog: FakeAppCatalog(["a"]), store: store)
        _ = engine.read()
        XCTAssertNil(engine.apply(.hide("gone")))
        XCTAssertNil(engine.apply(.move("gone", toIndex: 0)))
        XCTAssertEqual(try Data(contentsOf: store.fileURL), before)
    }

    // MARK: Names

    func testAFolderMadeWithAHugeNameIsBoundedLikeARenameAndLikeALoad() throws {
        let l = try XCTUnwrap(flat(["a", "b"]).applying(.makeFolder(drop: "a", onto: "b", name: String(repeating: "x", count: 5_000))))
        XCTAssertLessThanOrEqual(folder(l, at: 0).name.count, LaunchpadLimits.maxFolderName)
    }

    func testAFolderMadeWithAnEmptyOrBlankNameDoesNotHoldABlankName() throws {
        for name in ["", "   \n"] {
            XCTAssertNil(flat(["a", "b"]).applying(.makeFolder(drop: "a", onto: "b", name: name)), "refused, as a rename to blank is")
        }
    }
}
