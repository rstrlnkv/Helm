import XCTest
@testable import HelmRuntime

final class SystemExtensionParserTests: XCTestCase {
    /// Verbatim `systemextensionsctl list` output from a real machine.
    private let sample = """
    3 extension(s)
    --- com.apple.system_extension.network_extension (Go to 'System Settings > General > Login Items & Extensions > Network Extensions' to modify these system extension(s))
    enabled\tactive\tteamID\tbundleID (version)\tname\t[state]
    *\t*\tTNPM9PFX3W\tcom.nebula.karing.karingServiceSE (1.2.21/2408)\tkaringServiceSE\t[activated enabled]
    \t*\t2XZUN9L63Z\tcom.databridges.privacy.v2RayTun.snextension (2.2/19)\tsnextension\t[activated waiting for user]
    *\t*\tTC3Q7MAJXF\tcom.adguard.mac.adguard.network-extension (2.19.0/2258)\tAdGuard Network Extension\t[activated enabled]
    """

    func testListsEveryActivatedExtension() {
        let found = SystemExtensionParser.parse(sample)
        XCTAssertEqual(found.count, 3)
        XCTAssertEqual(found.map(\.identifier).sorted(), [
            "com.adguard.mac.adguard.network-extension",
            "com.databridges.privacy.v2RayTun.snextension",
            "com.nebula.karing.karingServiceSE",
        ])
    }

    /// The host app id is what the uninstaller matches against.
    func testDerivesHostAppIdentifiers() {
        let hosts = SystemExtensionParser.hostIdentifiers(sample)
        XCTAssertTrue(hosts.contains("com.nebula.karing"))
        XCTAssertTrue(hosts.contains("com.databridges.privacy.v2RayTun"))
        XCTAssertTrue(hosts.contains("com.adguard.mac.adguard"))
    }

    func testCarriesTeamStateAndName() {
        let found = SystemExtensionParser.parse(sample)
        let waiting = found.first { $0.identifier.contains("v2RayTun") }
        XCTAssertEqual(waiting?.teamID, "2XZUN9L63Z")
        XCTAssertEqual(waiting?.state, "activated waiting for user")
        XCTAssertEqual(waiting?.name, "snextension")
        XCTAssertFalse(waiting?.enabled ?? true)          // no `*` in the enabled column
        let adguard = found.first { $0.identifier.contains("adguard") }
        XCTAssertTrue(adguard?.enabled ?? false)
        XCTAssertEqual(adguard?.name, "AdGuard Network Extension")
    }

    func testIgnoresHeadersAndEmptyOutput() {
        XCTAssertTrue(SystemExtensionParser.parse("0 extension(s)\n").isEmpty)
        XCTAssertTrue(SystemExtensionParser.parse("").isEmpty)
    }
}
