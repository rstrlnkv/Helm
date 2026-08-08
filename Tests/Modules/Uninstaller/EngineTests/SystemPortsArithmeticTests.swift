import XCTest
import HelmTestSupport
@testable import Module_Uninstaller_Engine

/// The two numbers the uninstaller puts on screen — how big an app is, and how
/// much removing it freed — measured against a tree built here.
final class UninstallerSizeArithmeticTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = scratchDirectory("un-size")
    }

    /// One 400 KB allocation under two names. `FMFileSystem.size` walks names,
    /// so it charges the allocation twice — and `trashSync` adds exactly this
    /// figure to `freedBytes`, which is what the banner says was freed.
    ///
    /// The Disk module's scanner already decided the other way, on purpose:
    /// `TreeBuilder.addFile` dedupes by file id, "a hard link's target is one
    /// allocation however many names it has". Two answers to one question, in
    /// one app.
    func testAHardLinkedFileIsMeasuredOnce() throws {
        let folder = root.appendingPathComponent("Support")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("payload.bin")
        try Data(repeating: 0x41, count: 400_000).write(to: file)
        try FileManager.default.linkItem(at: file,
                                         to: folder.appendingPathComponent("payload-alias.bin"))

        let one = FMFileSystem().size(file)
        let whole = FMFileSystem().size(folder)

        XCTAssertGreaterThanOrEqual(one, 400_000)
        XCTAssertEqual(whole, one,
                       "the folder holds one allocation under two names, not two allocations")
    }
}

/// Two copies of one app, which /Applications and ~/Applications hold at once
/// often enough — a Setapp build beside a direct download, an old version kept
/// on purpose. `installedApps()` deduplicates by *path*, so both are listed.
/// Everything downstream keys off the bundle id, which is the one thing the two
/// copies share.
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

        // Both really are on the list — this is not a hypothetical.
        XCTAssertEqual(Set(mine.map { ($0.path as NSString).standardizingPath }),
                       [(small as NSString).standardizingPath,
                        (large as NSString).standardizingPath])

        let sizes = lister.appSizes(mine)
        // `[String: Int]` is keyed by bundle id, so the second copy's size
        // overwrites the first — and which one wins is decided by
        // `concurrentPerform`, i.e. by a race. The page reads
        // `sizes[app.bundleID]` once per row, so both rows show one number.
        XCTAssertEqual(sizes.count, mine.count,
                       "one size per installed copy; the id is not what tells them apart")
    }

    /// The review screen draws `ForEach(groups, id: \.id)`, and `id` is the
    /// bundle id. Two copies means two rows claiming one identity, which is a
    /// list that drops or duplicates rows and puts a tick on the wrong one.
    func testTwoCopiesOfOneAppAreTwoIdentities() throws {
        let small = InstalledApp(name: "Tool", bundleID: "com.acme.tool",
                                 path: "/Applications/Tool.app", sizeBytes: 40_000)
        let large = InstalledApp(name: "Tool", bundleID: "com.acme.tool",
                                 path: "/Applications/Setapp/Tool.app", sizeBytes: 900_000)

        let a = UninstallGroup(app: small, leftovers: [], running: false)
        let b = UninstallGroup(app: large, leftovers: [], running: false)

        XCTAssertNotEqual(a.id, b.id, "two rows for two different bundles on disk")
    }
}
