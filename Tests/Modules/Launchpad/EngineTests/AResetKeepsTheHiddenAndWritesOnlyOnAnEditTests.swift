import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine

/// A reset puts every shown app back in the catalog's order with no folder, and the hidden apps stay hidden:
/// the person asked for the arrangement to go, not for what they hid to come back. It overwrites the file only
/// as an edit does, so a read alone still writes nothing.
final class AResetKeepsTheHiddenAndWritesOnlyOnAnEditTests: XCTestCase {

    private func arranged(_ dir: URL) -> LayoutStore {
        let store = LayoutStore(directory: dir)
        var layout = LaunchpadLayout(items: [.folder(.init(id: UUID(), name: "F", apps: ["d", "b"])), .app("c"), .app("a")])
        layout.hidden = ["e"]
        XCTAssertTrue(store.save(layout))
        return store
    }

    func testAnArrangedLayoutGoesBackToTheCatalogOrderAndKeepsTheHidden() throws {
        let dir = scratchDirectory("reset-arranged")
        let store = arranged(dir)
        let engine = LaunchpadEngine(catalog: FakeAppCatalog(["a", "b", "c", "d", "e"]), launcher: FakeAppLauncher(), store: store)
        let snap = try XCTUnwrap(engine.resetArrangement())
        let expected = LaunchpadLayout(items: [.app("a"), .app("b"), .app("c"), .app("d")], hidden: ["e"])
        XCTAssertEqual(snap.layout, expected, "returned: alphabetical, no folder, e still hidden")
        XCTAssertEqual(store.load(), .loaded(expected), "and on disk")
        XCTAssertTrue(snap.saved)
        let mode = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
        XCTAssertEqual(engine.read().layout, expected, "a read after it says the same")
    }

    func testAnIncompleteReadResetKeepsTheAppsItCouldNotSeeOutOfTheFolders() throws {
        let store = arranged(scratchDirectory("reset-incomplete"))
        let engine = LaunchpadEngine(catalog: FakeAppCatalog(["a", "c", "e"], complete: false), launcher: FakeAppLauncher(), store: store)
        let snap = try XCTUnwrap(engine.resetArrangement())
        XCTAssertEqual(snap.layout.hidden, ["e"])
        XCTAssertEqual(snap.layout.items, [.app("a"), .app("c")])
    }

    func testAnUnreadableFileIsMovedAsideOnceAndAnEmptyCatalogDoesNotTrap() throws {
        let dir = scratchDirectory("reset-unreadable")
        try Data("{ broken".utf8).write(to: dir.appendingPathComponent("layout.json"))
        let engine = LaunchpadEngine(catalog: FakeAppCatalog(["b", "a"]), launcher: FakeAppLauncher(), store: LayoutStore(directory: dir))
        let snap = try XCTUnwrap(engine.resetArrangement())
        XCTAssertEqual(snap.layout.items, [.app("b"), .app("a")], "the catalog's order as it came")
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("layout.json.unreadable")), Data("{ broken".utf8))

        let empty = LaunchpadEngine(catalog: FakeAppCatalog([]), launcher: FakeAppLauncher(), store: LayoutStore(directory: scratchDirectory("reset-empty")))
        XCTAssertEqual(try XCTUnwrap(empty.resetArrangement()).layout, LaunchpadLayout())
    }

    func testAReadAloneNeverWritesAndAResetWritesOnce() throws {
        let dir = scratchDirectory("reset-reads")
        let engine = LaunchpadEngine(catalog: FakeAppCatalog(["a", "b"]), launcher: FakeAppLauncher(), store: LayoutStore(directory: dir))
        for _ in 0..<3 { _ = engine.read() }
        XCTAssertEqual(tree(under: dir), [])
        XCTAssertNotNil(engine.resetArrangement())
        XCTAssertEqual(tree(under: dir), ["layout.json"])
    }
}
