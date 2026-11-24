import XCTest
import HelmTestSupport
@testable import Module_Uninstaller_Engine

/// Two copies of one app (a Setapp build beside a direct download, an old
/// version kept on purpose) share the bundle id and nothing else. Both are
/// listed, sized and reviewed as themselves, keyed by path.
final class UninstallerDuplicateBundleIDTests: XCTestCase {

    private var home: URL!

    override func setUpWithError() throws {
        home = scratchDirectory("un-home")
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent("Applications/Setapp"),
            withIntermediateDirectories: true)
    }

    /// A bundle with a real Info.plist and `bytes` of payload inside it.
    private func makeApp(_ relative: String, id: String, bytes: Int) throws -> String {
        let bundle = home.appendingPathComponent(relative)
        let contents = bundle.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": id, "CFBundleName": "Tool"],
            format: .xml, options: 0)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
        try Data(repeating: 0x41, count: bytes)
            .write(to: contents.appendingPathComponent("payload.bin"))
        return bundle.path
    }

    func testBothCopiesAreListedAndEachKeepsItsOwnSize() throws {
        let small = try makeApp("Applications/Tool.app", id: "com.acme.tool", bytes: 40_000)
        let large = try makeApp("Applications/Setapp/Tool.app", id: "com.acme.tool", bytes: 900_000)

        let lister = WorkspaceAppLister(home: home, fs: FMFileSystem())
        // Matched on the unique folder name: `contentsOfDirectory(at:)` hands
        // back `/private/var/...` where `home.path` says `/var/...`.
        let tag = home.lastPathComponent
        let mine = lister.installedApps().filter { $0.path.contains(tag) }

        // Both really are on the list.
        XCTAssertEqual(Set(mine.map { ($0.path as NSString).standardizingPath }),
                       [(small as NSString).standardizingPath,
                        (large as NSString).standardizingPath])

        let sizes = lister.appSizes(mine)
        // Keyed by bundle id, the second copy's size would overwrite the first,
        // whichever thread of `concurrentPerform` finished last.
        XCTAssertEqual(sizes.count, mine.count,
                       "one size per installed copy; the id is not what tells them apart")
    }

    /// The review draws `ForEach(groups, id: \.id)`: two rows with one identity
    /// drop or duplicate rows and put a tick on the wrong one.
    func testTwoCopiesOfOneAppAreTwoIdentities() throws {
        let small = InstalledApp(name: "Tool", bundleID: "com.acme.tool",
                                 path: "/Applications/Tool.app")
        let large = InstalledApp(name: "Tool", bundleID: "com.acme.tool",
                                 path: "/Applications/Setapp/Tool.app")

        let a = UninstallGroup(app: small, leftovers: [], running: false)
        let b = UninstallGroup(app: large, leftovers: [], running: false)

        XCTAssertNotEqual(a.id, b.id, "two rows for two different bundles on disk")
    }
}
