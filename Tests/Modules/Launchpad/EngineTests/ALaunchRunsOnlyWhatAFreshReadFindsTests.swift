import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine

/// A launch opens a path only if a read made for this launch finds the id there and the bundle at that path still answers it.
/// Each refusal asserts the launcher was never called; the happy case, run first with the same fakes, is the control that
/// proves the launcher is reachable at all.
final class ALaunchRunsOnlyWhatAFreshReadFindsTests: XCTestCase {
    private func engine(_ catalog: FakeAppCatalog, _ launcher: FakeAppLauncher) -> LaunchpadEngine {
        LaunchpadEngine(catalog: catalog, launcher: launcher, store: LayoutStore(directory: scratchDirectory("launch")))
    }

    func testAnAppTheFreshReadFindsIsOpenedAtThePathOfThatRead() async {
        let catalog = FakeAppCatalog(["a"])
        let launcher = FakeAppLauncher()
        let engine = engine(catalog, launcher)
        _ = engine.read()
        catalog.reading = CatalogReading(apps: [CatalogApp(id: "a", name: "A", path: "/Applications/Moved/A.app")], complete: true)
        let outcome = await engine.launch("a")
        XCTAssertEqual(launcher.opened.count, 1)
        XCTAssertEqual(launcher.opened.first?.path, "/Applications/Moved/A.app", "the path of the second read, not the first")
        XCTAssertEqual(outcome, .launched)
    }

    func testAnIdTheFreshReadDoesNotHoldIsNotOpened() async {
        let catalog = FakeAppCatalog(["a", "b"])
        let launcher = FakeAppLauncher()
        let engine = engine(catalog, launcher)
        _ = engine.read()
        catalog.reading = CatalogReading(apps: [CatalogApp(id: "b", name: "B", path: "/Applications/b.app")], complete: true)
        let outcome = await engine.launch("a")
        XCTAssertEqual(outcome, .gone)
        XCTAssertTrue(launcher.opened.isEmpty)
    }

    func testABundleThatNowAnswersAnotherIdIsNotOpened() async {
        let catalog = FakeAppCatalog(["a"])
        let launcher = FakeAppLauncher()
        catalog.bundleIDs["/Applications/a.app"] = "somebody.else"
        let outcome = await engine(catalog, launcher).launch("a")
        XCTAssertEqual(outcome, .gone)
        XCTAssertTrue(launcher.opened.isEmpty)
    }

    func testAnIncompleteReadWithoutTheIdIsUnreadableAndOpensNothing() async {
        let launcher = FakeAppLauncher()
        let outcome = await engine(FakeAppCatalog(["b"], complete: false), launcher).launch("a")
        XCTAssertEqual(outcome, .unreadable)
        XCTAssertTrue(launcher.opened.isEmpty)
    }

    func testARefusalBySystemIsFailed() async {
        let launcher = FakeAppLauncher()
        launcher.answer = false
        let outcome = await engine(FakeAppCatalog(["a"]), launcher).launch("a")
        XCTAssertEqual(launcher.opened.count, 1)
        XCTAssertEqual(outcome, .failed)
    }

    func testAnIncompleteReadThatHoldsTheIdStillOpensIt() async {
        let launcher = FakeAppLauncher()
        let outcome = await engine(FakeAppCatalog(["a"], complete: false), launcher).launch("a")
        XCTAssertEqual(outcome, .launched, "incomplete only matters for an id that is missing")
        XCTAssertEqual(launcher.opened.map(\.path), ["/Applications/a.app"])
    }

    /// The real catalog over a real tree: an app one folder down is opened at its nested path, and once the
    /// bundle's identifier is changed on disk the same launch opens nothing.
    func testAnAppInAFolderIsOpenedWhereItIsAndNotOnceItsBundleChanged() async throws {
        let root = scratchDirectory("launch-folder")
        let contents = root.appendingPathComponent("Suite/Tool.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        func write(_ id: String) throws {
            try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": id], format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
        }
        try write("x.tool")
        let launcher = FakeAppLauncher()
        let engine = LaunchpadEngine(catalog: FileSystemAppCatalog(roots: [root]), launcher: launcher,
                                     store: LayoutStore(directory: scratchDirectory("launch-folder-store")))
        let first = await engine.launch("x.tool")
        XCTAssertEqual(first, .launched)
        XCTAssertEqual(launcher.opened.map(\.path), [root.appendingPathComponent("Suite/Tool.app").path])
        try write("somebody.else")
        let second = await engine.launch("x.tool")
        XCTAssertEqual(second, .gone)
        XCTAssertEqual(launcher.opened.count, 1, "no second open")
    }
}
