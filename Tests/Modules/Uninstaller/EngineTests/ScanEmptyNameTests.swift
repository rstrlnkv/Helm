import XCTest
@testable import Module_Uninstaller_Engine

/// The end-to-end consequence of `LeftoverMatcherHostileNamesTests`: proves the
/// bad candidate survives the engine's existence filter and reaches the review
/// screen as a real, sized, selectable row. Kept separate from the matcher unit
/// tests so the pure rule and its blast radius fail independently.
private struct ExistingFS: FileSystemPort {
    let existing: [String: Int]
    func exists(_ url: URL) -> Bool { existing[url.path] != nil }
    func size(_ url: URL) -> Int { existing[url.path] ?? 0 }
    func glob(_ pattern: URL) -> [URL] { [] }
    func children(of url: URL) -> [URL] { [] }
}
private struct NoApps: AppLister {
    func installedBundleIDs() -> Set<String> { [] }
    func isKnownToSystem(bundleID: String) -> Bool { false }
    func installedApps() -> [InstalledApp] { [] }
    func appSizes(_ apps: [InstalledApp]) -> [String: Int] { [:] }
}

final class ScanEmptyNameTests: XCTestCase {
    /// Trap: an app whose Info.plist carries an empty `CFBundleDisplayName`.
    /// The name-derived candidates collapse onto the shared folders, both of
    /// which exist on every Mac, so the scan returns them as leftovers of that
    /// one app — and the review screen ticks every returned leftover by default.
    func test_an_app_with_no_display_name_does_not_claim_shared_library_folders() async throws {
        let fs = ExistingFS(existing: [
            "/Users/x/Library/Application Support": 40_000_000_000,
            "/Users/x/Library/Logs": 500_000_000,
        ])
        let engine = UninstallerEngine(home: URL(fileURLWithPath: "/Users/x"),
                                       apps: NoApps(), fs: fs,
                                       trash: NoTrash(), running: NoRunning())
        let result = try await engine.scan(bundleID: "com.acme.tool",
                                           appPath: "/Applications/Tool.app",
                                           appName: "")
        XCTAssertEqual(result.leftovers.map(\.path), [],
                       "the scan offered shared folders for removal: \(result.leftovers.map(\.path))")
    }

    /// Control: the same engine, the same filesystem, a real name — nothing is
    /// found, which is what makes the assertion above meaningful.
    func test_a_named_app_finds_nothing_in_the_same_filesystem() async throws {
        let fs = ExistingFS(existing: [
            "/Users/x/Library/Application Support": 40_000_000_000,
            "/Users/x/Library/Logs": 500_000_000,
        ])
        let engine = UninstallerEngine(home: URL(fileURLWithPath: "/Users/x"),
                                       apps: NoApps(), fs: fs,
                                       trash: NoTrash(), running: NoRunning())
        let result = try await engine.scan(bundleID: "com.acme.tool",
                                           appPath: "/Applications/Tool.app",
                                           appName: "Tool")
        XCTAssertEqual(result.leftovers.map(\.path), [])
    }
}
