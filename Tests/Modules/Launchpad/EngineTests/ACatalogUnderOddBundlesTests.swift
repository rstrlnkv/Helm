import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine

/// A real temporary tree through the real port: bundles with no id, a non-string id, garbage plists, an
/// oversize name, a symlink loop, a folder that will not open, an `.app` inside an `.app`, the same id
/// twice, and folders deeper than the walk goes.
final class ACatalogUnderOddBundlesTests: XCTestCase {

    @discardableResult
    private func bundle(_ relative: String, in root: URL, plist: [String: Any]? = nil, raw: Data? = nil) throws -> URL {
        let app = root.appendingPathComponent(relative)
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let data = try raw ?? PropertyListSerialization.data(fromPropertyList: plist ?? [:], format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return app
    }

    private func read(_ roots: URL...) -> CatalogReading { FileSystemAppCatalog(roots: roots).read() }

    func testNameFallsBackFromDisplayNameToBundleNameToFileName() throws {
        let root = scratchDirectory("cat-names")
        try bundle("A.app", in: root, plist: ["CFBundleIdentifier": "a", "CFBundleDisplayName": "Shown", "CFBundleName": "Bn"])
        try bundle("B.app", in: root, plist: ["CFBundleIdentifier": "b", "CFBundleName": "Bn"])
        try bundle("C File.app", in: root, plist: ["CFBundleIdentifier": "c"])
        XCTAssertEqual(read(root).apps.map(\.name).sorted(), ["Bn", "C File", "Shown"])
    }

    func testAMissingOrNonStringIdIsSkippedAndGarbageIsToo() throws {
        let root = scratchDirectory("cat-bad")
        try bundle("NoId.app", in: root, plist: ["CFBundleName": "x"])
        try bundle("Num.app", in: root, plist: ["CFBundleIdentifier": 5])
        try bundle("Junk.app", in: root, raw: Data("not a plist".utf8))
        try bundle("Ok.app", in: root, plist: ["CFBundleIdentifier": "ok"])
        let r = read(root)
        XCTAssertEqual(r.apps.map(\.id), ["ok"])
        XCTAssertTrue(r.complete)
    }

    func testAnInfoPlistOverTheCeilingIsSkippedAndTheRestStillRead() throws {
        let root = scratchDirectory("cat-bigplist")
        try bundle("Big.app", in: root, plist: ["CFBundleIdentifier": "big", "Pad": String(repeating: "p", count: LaunchpadLimits.maxFileBytes + 100)])
        try bundle("Ok.app", in: root, plist: ["CFBundleIdentifier": "ok"])
        let r = read(root)
        XCTAssertEqual(r.apps.map(\.id), ["ok"])
        XCTAssertTrue(r.complete)
    }

    func testAnOversizeNameAndIdAreCut() throws {
        let root = scratchDirectory("cat-long")
        let long = String(repeating: "n", count: 50_000)
        try bundle("L.app", in: root, plist: ["CFBundleIdentifier": long, "CFBundleDisplayName": long])
        let app = try XCTUnwrap(read(root).apps.first)
        XCTAssertEqual(app.name.count, LaunchpadLimits.maxStringLength)
        XCTAssertEqual(app.id.count, LaunchpadLimits.maxStringLength)
    }

    func testASymlinkedFolderIsNotFollowedAndASymlinkedAppIs() throws {
        let root = scratchDirectory("cat-links")
        let elsewhere = scratchDirectory("cat-elsewhere")
        let real = try bundle("Real.app", in: elsewhere, plist: ["CFBundleIdentifier": "real"])
        try bundle("Hidden.app", in: elsewhere, plist: ["CFBundleIdentifier": "behind"])
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Linked.app"), withDestinationURL: real)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Loop"), withDestinationURL: root)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Out"), withDestinationURL: elsewhere)
        XCTAssertEqual(read(root).apps.map(\.id), ["real"])
    }

    func testAFolderThatWillNotOpenMakesTheReadIncomplete() throws {
        let root = scratchDirectory("cat-locked")
        try bundle("Ok.app", in: root, plist: ["CFBundleIdentifier": "ok"])
        let locked = root.appendingPathComponent("Locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: false)
        chmod(locked.path, 0o000)
        addTeardownBlock { chmod(locked.path, 0o755) }
        let r = read(root)
        XCTAssertFalse(r.complete)
        XCTAssertEqual(r.apps.map(\.id), ["ok"])
    }

    func testAnAbsentRootIsEmptyAndComplete() {
        let r = read(scratchDirectory("cat-absent").appendingPathComponent("nothing"))
        XCTAssertEqual(r, CatalogReading(apps: [], complete: true))
    }

    func testAnAppInsideAnAppIsNotDescendedInto() throws {
        let root = scratchDirectory("cat-nested")
        try bundle("Outer.app", in: root, plist: ["CFBundleIdentifier": "outer"])
        try bundle("Outer.app/Contents/Helpers/Inner.app", in: root, plist: ["CFBundleIdentifier": "inner"])
        XCTAssertEqual(read(root).apps.map(\.id), ["outer"])
    }

    func testTheSameIdTwiceIsOneEntryAndTheWinnerIsFixed() throws {
        let first = scratchDirectory("cat-dup1"), second = scratchDirectory("cat-dup2")
        try bundle("Zed.app", in: first, plist: ["CFBundleIdentifier": "dup"])
        try bundle("Abe.app", in: first, plist: ["CFBundleIdentifier": "dup"])
        try bundle("Abe.app", in: second, plist: ["CFBundleIdentifier": "dup"])
        for _ in 0..<3 {
            let r = read(first, second)
            XCTAssertEqual(r.apps.count, 1)
            XCTAssertEqual(r.apps.first?.path, first.appendingPathComponent("Abe.app").path, "earlier root, then smallest path")
        }
    }

    func testTheWalkStopsTwoFoldersBelowTheRoot() throws {
        let root = scratchDirectory("cat-depth")
        try bundle("a/b/Within.app", in: root, plist: ["CFBundleIdentifier": "within"])
        try bundle("a/b/c/Beyond.app", in: root, plist: ["CFBundleIdentifier": "beyond"])
        try bundle("Dotted.d/Skipped.app", in: root, plist: ["CFBundleIdentifier": "skipped"])
        try bundle(".hidden/Skipped2.app", in: root, plist: ["CFBundleIdentifier": "skipped2"])
        XCTAssertEqual(read(root).apps.map(\.id), ["within"])
    }

    /// The ceiling is a constant (10 000), so the tree is real: one more bundle than the ceiling, each with its own id.
    func testAWalkStoppedAtTheCeilingIsNotComplete() throws {
        let root = scratchDirectory("cat-cap")
        for n in 0...10_000 {
            let contents = root.appendingPathComponent("A\(n).app/Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "id\(n)"], format: .xml, options: 0)
            try data.write(to: contents.appendingPathComponent("Info.plist"))
        }
        let r = read(root)
        XCTAssertEqual(r.apps.count, 10_000, "the walk stops at the ceiling")
        XCTAssertFalse(r.complete, "a walk the ceiling stopped has not seen every app, so it must not let a reconcile drop any")
    }

    func testAWalkJustUnderTheCeilingStaysComplete() throws {
        let root = scratchDirectory("cat-nocap")
        for n in 0..<50 { try bundle("A\(n).app", in: root, plist: ["CFBundleIdentifier": "id\(n)"]) }
        let r = read(root)
        XCTAssertEqual(r.apps.count, 50)
        XCTAssertTrue(r.complete)
    }
}
