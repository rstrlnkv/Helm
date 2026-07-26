import XCTest
@testable import Module_Leftovers_Engine

/// Runs the real scanner against this Mac. Gated like the disk benchmark:
/// it depends on what is installed, so it informs rather than gates CI —
/// `HELM_BENCH=1 swift test --filter LiveExtensionScan`.
final class LiveExtensionScan: XCTestCase {
    func testSystemExtensionsAppearInTheList() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        let scanner = LeftoversScanner(home: FileManager.default.homeDirectoryForCurrentUser,
                                       files: FileSystemLeftovers(),
                                       apps: WorkspaceInstalledApps(),
                                       extensions: ActiveExtensions())
        let extensions = scanner.scan().filter { $0.kind == .systemExtension }
        print("system extensions listed: \(extensions.count)")
        for item in extensions {
            print("  \(item.identifier)  status=\(item.status.rawValue) removable=\(item.removable)")
        }
        // Whatever is installed, Helm must never offer to trash one.
        XCTAssertFalse(extensions.contains(where: \.removable))
    }
}
