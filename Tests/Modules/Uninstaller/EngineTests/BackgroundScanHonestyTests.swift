import XCTest
@testable import Module_Uninstaller_Engine

// MARK: - Fakes

/// Every listing empty unless the test says otherwise, and nothing exists
/// unless the test says otherwise. `FileSystemPort.children` documents itself
/// as "empty if missing **or unreadable**" — the two are one answer here, and
/// that is the whole subject of this file.
private struct SilentFS: FileSystemPort {
    var listings: [String: [String]] = [:]
    var existing: Set<String> = []
    func exists(_ url: URL) -> Bool { existing.contains(url.path) }
    func size(_ url: URL) -> Int { 1_000 }
    func glob(_ pattern: URL) -> [URL] { [] }
    func children(of url: URL) -> [URL] {
        (listings[url.path] ?? []).map { url.appendingPathComponent($0) }
    }
}

private struct StubApps: AppLister {
    var installed: Set<String> = []
    var known: Set<String> = []
    func installedBundleIDs() -> Set<String> { installed }
    func isKnownToSystem(bundleID: String) -> Bool { known.contains(bundleID) }
    func installedApps() -> [InstalledApp] { [] }
    func appSizes(_ apps: [InstalledApp]) -> [String: Int] { [:] }
}

// MARK: - Tests

/// `ScanReport`'s doc is explicit, and it is the rule the whole background
/// feature rests on:
///
/// > **Nil is not an empty report.** A scan whose root was refused, or that was
/// > cancelled, or that could not read a directory in scope, must not come back
/// > as "we looked and it was clean".
///
/// `DuplicatesEngine.backgroundScan` honours it — a refused root returns nil.
/// `UninstallerEngine.backgroundScan` has **no path to nil at all**: it awaits
/// `scanOrphans()`, which returns a non-optional array, and wraps whatever came
/// back. Every failure this module can have therefore arrives at the journal
/// spelled «проверено, чисто».
final class UninstallerBackgroundScanHonestyTests: XCTestCase {

    private let home = URL(fileURLWithPath: "/Users/x")

    private func engine(_ fs: SilentFS, apps: StubApps = StubApps()) -> UninstallerEngine {
        UninstallerEngine(home: home, apps: apps, fs: fs, trash: NoTrash(),
                          running: NoRunning())
    }

    /// The no-permission case, which is the ordinary one: Helm is installed,
    /// Full Disk Access has not been granted (or was dropped by a new build —
    /// the project's own notes say every local install drops it), and every
    /// listing under `~/Library` comes back empty.
    ///
    /// Nine directories, not one entry between them. `~/Library/Preferences`
    /// alone holds hundreds of files on any Mac that has been switched on. This
    /// is a reading that did not happen, and it is recorded as a scan that ran.
    func testAnEntirelyUnreadableLibraryIsNotACleanScan() async {
        let report = await engine(SilentFS()).backgroundScan()
        XCTAssertNil(report,
                     "nine unreadable directories were reported as a scan that found nothing")
    }

    /// The same thing said without relying on how many directories were silent:
    /// the home Helm was given has no `~/Library` in it at all. There is no Mac
    /// in that state — it means the port could not see the home — and the scan
    /// still answers with a finished, empty report.
    func testAHomeWithoutALibraryIsNotACleanScan() async {
        var fs = SilentFS()
        fs.existing = []            // not even ~/Library
        let report = await engine(fs).backgroundScan()
        XCTAssertNil(report, "a home the port cannot see was reported as clean")
    }

    /// The other direction of the same missing guard, and the expensive one.
    ///
    /// `OrphanDetector.isOrphan` treats "not in `installedBundleIDs`" as
    /// evidence of an orphan. The set has no error channel: an
    /// `installedBundleIDs()` that fails answers `[]`, indistinguishable from a
    /// Mac with no apps — and then **every** bundle-id-shaped folder under
    /// `~/Library` is an orphan. Unattended, with nobody reading the screen,
    /// that is the person's entire Library offered up for removal in one go.
    ///
    /// A Library holding third-party support folders while zero apps are
    /// installed is a contradiction, and a scan that runs with nobody watching
    /// is the place to notice it.
    func testAFailedInstalledAppsReadingDoesNotOrphanTheWholeLibrary() async {
        var fs = SilentFS()
        fs.existing = ["/Users/x/Library"]
        fs.listings = [
            "/Users/x/Library/Application Support": ["com.acme.tool", "com.other.app"],
            "/Users/x/Library/Caches": ["com.acme.tool", "com.other.app"],
            "/Users/x/Library/Preferences": ["com.acme.tool.plist", "com.other.app.plist"],
        ]
        // The reading failed: no apps, and LaunchServices answers for none either.
        let report = await engine(fs, apps: StubApps(installed: [], known: [])).backgroundScan()
        XCTAssertNotEqual(report?.count, 6,
                          "an empty installed-apps set turned every entry in ~/Library "
                          + "into a removal candidate")
    }
}
