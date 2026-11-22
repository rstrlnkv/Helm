import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine

/// A counts file that is planted, torn, oversize or from a newer build never stops a read: the order falls back, the bad file
/// is left alone by every read, and the first launch moves it aside once and writes fresh. Each input first proves the file is
/// there and the read still answers.
final class AnUnreadableCountsFileNeverBreaksTheWindowTests: XCTestCase {
    private func engine(_ dir: URL) -> LaunchpadEngine {
        LaunchpadEngine(catalog: FakeAppCatalog(["a", "b"]), launcher: FakeAppLauncher(), store: LayoutStore(directory: dir))
    }

    private func plant(_ data: Data, _ label: String) throws -> (dir: URL, file: URL) {
        let dir = scratchDirectory(label)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("launch-counts.json")
        try data.write(to: file)
        return (dir, file)
    }

    private func doc(_ counts: String, version: Int = 1) -> Data { Data(#"{"version":\#(version),"counts":\#(counts)}"#.utf8) }

    func testEachBadFileReadsWithoutBreakingAndWithoutChangingAByte() throws {
        let oversize = Data(repeating: 0x20, count: LaunchpadLimits.maxFileBytes + 10)
        let tooMany = "{" + (0...LaunchpadLimits.maxCountedApps).map { "\"id\($0)\":1" }.joined(separator: ",") + "}"
        let longID = String(repeating: "x", count: LaunchpadLimits.maxStringLength + 1)
        let cases: [(String, Data, expect: [String: Int]?)] = [
            ("garbage", Data("{ broken".utf8), nil),
            ("oversize", oversize, nil),
            ("version 2", doc(#"{"a":1}"#, version: 2), nil),
            ("version 0", doc(#"{"a":1}"#, version: 0), nil),
            ("version -1", doc(#"{"a":1}"#, version: -1), nil),
            ("wrong shape", Data("[1,2,3]".utf8), nil),
            ("counts is a list", doc("[1]"), nil),
            ("negative", doc(#"{"a":-5,"b":3}"#), ["b": 3]),
            ("fractional", doc(#"{"a":2.9}"#), ["a": 2]),
            ("huge", doc(#"{"a":1e300,"b":1e999}"#), ["a": LaunchpadLimits.maxLaunchCount]),
            ("string count", doc(#"{"a":"7","b":4}"#), ["b": 4]),
            ("long id", doc(#"{"\#(longID)":9,"":9,"a":1}"#), ["a": 1]),
            ("too many entries", doc(tooMany), nil),
        ]
        for (label, data, expect) in cases {
            let (dir, file) = try plant(data, "counts-bad")
            let snap = engine(dir).read(reason: .refresh)
            XCTAssertEqual(snap.order, ["a", "b"], "\(label): the read still answers")
            if let expect {
                XCTAssertEqual(snap.launchCounts, expect, label)
            } else if label == "too many entries" {
                XCTAssertEqual(snap.launchCounts.count, LaunchpadLimits.maxCountedApps, "\(label): bounded, not dropped")
            } else {
                XCTAssertEqual(snap.launchCounts, [:], "\(label): no counts")
            }
            XCTAssertEqual(try Data(contentsOf: file), data, "\(label): a read changes no byte")
            XCTAssertEqual(tree(under: dir).count, 1, "\(label): a read writes nothing else")
        }
    }

    func testTheFirstLaunchMovesABadFileAsideOnceAndWritesFresh() async throws {
        let bad = Data("{ broken".utf8)
        let (dir, file) = try plant(bad, "counts-aside")
        let aside = dir.appendingPathComponent("launch-counts.json.unreadable")
        let engine = engine(dir)
        XCTAssertEqual(engine.read(reason: .refresh).launchCounts, [:])
        XCTAssertFalse(FileManager.default.fileExists(atPath: aside.path), "a read moves nothing")
        let first = await engine.launch("a")
        XCTAssertEqual(first, .launched)
        XCTAssertEqual(try Data(contentsOf: aside), bad)
        XCTAssertEqual(LaunchCountStore(directory: dir).load().counts, ["a": 1])
        try Data("other".utf8).write(to: aside)
        let second = await engine.launch("a")
        XCTAssertEqual(second, .launched)
        XCTAssertEqual(try Data(contentsOf: aside), Data("other".utf8), "the file is fine now: no second move")
        XCTAssertEqual(LaunchCountStore(directory: dir).load().counts, ["a": 2])
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testAResetRemovesTheAsideToo() async throws {
        let (dir, file) = try plant(Data("{ broken".utf8), "counts-reset-aside")
        let aside = dir.appendingPathComponent("launch-counts.json.unreadable")
        let store = LaunchCountStore(directory: dir)
        XCTAssertEqual(store.load(), .unreadable, "the control: the file is bad")
        XCTAssertTrue(store.reset())
        XCTAssertFalse(FileManager.default.fileExists(atPath: aside.path), "the bundle ids it held are gone")
        XCTAssertEqual(store.load().counts, [:])
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "a fresh file stands")
        // A file that was fine all along, with an old aside beside it, loses the aside too.
        try Data("old".utf8).write(to: aside)
        XCTAssertTrue(store.record("a"))
        XCTAssertTrue(store.reset())
        XCTAssertFalse(FileManager.default.fileExists(atPath: aside.path))
    }

    func testAFailedMoveWritesNothingAndTheLayoutIsUntouched() async throws {
        let bad = Data("{ broken".utf8)
        let (dir, file) = try plant(bad, "counts-noaside")
        // A folder where the aside name should go, holding a file, so removing and moving fail.
        let aside = dir.appendingPathComponent("launch-counts.json.unreadable")
        try FileManager.default.createDirectory(at: aside, withIntermediateDirectories: false)
        try Data("x".utf8).write(to: aside.appendingPathComponent("held"))
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path) }
        tailTheLog()
        let engine = engine(dir)
        let outcome = await engine.launch("a")
        XCTAssertEqual(outcome, .launched, "the launch itself is not held back by a count that cannot be kept")
        XCTAssertEqual(try Data(contentsOf: file), bad, "nothing was written over the bad file")
        XCTAssertFalse(loggedLines(LaunchpadEngine.moduleID).filter { $0.contains("could not be moved aside") }.isEmpty)
        XCTAssertEqual(engine.read(reason: .refresh).launchCounts, [:])
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("layout.json").path))
    }
}
