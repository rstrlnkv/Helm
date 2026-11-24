import XCTest
import HelmTestSupport
@testable import Module_Uninstaller_Engine

/// Which size sits under which key, where `UninstallerDuplicateBundleIDTests`
/// counts keys: `appSizes` is filled by `concurrentPerform`, and a count of two
/// would pass with each copy measured as the other.
final class AppSizeIdentityTests: XCTestCase {

    private var home: URL!

    override func setUpWithError() throws {
        home = scratchDirectory("un-size-id")
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent("Applications/Setapp"),
            withIntermediateDirectories: true)
    }

    @discardableResult
    private func makeApp(_ relative: String, id: String, bytes: Int) throws -> String {
        let contents = home.appendingPathComponent(relative).appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": id, "CFBundleName": "Tool"],
            format: .xml, options: 0)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
        try Data(repeating: 0x41, count: bytes)
            .write(to: contents.appendingPathComponent("payload.bin"))
        return home.appendingPathComponent(relative).path
    }

    /// Two copies of one app, an order of magnitude apart in size: the small one
    /// does not wear the large one's number.
    func testEachCopyIsMeasuredAsItselfAndNotAsTheOtherOne() throws {
        try makeApp("Applications/Tool.app", id: "com.acme.tool", bytes: 40_000)
        try makeApp("Applications/Setapp/Tool.app", id: "com.acme.tool", bytes: 900_000)

        let lister = WorkspaceAppLister(home: home, fs: FMFileSystem())
        // `contentsOfDirectory` hands back `/private/var/…` where `home.path`
        // says `/var/…`, so the copies are matched by the unique folder name.
        let tag = home.lastPathComponent
        let mine = lister.installedApps().filter { $0.path.contains(tag) }
        let sizes = lister.appSizes(mine)

        let setapp = try XCTUnwrap(mine.first { $0.path.contains("/Setapp/") })
        let direct = try XCTUnwrap(mine.first { !$0.path.contains("/Setapp/") })

        XCTAssertGreaterThanOrEqual(try XCTUnwrap(sizes[setapp.path]), 900_000,
                                    "the 900 KB copy reports \(sizes[setapp.path] ?? -1)")
        XCTAssertLessThan(try XCTUnwrap(sizes[direct.path]), 900_000,
                          "the 40 KB copy reports \(sizes[direct.path] ?? -1) — it is wearing "
                          + "the other copy's number, which is what a race over one key does")
    }

    /// The same statement about the plan, which is what actually gets trashed.
    /// Two groups, two paths, two totals — and neither total is the other's.
    func testThePlanTotalsEachCopyOnItsOwn() {
        let small = InstalledApp(name: "Tool", bundleID: "com.acme.tool",
                                 path: "/Applications/Tool.app")
        let large = InstalledApp(name: "Tool", bundleID: "com.acme.tool",
                                 path: "/Users/x/Applications/Setapp/Tool.app")
        let groups = [UninstallGroup(app: small, leftovers: [], running: false),
                      UninstallGroup(app: large, leftovers: [], running: false)]

        XCTAssertEqual(Set(UninstallPlan.paths(groups, selectedLeftovers: [])),
                       [small.path, large.path],
                       "one of the two copies is not in the plan its own row queued")
        XCTAssertEqual(UninstallPlan.totalBytes(groups, appBytes: [small.path: 40_000, large.path: 900_000],
                                                     selectedLeftovers: []), 940_000)
    }
}
