import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine

/// An unreadable folder looks like an uninstalled app, so an incomplete read must not make an app fall out
/// of the arrangement; and reading is not a reason to write the file.
final class AnIncompleteReadDropsNothingTests: XCTestCase {

    func testReconcileDropsNothingWhenTheReadWasIncomplete() {
        var layout = LaunchpadLayout(items: [.app("a"), .app("gone"), .folder(.init(id: UUID(), name: "F", apps: ["x", "y"]))])
        layout.hidden = ["h"]
        let out = layout.reconciled(catalog: ["a"], complete: false)
        XCTAssertEqual(out, layout)
        XCTAssertNotEqual(layout.reconciled(catalog: ["a"], complete: true), layout, "the same read, complete, does drop them")
    }

    func testAHiddenAppThatIsNotInstalledIsForgottenOnlyByACompleteRead() {
        var layout = LaunchpadLayout(items: [.app("a")])
        layout.hidden = ["gone", "a2"]
        XCTAssertEqual(layout.reconciled(catalog: ["a", "a2"], complete: false).hidden, ["gone", "a2"], "unreadable folder, not uninstalled")
        XCTAssertEqual(layout.reconciled(catalog: ["a", "a2"], complete: true).hidden, ["a2"])
    }

    func testReadingNeverWritesTheFile() throws {
        let dir = scratchDirectory("incomplete-read")
        let store = LayoutStore(directory: dir)
        XCTAssertTrue(store.save(LaunchpadLayout(items: [.app("a"), .app("b")])))
        let before = try Data(contentsOf: store.fileURL)
        let mtime = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.modificationDate] as? Date
        let catalog = FakeAppCatalog(["b", "new"], complete: false)
        let engine = LaunchpadEngine(catalog: catalog, store: store)
        for _ in 0..<3 { _ = engine.read() }
        catalog.reading = CatalogReading(apps: [], complete: true)
        _ = engine.read()
        XCTAssertEqual(try Data(contentsOf: store.fileURL), before)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.modificationDate] as? Date, mtime)
    }

    func testAnEditDuringAnIncompleteReadSavesTheAppsTheReadCouldNotSee() throws {
        let store = LayoutStore(directory: scratchDirectory("incomplete-edit"))
        XCTAssertTrue(store.save(LaunchpadLayout(items: [.app("a"), .app("b"), .app("c")])))
        let engine = LaunchpadEngine(catalog: FakeAppCatalog(["a", "c"], complete: false), store: store)
        _ = engine.read()
        XCTAssertNotNil(engine.apply(.hide("a")))
        XCTAssertEqual(store.load(), .loaded(LaunchpadLayout(items: [.app("b"), .app("c")], hidden: ["a"])), "b was in a folder that would not open")
    }

    func testAnIncompleteReadShowsTheSavedAppsThatAreMissing() {
        let dir = scratchDirectory("incomplete-snap")
        let store = LayoutStore(directory: dir)
        XCTAssertTrue(store.save(LaunchpadLayout(items: [.app("a"), .app("b")])))
        let snap = LaunchpadEngine(catalog: FakeAppCatalog(["a"], complete: false), store: store).read()
        XCTAssertEqual(snap.layout.items, [.app("a"), .app("b")])
        XCTAssertFalse(snap.catalogComplete)
    }
}
