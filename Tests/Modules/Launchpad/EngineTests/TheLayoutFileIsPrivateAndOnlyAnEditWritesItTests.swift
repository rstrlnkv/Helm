import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine

/// The arrangement names no path but is still the person's: 0600 in a 0700 folder. Only an accepted edit writes
/// it; a refused edit writes nothing; a failed save is reported yet the result still comes back; a bad file is moved
/// aside once before the first save and never overwritten by a read.
final class TheLayoutFileIsPrivateAndOnlyAnEditWritesItTests: XCTestCase {

    private func mode(_ url: URL) throws -> Int {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int) ?? -1
    }

    func testTheFileAndItsFolderArePrivate() throws {
        let dir = scratchDirectory("private").appendingPathComponent("Launchpad")
        let engine = LaunchpadEngine(catalog: FakeAppCatalog(["a", "b"]), launcher: FakeAppLauncher(), store: LayoutStore(directory: dir))
        _ = engine.read(reason: .refresh)
        XCTAssertNotNil(engine.apply(.hide("a")))
        XCTAssertEqual(try mode(dir.appendingPathComponent("layout.json")), 0o600)
        XCTAssertEqual(try mode(dir), 0o700)
    }

    func testAReadWritesNothingAndARefusedEditWritesNothing() throws {
        let dir = scratchDirectory("only-edit")
        let engine = LaunchpadEngine(catalog: FakeAppCatalog(["a"]), launcher: FakeAppLauncher(), store: LayoutStore(directory: dir))
        _ = engine.read(reason: .refresh)
        XCTAssertEqual(tree(under: dir), [])
        XCTAssertNil(engine.apply(.hide("vanished")))
        XCTAssertEqual(tree(under: dir), [])
    }

    func testAFailedSaveIsReportedAndTheResultStillComes() throws {
        let blocker = scratchDirectory("blocked").appendingPathComponent("Launchpad")
        try Data("a file where the folder should be".utf8).write(to: blocker)
        tailTheLog()
        let engine = LaunchpadEngine(catalog: FakeAppCatalog(["a", "b"]), launcher: FakeAppLauncher(), store: LayoutStore(directory: blocker))
        let snap = try XCTUnwrap(engine.apply(.hide("a")))
        XCTAssertFalse(snap.saved)
        XCTAssertEqual(snap.layout.hidden, ["a"])
        XCTAssertFalse(loggedLines(LaunchpadEngine.moduleID).filter { $0.contains("could not be saved") }.isEmpty)
    }

    func testAnUnreadableFileIsLeftByReadsAndMovedAsideOnceBeforeTheFirstSave() throws {
        let dir = scratchDirectory("aside")
        let file = dir.appendingPathComponent("layout.json")
        let aside = dir.appendingPathComponent("layout.json.unreadable")
        try Data("{ broken".utf8).write(to: file)
        let engine = LaunchpadEngine(catalog: FakeAppCatalog(["b", "a"]), launcher: FakeAppLauncher(), store: LayoutStore(directory: dir))
        let snap = engine.read(reason: .refresh)
        XCTAssertEqual(snap.layoutRead, .unreadable)
        XCTAssertEqual(snap.layout.items, [.app("b"), .app("a")], "the catalog's order, nothing lost")
        XCTAssertEqual(try Data(contentsOf: file), Data("{ broken".utf8), "a read leaves the bad file where it is")
        XCTAssertNil(engine.apply(.hide("vanished")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: aside.path), "a refused edit moves nothing")
        XCTAssertNotNil(engine.apply(.hide("a")))
        XCTAssertEqual(try Data(contentsOf: aside), Data("{ broken".utf8))
        XCTAssertEqual(LayoutStore(directory: dir).load(), .loaded(LaunchpadLayout(items: [.app("b")], hidden: ["a"])))
        XCTAssertNotNil(engine.apply(.unhide("a")))
        XCTAssertEqual(try Data(contentsOf: aside), Data("{ broken".utf8), "the first bad file stays; no second move")
    }

    func testASecondBadFileReplacesTheEarlierOneAside() throws {
        let dir = scratchDirectory("aside-twice")
        let file = dir.appendingPathComponent("layout.json")
        let aside = dir.appendingPathComponent("layout.json.unreadable")
        let engine = LaunchpadEngine(catalog: FakeAppCatalog(["a", "b"]), launcher: FakeAppLauncher(), store: LayoutStore(directory: dir))
        try Data("first".utf8).write(to: file)
        XCTAssertNotNil(engine.apply(.hide("a")))
        XCTAssertEqual(try Data(contentsOf: aside), Data("first".utf8))
        try Data("second".utf8).write(to: file)
        XCTAssertNotNil(engine.apply(.hide("b")))
        XCTAssertEqual(try Data(contentsOf: aside), Data("second".utf8), "the newer bad file is not overwritten unseen")
        XCTAssertEqual(LayoutStore(directory: dir).load(), .loaded(LaunchpadLayout(items: [.app("a")], hidden: ["b"])))
    }

    /// The aside is a folder carrying the immutable flag, so replacing it is refused: the bad file stays, nothing is saved.
    func testABadFileThatCannotBeMovedAsideIsKeptAndNothingIsSaved() throws {
        let dir = scratchDirectory("aside-refused")
        let file = dir.appendingPathComponent("layout.json")
        let aside = dir.appendingPathComponent("layout.json.unreadable")
        try Data("{ broken".utf8).write(to: file)
        try FileManager.default.createDirectory(at: aside, withIntermediateDirectories: true)
        try Data("older".utf8).write(to: aside.appendingPathComponent("keep"))
        // Refuse the removal of the aside: the immutable flag on the folder stops `removeItem` and the rename over it.
        XCTAssertEqual(chflags(aside.path, UInt32(UF_IMMUTABLE)), 0)
        addTeardownBlock { _ = chflags(aside.path, 0) }
        tailTheLog()
        let engine = LaunchpadEngine(catalog: FakeAppCatalog(["a", "b"]), launcher: FakeAppLauncher(), store: LayoutStore(directory: dir))
        let snap = try XCTUnwrap(engine.apply(.hide("a")))
        XCTAssertFalse(snap.saved, "the edit is not on disk")
        XCTAssertEqual(snap.layout.hidden, ["a"], "the returned snapshot holds the edit")
        XCTAssertEqual(try Data(contentsOf: file), Data("{ broken".utf8), "the bad file is not overwritten")
        XCTAssertEqual(try Data(contentsOf: aside.appendingPathComponent("keep")), Data("older".utf8))
        XCTAssertFalse(loggedLines(LaunchpadEngine.moduleID).filter { $0.contains("could not be moved aside") }.isEmpty)
    }

    func testTheUnreadableWarningIsOnceForOneBadFileAndAgainForAnother() throws {
        let dir = scratchDirectory("warn-once")
        let file = dir.appendingPathComponent("layout.json")
        try Data("{ broken".utf8).write(to: file)
        tailTheLog()
        let store = LayoutStore(directory: dir)
        func warnings() -> Int { loggedLines(LaunchpadEngine.moduleID).filter { $0.contains("could not be read") }.count }
        XCTAssertEqual(store.load(), .unreadable)
        XCTAssertEqual(store.load(), .unreadable)
        XCTAssertEqual(warnings(), 1, "one warning for one bad file, however often it is read")
        try Data("{ broken differently, and longer".utf8).write(to: file)
        XCTAssertEqual(store.load(), .unreadable)
        XCTAssertEqual(warnings(), 2, "a different bad file is news again")
    }
}
