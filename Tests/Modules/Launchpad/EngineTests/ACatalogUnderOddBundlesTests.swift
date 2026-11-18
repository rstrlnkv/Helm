import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine

/// A real temporary tree through the real port: bundles with no id, a non-string id, garbage plists, an
/// oversize name, a symlink loop, a folder that will not open, an `.app` inside an `.app`, the same id
/// twice, folders deeper than the walk goes, a pipe where a file should be, and an `InfoPlist.strings` that is
/// garbage, huge or over the ceiling: what a file another process planted can hand the walk.
final class ACatalogUnderOddBundlesTests: XCTestCase {

    @discardableResult
    private func bundle(_ relative: String, in root: URL, plist: [String: Any]? = nil, raw: Data? = nil,
                        strings: [String: Data] = [:]) throws -> URL {
        let app = root.appendingPathComponent(relative)
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let data = try raw ?? PropertyListSerialization.data(fromPropertyList: plist ?? [:], format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        for (code, text) in strings {
            let lproj = contents.appendingPathComponent("Resources/\(code).lproj")
            try FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
            try text.write(to: lproj.appendingPathComponent("InfoPlist.strings"))
        }
        return app
    }

    private static let codes = ["en", "de", "fr", "ja", "ru", "zh-Hans", "es", "pt"]
    private func inEveryLanguage(_ data: Data) -> [String: Data] { Dictionary(uniqueKeysWithValues: Self.codes.map { ($0, data) }) }

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

    /// A file that parses whole inside the ceiling and is padded with blanks past it is still over the ceiling:
    /// the cut-off read would parse, so only the size check refuses it; one byte under the line it is read.
    func testAValidInfoPlistPaddedOneByteOverTheCeilingIsSkippedAndAtTheCeilingIsRead() throws {
        let root = scratchDirectory("cat-padded-plist")
        func padded(_ id: String, to total: Int) throws -> Data {
            let head = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": id], format: .xml, options: 0)
            return head + Data(repeating: 0x20, count: total - head.count)
        }
        XCTAssertEqual(LaunchpadLimits.maxFileBytes, 2 * 1024 * 1024)
        try bundle("Over.app", in: root, raw: padded("over", to: 2 * 1024 * 1024 + 1))
        try bundle("At.app", in: root, raw: padded("at", to: 2 * 1024 * 1024))
        let r = read(root)
        XCTAssertEqual(r.apps.map(\.id), ["at"])
        XCTAssertEqual(r.apps.map { URL(fileURLWithPath: $0.path).lastPathComponent }, ["At.app"])
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

    func testALocalizedNameOverTheCeilingIsCut() throws {
        let root = scratchDirectory("odd-long-name")
        let long = String(repeating: "n", count: 50_000)
        try bundle("Long.app", in: root, plist: ["CFBundleIdentifier": "x.long", "CFBundleName": "FromPlist"],
                   strings: inEveryLanguage(Data("\"CFBundleDisplayName\" = \"\(long)\";".utf8)))
        XCTAssertEqual(read(root).apps.map(\.name), [String(repeating: "n", count: LaunchpadLimits.maxStringLength)])
    }

    func testAGarbageInfoPlistStringsFallsBackToTheInfoPlistName() throws {
        let root = scratchDirectory("odd-garbage-strings")
        let garbage = Data([0xFF, 0xFE, 0x00, 0x80, 0x7B, 0x22, 0x00, 0xC3, 0x28]) + Data(repeating: 0x41, count: 1_000)
        try bundle("Junk.app", in: root, plist: ["CFBundleIdentifier": "x.junk", "CFBundleName": "FromPlist"], strings: inEveryLanguage(garbage))
        let r = read(root)
        XCTAssertEqual(r.apps.map(\.id), ["x.junk"], "the app is listed, not dropped")
        XCTAssertEqual(r.apps.map(\.name), ["FromPlist"])
        XCTAssertTrue(r.complete)
    }

    /// Over the ceiling the file is not parsed at all: the name is the `Info.plist` one, and the read comes back at once.
    func testAHugeInfoPlistStringsIsNotReadAndTheNameFallsBack() throws {
        let root = scratchDirectory("odd-huge-strings")
        var text = ""
        text.reserveCapacity(8_000_000)
        for n in 0..<200_000 { text += "\"k\(n)\" = \"v\(n)\";\n" }
        text += "\"CFBundleDisplayName\" = \"FromStrings\";\n"
        try bundle("Huge.app", in: root, plist: ["CFBundleIdentifier": "x.huge", "CFBundleName": "FromPlist"], strings: inEveryLanguage(Data(text.utf8)))
        let started = Date()
        let r = read(root)
        XCTAssertEqual(r.apps.map(\.name), ["FromPlist"])
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }

    /// A pipe nobody writes to blocks whoever opens it for reading. The read runs on a thread of its own under a deadline,
    /// so a regression fails this test instead of hanging the suite.
    func testAPipeWhereAnInfoPlistOrItsStringsShouldBeDoesNotHoldTheWalk() throws {
        let root = scratchDirectory("odd-fifo")
        let pipe = try bundle("Pipe.app", in: root, plist: ["CFBundleIdentifier": "x.pipe"])
        let pipeInfo = pipe.appendingPathComponent("Contents/Info.plist").path
        try FileManager.default.removeItem(atPath: pipeInfo)
        XCTAssertEqual(mkfifo(pipeInfo, 0o600), 0)
        let named = try bundle("Named.app", in: root, plist: ["CFBundleIdentifier": "x.named", "CFBundleName": "FromPlist"])
        var pipes = [pipeInfo]
        for code in Self.codes {
            let lproj = named.appendingPathComponent("Contents/Resources/\(code).lproj")
            try FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
            XCTAssertEqual(mkfifo(lproj.appendingPathComponent("InfoPlist.strings").path, 0o600), 0)
            pipes.append(lproj.appendingPathComponent("InfoPlist.strings").path)
        }
        // A regressed reader sits in `open` for a pipe; opening it for both ends here lets that thread go.
        addTeardownBlock { for path in pipes { let fd = open(path, O_RDWR | O_NONBLOCK); if fd >= 0 { close(fd) } } }
        let answer = Answer()
        let finished = DispatchSemaphore(value: 0)
        let catalog = FileSystemAppCatalog(roots: [root])
        Thread.detachNewThread {
            answer.set(catalog.read(), catalog.bundleID(atPath: pipe.path))
            finished.signal()
        }
        XCTAssertEqual(finished.wait(timeout: .now() + 5), .success, "the walk is held by a pipe")
        let (reading, id) = answer.get()
        XCTAssertEqual(reading?.apps.map(\.id), ["x.named"])
        XCTAssertEqual(reading?.apps.map(\.name), ["FromPlist"])
        XCTAssertNil(id)
    }

    private final class Answer: @unchecked Sendable {
        private let lock = NSLock()
        private var reading: CatalogReading?
        private var id: String?
        func set(_ reading: CatalogReading, _ id: String?) { lock.lock(); self.reading = reading; self.id = id; lock.unlock() }
        func get() -> (CatalogReading?, String?) { lock.lock(); defer { lock.unlock() }; return (reading, id) }
    }
}
