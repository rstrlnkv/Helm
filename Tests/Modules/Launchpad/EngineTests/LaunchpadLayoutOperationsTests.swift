import XCTest
@testable import Module_Launchpad_Engine

final class LaunchpadLayoutOperationsTests: XCTestCase {
    private func layout(_ ids: [String]) -> LaunchpadLayout { LaunchpadLayout(items: ids.map { .app($0) }) }

    func testMoveClampsItsIndex() {
        let l = layout(["a", "b", "c"]).applying(.move("a", toIndex: 99))
        XCTAssertEqual(l?.items, [.app("b"), .app("c"), .app("a")])
        XCTAssertEqual(layout(["a", "b"]).applying(.move("b", toIndex: -5))?.items, [.app("b"), .app("a")])
    }

    func testAVanishedIdIsRefused() {
        XCTAssertNil(layout(["a"]).applying(.hide("zz")))
        XCTAssertNil(layout(["a"]).applying(.move("zz", toIndex: 0)))
        XCTAssertNil(layout(["a", "b"]).applying(.makeFolder(drop: "a", onto: "zz", name: "F")))
    }

    func testAFolderTakesTheTargetsSlot() throws {
        let l = try XCTUnwrap(layout(["a", "b", "c"]).applying(.makeFolder(drop: "a", onto: "c", name: "F")))
        XCTAssertEqual(l.items.count, 2)
        guard case .folder(let f) = l.items[1] else { return XCTFail("no folder in the target's slot") }
        XCTAssertEqual(f.apps, ["c", "a"])
        XCTAssertEqual(l.items[0], .app("b"))
    }

    func testAFolderOfOneDissolvesAndAnEmptyOneGoes() throws {
        var l = try XCTUnwrap(layout(["a", "b"]).applying(.makeFolder(drop: "a", onto: "b", name: "F")))
        guard case .folder(let f) = l.items[0] else { return XCTFail() }
        l = try XCTUnwrap(l.applying(.hide("a")))
        XCTAssertEqual(l.items, [.app("b")])
        XCTAssertEqual(l.hidden, ["a"])
        XCTAssertNil(l.applying(.rename(f.id, to: "x")), "the folder is gone")
        let emptied = LaunchpadLayout(items: [.folder(.init(id: UUID(), name: "F", apps: [])), .app("z")]).normalized()
        XCTAssertEqual(emptied.items, [.app("z")], "an empty folder goes")
    }

    func testRemoveFromFolderLandsRightAfterIt() throws {
        var l = try XCTUnwrap(layout(["a", "b", "c", "d"]).applying(.makeFolder(drop: "a", onto: "b", name: "F")))
        guard case .folder(let f) = l.items[0] else { return XCTFail() }
        l = try XCTUnwrap(l.applying(.add("c", toFolder: f.id, at: nil)))
        l = try XCTUnwrap(l.applying(.remove("b", fromFolder: f.id)))
        XCTAssertEqual(l.items.map(\.itemID), [f.id.uuidString, "b", "d"])
    }

    func testRenameTrimsTruncatesAndRefusesEmpty() throws {
        let l = try XCTUnwrap(layout(["a", "b"]).applying(.makeFolder(drop: "a", onto: "b", name: "F")))
        guard case .folder(let f) = l.items[0] else { return XCTFail() }
        XCTAssertNil(l.applying(.rename(f.id, to: "   ")))
        let long = try XCTUnwrap(l.applying(.rename(f.id, to: "  " + String(repeating: "x", count: 500))))
        guard case .folder(let g) = long.items[0] else { return XCTFail() }
        XCTAssertEqual(g.name.count, LaunchpadLimits.maxFolderName)
    }

    func testHideTakesAnAppOutOfItsFolderAndUnhideAppendsIt() throws {
        var l = try XCTUnwrap(layout(["a", "b", "c"]).applying(.hide("a")))
        XCTAssertEqual(l.items, [.app("b"), .app("c")])
        l = try XCTUnwrap(l.applying(.unhide("a")))
        XCTAssertEqual(l.items.last, .app("a"))
        XCTAssertTrue(l.hidden.isEmpty)
    }

    func testReconcileAppendsNewDropsGoneAndIsIdempotent() {
        let l = layout(["a", "gone"]).reconciled(catalog: ["a", "b", "c"], complete: true)
        XCTAssertEqual(l.items, [.app("a"), .app("b"), .app("c")])
        XCTAssertEqual(l.reconciled(catalog: ["a", "b", "c"], complete: true), l)
    }

    func testHiddenAppsStayHiddenAcrossReconcile() {
        var l = layout(["a"])
        l.hidden = ["b"]
        XCTAssertEqual(l.reconciled(catalog: ["a", "b"], complete: true).items, [.app("a")])
    }

    func testNormalizedKeepsEachIdOnceAndHiddenWins() {
        var l = LaunchpadLayout(items: [.app("a"), .app("a"), .app("h")])
        l.hidden = ["h"]
        XCTAssertEqual(l.normalized().items, [.app("a")])
    }
}
