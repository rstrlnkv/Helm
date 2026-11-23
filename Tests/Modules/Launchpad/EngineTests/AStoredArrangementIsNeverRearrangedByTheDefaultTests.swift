import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine

/// The default arrangement is for a person who has none. A layout on disk is read as it is, however Apple-like the
/// apps; a layout that will not read shows the catalog's order, as its warning says, and is not replaced by the default.
final class AStoredArrangementIsNeverRearrangedByTheDefaultTests: XCTestCase {

    private func catalog() -> FakeAppCatalog {
        let catalog = FakeAppCatalog()
        catalog.reading = CatalogReading(apps: ["com.apple.mail", "com.apple.Safari", "com.apple.Terminal", "com.apple.Automator"]
            .map { CatalogApp(id: $0, name: $0, path: "/Applications/\($0).app") }, complete: true)
        return catalog
    }

    func testAStoredLayoutIsReadAsItIsAndNothingIsWritten() throws {
        let dir = scratchDirectory("stored-untouched")
        let store = LayoutStore(directory: dir)
        let mine = LaunchpadLayout(items: [.app("com.apple.mail"), .app("com.apple.Safari"), .app("com.apple.Terminal"), .app("com.apple.Automator")])
        XCTAssertTrue(store.save(mine))
        let before = try Data(contentsOf: store.fileURL)
        let engine = LaunchpadEngine(catalog: catalog(), launcher: FakeAppLauncher(), store: store)
        XCTAssertEqual(engine.read(reason: .refresh).layout, mine)
        XCTAssertEqual(try Data(contentsOf: store.fileURL), before)
    }

    func testAnUnreadableFileShowsTheCatalogOrderNotTheDefault() throws {
        let dir = scratchDirectory("stored-unreadable")
        try Data("{ broken".utf8).write(to: dir.appendingPathComponent("layout.json"))
        let engine = LaunchpadEngine(catalog: catalog(), launcher: FakeAppLauncher(), store: LayoutStore(directory: dir))
        XCTAssertEqual(engine.read(reason: .refresh).layout.items, ["com.apple.mail", "com.apple.Safari", "com.apple.Terminal", "com.apple.Automator"].map { .app($0) })
    }
}
