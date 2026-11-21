import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine

/// A launch is counted once, after the system opened the app, in a private file of its own that survives the engine.
/// Each refusal first proves the launcher was reached (or not) the way the case says, so a count that is absent is absent
/// for the reason under test; the layout file is never touched by a count.
final class ALaunchCountIsWrittenOnceOnASuccessfulLaunchAndNeverLostTests: XCTestCase {
    private func rig(_ label: String, ids: [String] = ["a", "b"]) -> (engine: LaunchpadEngine, launcher: FakeAppLauncher, catalog: FakeAppCatalog, dir: URL) {
        let dir = scratchDirectory(label)
        let catalog = FakeAppCatalog(ids)
        let launcher = FakeAppLauncher()
        return (LaunchpadEngine(catalog: catalog, launcher: launcher, store: LayoutStore(directory: dir)), launcher, catalog, dir)
    }

    private func counts(_ dir: URL) -> [String: Int] { LaunchCountStore(directory: dir).load().counts }

    func testASuccessfulLaunchWritesOneAndASecondWritesTwoAndItSurvivesAFreshEngine() async throws {
        let (engine, launcher, _, dir) = rig("counts-once")
        let first = await engine.launch("a")
        XCTAssertEqual(first, .launched)
        XCTAssertEqual(launcher.opened.count, 1, "the system was asked once")
        XCTAssertEqual(counts(dir), ["a": 1])
        let second = await engine.launch("a")
        XCTAssertEqual(second, .launched)
        XCTAssertEqual(counts(dir), ["a": 2])
        let fresh = LaunchpadEngine(catalog: FakeAppCatalog(["a", "b"]), launcher: FakeAppLauncher(), store: LayoutStore(directory: dir))
        XCTAssertEqual(fresh.read().launchCounts, ["a": 2], "a new engine reads what the file holds")
    }

    func testAGoneUnreadableOrRefusedLaunchWritesNothing() async {
        let (engine, launcher, catalog, dir) = rig("counts-refused")
        let gone = await engine.launch("vanished")
        XCTAssertEqual(gone, .gone)
        XCTAssertTrue(launcher.opened.isEmpty)
        catalog.reading = CatalogReading(apps: [CatalogApp(id: "b", name: "B", path: "/Applications/b.app")], complete: false)
        let unreadable = await engine.launch("a")
        XCTAssertEqual(unreadable, .unreadable)
        XCTAssertTrue(launcher.opened.isEmpty)
        catalog.reading = CatalogReading(apps: [CatalogApp(id: "a", name: "A", path: "/Applications/a.app")], complete: true)
        launcher.answer = false
        let failed = await engine.launch("a")
        XCTAssertEqual(failed, .failed)
        XCTAssertEqual(launcher.opened.count, 1, "the system was reached and said no: the control that the refusal is its answer")
        XCTAssertEqual(tree(under: dir), [], "no count file, and no layout file either")
    }

    func testACountNeverTouchesTheLayoutFile() async throws {
        let (engine, _, _, dir) = rig("counts-layout")
        XCTAssertNotNil(engine.apply(.hide("b")))
        let layout = dir.appendingPathComponent("layout.json")
        let before = try Data(contentsOf: layout)
        let outcome = await engine.launch("a")
        XCTAssertEqual(outcome, .launched)
        XCTAssertEqual(counts(dir), ["a": 1])
        XCTAssertEqual(try Data(contentsOf: layout), before)
    }

    func testACountStopsAtTheCeilingAndAFileBeyondItReadsAsTheCeiling() async throws {
        let (engine, _, _, dir) = rig("counts-ceiling")
        let ceiling = LaunchpadLimits.maxLaunchCount
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"version":1,"counts":{"a":5000000000}}"#.utf8).write(to: dir.appendingPathComponent("launch-counts.json"))
        XCTAssertEqual(engine.read().launchCounts, ["a": ceiling], "a file beyond the ceiling reads as the ceiling")
        let outcome = await engine.launch("a")
        XCTAssertEqual(outcome, .launched)
        XCTAssertEqual(counts(dir), ["a": ceiling], "one more launch does not pass it")
        let written = try String(contentsOf: dir.appendingPathComponent("launch-counts.json"), encoding: .utf8)
        XCTAssertTrue(written.contains("\"a\":\(ceiling)}"), "the file itself holds the ceiling, not one past it: \(written)")
    }

    func testResetEmptiesTheCountsAndWritesNothingWhenThereAreNone() async throws {
        let (engine, _, _, dir) = rig("counts-reset")
        XCTAssertNotNil(engine.resetLaunchCounts())
        XCTAssertEqual(tree(under: dir), [], "nothing to reset, nothing written")
        let outcome = await engine.launch("a")
        XCTAssertEqual(outcome, .launched)
        XCTAssertEqual(counts(dir), ["a": 1], "the control: there was something to reset")
        let snap = try XCTUnwrap(engine.resetLaunchCounts())
        XCTAssertEqual(snap.launchCounts, [:])
        XCTAssertTrue(snap.saved)
        XCTAssertEqual(counts(dir), [:])
        XCTAssertEqual(LaunchCountStore(directory: dir).load(), .loaded(.empty), "an empty document, not a missing file")
    }

    func testTheFileIsPrivate() async throws {
        let dir = scratchDirectory("counts-private").appendingPathComponent("Launchpad")
        let engine = LaunchpadEngine(catalog: FakeAppCatalog(["a"]), launcher: FakeAppLauncher(), store: LayoutStore(directory: dir))
        let outcome = await engine.launch("a")
        XCTAssertEqual(outcome, .launched)
        let mode = { (url: URL) in (try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int) ?? -1 }
        XCTAssertEqual(mode(dir.appendingPathComponent("launch-counts.json")), 0o600)
        XCTAssertEqual(mode(dir), 0o700)
    }
}
