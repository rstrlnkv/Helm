import XCTest
import HelmRuntime
@testable import Module_Uninstaller_Engine

/// The real last-opened port — `MDItemCreate` and `kMDItemLastUsedDate` in this
/// process — against real bundles, a path that is gone, and a bundle on a volume
/// Spotlight does not index. Its answers depend on this Mac, so it is a report
/// behind `HELM_BENCH` and not a gate.
///
///     HELM_BENCH=1 HELM_T7_MDLS=<tsv of path, mdls -raw value> \
///     HELM_T7_UNINDEXED=<a bundle on a volume with indexing off> \
///       swift test --filter TheLastOpenedPortOnThisMacTests
///
/// The TSV is taken by the person running this, with `mdls` in their own shell:
/// the product never launches `mdls`, and neither does this test.
final class TheLastOpenedPortOnThisMacTests: XCTestCase {

    private var env: [String: String] { ProcessInfo.processInfo.environment }

    private func lister() -> WorkspaceAppLister {
        WorkspaceAppLister(home: FileManager.default.homeDirectoryForCurrentUser, fs: FMFileSystem())
    }

    private static let mdlsFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return f
    }()

    /// Every bundle in the TSV: the port and `mdls` agree on having a date and on
    /// the date itself, to the second. The subject is asserted first — at least
    /// one bundle has a date, or agreement is between two silences.
    func testThePortAgreesWithMdlsOnEveryBundleListed() throws {
        try XCTSkipUnless(env["HELM_BENCH"] == "1")
        let tsvPath = try XCTUnwrap(env["HELM_T7_MDLS"])
        let tsv = try String(contentsOfFile: tsvPath, encoding: .utf8)
        // An app opened after the TSV was taken has moved on, and that is the
        // port being right: a later date than mdls said, and later than the
        // file itself, is agreement.
        let taken = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: tsvPath)[.modificationDate] as? Date)
        let rows = tsv.split(separator: "\n").map { $0.split(separator: "\t", maxSplits: 1).map(String.init) }
        let lister = lister()
        var dated = 0, agreed = 0, disagreements: [String] = []
        var slowest: (String, TimeInterval) = ("", 0)
        let started = Date()
        for row in rows where row.count == 2 {
            let (path, raw) = (row[0], row[1])
            let expected = Self.mdlsFormat.date(from: raw)
            let t0 = Date()
            let got = lister.lastOpened(path: path)
            let took = Date().timeIntervalSince(t0)
            if took > slowest.1 { slowest = ((path as NSString).lastPathComponent, took) }
            if got != nil { dated += 1 }
            switch (expected, got) {
            case (nil, nil): agreed += 1
            case (let e?, let g?) where abs(e.timeIntervalSince(g)) < 1: agreed += 1
            case (_, let g?) where g > taken: agreed += 1
            default: disagreements.append("\((path as NSString).lastPathComponent): mdls \(raw), port \(String(describing: got))")
            }
        }
        let total = Date().timeIntervalSince(started)
        print(String(format: "T7 port: %d bundles, %d dated, %d agree with mdls, %.1f ms total, slowest %@ %.1f ms",
                     rows.count, dated, agreed, total * 1000, slowest.0, slowest.1 * 1000))
        disagreements.forEach { print("T7 disagree: \($0)") }
        XCTAssertGreaterThan(dated, 0, "the port dated nothing — the subject never happened")
        XCTAssertEqual(disagreements, [])
    }

    /// A bundle that was there when the list was taken and is gone when the date
    /// is asked for: nil, which the screen draws as "no record", and quickly.
    func testAPathThatVanishedIsNil() throws {
        try XCTSkipUnless(env["HELM_BENCH"] == "1")
        let root = scratchDirectory("t7-vanished")
        let bundle = root.appendingPathComponent("Gone.app")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try FileManager.default.removeItem(at: bundle)
        let t0 = Date()
        XCTAssertNil(lister().lastOpened(path: bundle.path))
        XCTAssertNil(lister().lastOpened(path: "/Applications/\(UUID().uuidString).app"))
        XCTAssertLessThan(Date().timeIntervalSince(t0), 1)
    }

    /// A bundle nobody has opened, on a volume Spotlight does not index. The port
    /// must say nil — "no record" — and not hand back some other date of the
    /// file's, which the row would draw as «Opened …».
    func testABundleOnAnUnindexedVolumeHasNoOpeningInvented() throws {
        try XCTSkipUnless(env["HELM_BENCH"] == "1")
        let path = try XCTUnwrap(env["HELM_T7_UNINDEXED"], "set HELM_T7_UNINDEXED")
        let values = try URL(fileURLWithPath: path).resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        let got = lister().lastOpened(path: path)
        print("T7 unindexed: port \(String(describing: got)), modified \(String(describing: values.contentModificationDate)), created \(String(describing: values.creationDate))")
        XCTAssertNil(got, "an unindexed bundle nobody opened read as opened on \(String(describing: got)) — its modification date is \(String(describing: values.contentModificationDate))")
    }

    /// The engine's whole read over this Mac's real list: how long, how many
    /// dated, and nothing left unread by the deadline on an ordinary machine.
    func testTheEnginesReadOverThisMacsListFinishesWellInsideItsDeadline() async throws {
        try XCTSkipUnless(env["HELM_BENCH"] == "1")
        let lister = lister()
        let apps = lister.installedApps()
        try XCTSkipIf(apps.count < 5)
        let engine = UninstallerEngine(home: FileManager.default.homeDirectoryForCurrentUser, apps: lister,
                                       fs: FakeFS(existing: [:]), trash: FakeTrash(), running: FakeRunning(running: []),
                                       store: NamespacedStore(namespace: UninstallerEngine.moduleID,
                                                              backing: InMemoryKeyValueStore()))
        let t0 = Date()
        let reading = await engine.lastOpened(apps)
        let took = Date().timeIntervalSince(t0)
        print(String(format: "T7 engine read: %d apps, %d dated, %d unread, %.1f ms", apps.count,
                     reading.opened.count, reading.unread.count, took * 1000))
        XCTAssertGreaterThan(reading.opened.count, 0)
        XCTAssertTrue(reading.unread.isEmpty)
        XCTAssertLessThan(took, UninstallerEngine.lastOpenedDeadline)
    }
}
