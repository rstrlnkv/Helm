import XCTest
@testable import Module_Uninstaller_Engine

/// `LeftoverMatcherHostileNamesTests` end to end, through the engine's
/// existence filter. Separate, so the pure rule and its blast radius fail
/// independently.
final class ScanEmptyNameTests: XCTestCase {
    /// An empty `CFBundleDisplayName` would collapse the name-derived candidates
    /// onto the shared folders, which exist on every Mac.
    func test_an_app_with_no_display_name_does_not_claim_shared_library_folders() async throws {
        let fs = FakeFS(existing: [
            "/Users/x/Library/Application Support": 40_000_000_000,
            "/Users/x/Library/Logs": 500_000_000,
        ])
        let engine = UninstallerEngine(home: URL(fileURLWithPath: "/Users/x"),
                                       apps: FakeApps(), fs: fs,
                                       trash: NoTrash(), running: NoRunning())
        let result = await engine.scan(bundleID: "com.acme.tool",
                                           appName: "")
        XCTAssertEqual(result.leftovers.map(\.path), [],
                       "the scan offered shared folders for removal: \(result.leftovers.map(\.path))")
    }

    /// Control: the same engine, the same filesystem, a real name — nothing is
    /// found, which is what makes the assertion above meaningful.
    func test_a_named_app_finds_nothing_in_the_same_filesystem() async throws {
        let fs = FakeFS(existing: [
            "/Users/x/Library/Application Support": 40_000_000_000,
            "/Users/x/Library/Logs": 500_000_000,
        ])
        let engine = UninstallerEngine(home: URL(fileURLWithPath: "/Users/x"),
                                       apps: FakeApps(), fs: fs,
                                       trash: NoTrash(), running: NoRunning())
        let result = await engine.scan(bundleID: "com.acme.tool",
                                           appName: "Tool")
        XCTAssertEqual(result.leftovers.map(\.path), [])
    }
}
