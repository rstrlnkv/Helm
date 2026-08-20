import XCTest
import HelmTestSupport

/// This module's ports reach a real Mac by default, and four of them do it in
/// ways nothing would report.
///
/// - `files:` is `FileSystemLeftovers`, which walks `~/Library/LaunchAgents`,
///   `/Library/LaunchAgents` and `/Library/LaunchDaemons` and reads the plists
///   in them — so a forgetful construction makes the scan's answer a fact about
///   whoever runs the suite.
/// - `apps:` is `WorkspaceInstalledApps`, the yardstick the scan uses to decide
///   whether anybody still owns a file; on this Mac it says the owner's apps.
/// - `loaded:` and `switcher:` are both `ActiveExtensions`, which shells out to
///   `systemextensionsctl` and to `launchctl print-disabled gui/$(getuid())` —
///   the reading half against the owner's real login items, and the writing half
///   holding `launchctl disable`.
///
/// `home:` is on the list for the reason Hosts gives about its own: it defaults
/// to this Mac's home directory and it is the reference `RemovableScope` judges
/// every removal against, so a construction that forgets it asks the gate about
/// the owner's folders while claiming to be about a scratch directory.
///
/// The scan itself is `PortsAtConstruction`, shared, and this file is the wiring.
final class EveryEngineNamesItsPortsTests: XCTestCase {

    func testEveryConstructionInThisModulesTestsNamesEveryPort() throws {
        try PortsAtConstruction.check("LeftoversEngine",
                                      under: "Tests/Modules/Leftovers",
                                      naming: ["home", "files", "apps", "loaded", "switcher"],
                                      atLeast: 8)
    }
}
