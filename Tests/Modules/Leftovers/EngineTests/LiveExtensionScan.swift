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

        let all = scanner.scan()
        let toggleable = all.filter(\.canToggle)
        let off = all.filter(\.disabled)
        print("login items Helm can switch: \(toggleable.count), currently off: \(off.count)")
        for item in off { print("  off: \(item.identifier)") }
        // Anything switchable must have a label to switch.
        XCTAssertFalse(toggleable.contains { $0.identifier.isEmpty })
        // And a label the switch will carry: `ActiveExtensions.setDisabled` refuses
        // a `/` outright, so a row offering «Turn off» for one is a button that does
        // nothing (`ASwitchTheSystemWillRefuseTests` has the fixtures and the
        // reasoning). Read here as well because this is the only reading taken over
        // labels nobody in this repository wrote — whatever is really in the
        // LaunchAgents folders of the Mac running it.
        let unusable = toggleable.filter {
            $0.identifier.contains("/") || $0.identifier.contains("\"")
                || $0.identifier.contains(where: \.isNewline)
        }
        XCTAssertEqual(unusable.count, 0,
                       "\(unusable.count) row(s) on this Mac offer a switch for a label launchd "
                       + "will not be asked about")
    }
}
