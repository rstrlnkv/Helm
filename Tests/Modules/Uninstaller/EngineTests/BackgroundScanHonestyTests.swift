import XCTest
import HelmRuntime
@testable import Module_Uninstaller_Engine

// MARK: - Fakes

/// The grant's three answers, named at every construction that cares.
private struct FakeAccess: FullDiskAccessPort {
    var answer: PermissionState?
    func fullDiskAccess() -> PermissionState? { answer }
}

// MARK: - Tests

/// Nil is not an empty report (`ScanReport`). `UninstallerEngine.backgroundScan`
/// returns nil when `~/Library` cannot be seen (`checks.library`) and when the
/// installed-apps reading is empty while the Library is not
/// (`checks.installed`); the two tests below reach one guard each.
final class UninstallerBackgroundScanHonestyTests: XCTestCase {

    private let home = URL(fileURLWithPath: "/Users/x")

    private func engine(_ fs: FakeFS, apps: FakeApps = FakeApps()) -> UninstallerEngine {
        UninstallerEngine(home: home, apps: apps, fs: fs, trash: NoTrash(),
                          running: NoRunning())
    }

    /// A home with no `~/Library` is no Mac's state: the port could not see the
    /// home, and that is not a clean scan.
    func testAHomeWithoutALibraryIsNotACleanScan() async {
        let fs = FakeFS()
        let report = await engine(fs).backgroundScan()
        XCTAssertNil(report, "a home the port cannot see was reported as clean")
    }

    /// A failed `installedBundleIDs()` answers `[]`, and `OrphanDetector.isOrphan`
    /// would then make every bundle-id-shaped folder under `~/Library` an orphan,
    /// unattended. A Library of third-party folders with zero apps installed is a
    /// contradiction, and the scan answers nil.
    func testAFailedInstalledAppsReadingDoesNotOrphanTheWholeLibrary() async {
        let fs = FakeFS()
        fs.existing = ["/Users/x/Library": 1_000]
        fs.listings = [
            "/Users/x/Library": ["Caches"],
            "/Users/x/Library/Application Support": ["com.acme.tool", "com.other.app"],
            "/Users/x/Library/Caches": ["com.acme.tool", "com.other.app"],
            "/Users/x/Library/Preferences": ["com.acme.tool.plist", "com.other.app.plist"],
        ]
        // The reading failed: no apps, and LaunchServices answers for none either.
        let report = await engine(fs, apps: FakeApps()).backgroundScan()
        XCTAssertNil(report,
                          "an empty installed-apps set turned every entry in ~/Library "
                          + "into a removal candidate")
    }

    // MARK: Full Disk Access gate

    /// Every path exists and `~/Library` lists one folder, as on a Mac that grants the read.
    private func countingFS() -> FakeFS {
        FakeFS(listings: ["/Users/x/Library": ["Caches"]], everyPathExistsAt: 1)
    }

    private func gated(_ fs: FileSystemPort, _ answer: PermissionState?) -> UninstallerEngine {
        UninstallerEngine(home: home, apps: FakeApps(apps: [InstalledApp(name: "Tool", bundleID: "com.acme.tool",
                                                      path: "/Applications/Tool.app")]), fs: fs,
                          trash: NoTrash(), running: NoRunning(),
                          fullDiskAccess: FakeAccess(answer: answer))
    }

    /// Without the grant nothing is listed and nothing is reported.
    func testADeniedGrantAnswersNilAndReadsNothing() async {
        let fs = countingFS()
        let report = await gated(fs, .denied).backgroundScan()
        XCTAssertNil(report)
        XCTAssertEqual(fs.reads, 0, "a scan without the grant still read the disk")
    }

    /// A probe that could not answer is not a grant.
    func testAnUnreadableGrantAnswersNil() async {
        let fs = countingFS()
        let report = await gated(fs, nil).backgroundScan()
        XCTAssertNil(report)
        XCTAssertEqual(fs.reads, 0)
    }

    /// Control: the same Mac with the grant is scanned, and a listing Library gives a report.
    func testAGrantedGrantWithAListingLibraryAnswersAReport() async {
        let fs = countingFS()
        let report = await gated(fs, .granted).backgroundScan()
        XCTAssertNotNil(report)
        XCTAssertGreaterThan(fs.reads, 0)
    }
}
