import XCTest
@testable import HelmRuntime

/// `hostIdentifiers` is what tells the uninstaller which failed removals to
/// blame on a system extension, so a wrong entry here becomes wrong advice on a
/// failure sheet. Fed the real `systemextensionsctl list` shape, including the
/// two kinds of line that are not extensions.
final class SystemExtensionHostTests: XCTestCase {

    /// Real output shape: a `---` section marker, the column header, one enabled
    /// row and one row that is present but switched off.
    private let listing = """
    1 extension(s)
    --- com.apple.system_extension.network_extension
    enabled\tactive\tteamID\tbundleID (version)\tname\t[state]
    *\t*\t2XZUN9L63Z\tat.obdev.littlesnitch.networkextension (6.1/6123)\tLittle Snitch Network Extension\t[activated enabled]
    \t*\tMLZF7K7B5R\tcom.example.tool.helper (1.0/1)\tTool Helper\t[terminated waiting to uninstall on reboot]
    """

    /// The header line has six tab-separated columns like every real row; it is
    /// rejected only because "bundleID (version)" contains no dot. Pinning that,
    /// because it is load-bearing and invisible.
    func testTheColumnHeaderIsNotParsedAsAnExtension() {
        let parsed = SystemExtensionParser.parse(listing)
        XCTAssertFalse(parsed.contains { $0.identifier.contains("bundleID") }, "\(parsed)")
        XCTAssertEqual(parsed.count, 2)
    }

    func testTheEnabledColumnDistinguishesTheTwoRows() {
        let parsed = SystemExtensionParser.parse(listing)
        XCTAssertEqual(parsed.first { $0.identifier.hasPrefix("at.obdev") }?.enabled, true)
        XCTAssertEqual(parsed.first { $0.identifier.hasPrefix("com.example") }?.enabled, false)
    }

    /// Version, team and state must each come from their own column — a name
    /// carrying a version-looking string must not shift the others.
    func testEachFieldComesFromItsOwnColumn() {
        let parsed = SystemExtensionParser.parse(listing)
        let snitch = parsed.first { $0.identifier.hasPrefix("at.obdev") }
        XCTAssertEqual(snitch?.identifier, "at.obdev.littlesnitch.networkextension")
        XCTAssertEqual(snitch?.teamID, "2XZUN9L63Z")
        XCTAssertEqual(snitch?.version, "6.1/6123")
        XCTAssertEqual(snitch?.name, "Little Snitch Network Extension")
        XCTAssertEqual(snitch?.state, "activated enabled")
    }

    /// The host is the extension id minus its last component. Both the
    /// extension and its host must be reported: the caller compares an app's own
    /// bundle id against this set, and an app can ship an extension under its
    /// own id.
    func testHostsIncludeBothTheExtensionAndTheAppItBelongsTo() {
        let hosts = SystemExtensionParser.hostIdentifiers(listing)
        XCTAssertTrue(hosts.contains("at.obdev.littlesnitch.networkextension"))
        XCTAssertTrue(hosts.contains("at.obdev.littlesnitch"))
        XCTAssertTrue(hosts.contains("com.example.tool.helper"))
        XCTAssertTrue(hosts.contains("com.example.tool"))
    }

    /// A three-component id has no component to spare: dropping one would leave
    /// "com.vendor", which prefixes every product that vendor ships. The parser
    /// keeps it whole — pinning so the `> 3` guard is not "simplified" to `> 2`.
    func testAThreeComponentExtensionIdIsNotShortened() {
        let line = "*\t*\tTEAM01\tcom.vendor.ext (1.0/1)\tExt\t[activated enabled]"
        let hosts = SystemExtensionParser.hostIdentifiers(line)
        XCTAssertEqual(hosts, ["com.vendor.ext"])
        XCTAssertFalse(hosts.contains("com.vendor"))
    }

    /// No extensions installed is the common case and must produce nothing at
    /// all, not an empty-identifier entry that would prefix-match everything.
    func testEmptyAndNoiseOutputProduceNoHosts() {
        for output in ["", "0 extension(s)", "--- com.apple.system_extension.network_extension\n"] {
            XCTAssertTrue(SystemExtensionParser.hostIdentifiers(output).isEmpty, output.debugDescription)
        }
        XCTAssertFalse(SystemExtensionParser.hostIdentifiers(listing).contains(""))
    }
}
