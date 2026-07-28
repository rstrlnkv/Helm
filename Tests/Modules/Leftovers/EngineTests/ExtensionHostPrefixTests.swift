import XCTest
import HelmRuntime
@testable import Module_Leftovers_Engine

private struct HostFakeFiles: LeftoversFilePort {
    func isWritable(_ url: URL) -> Bool { true }
    func children(of url: URL) -> [URL] { [] }
    func exists(_ path: String) -> Bool { false }
    func size(_ url: URL) -> Int { 0 }
    func readPlist(_ url: URL) -> PlistData? { nil }
}

private struct HostFakeApps: InstalledAppsPort {
    let ids: Set<String>
    func installedBundleIDs() -> Set<String> { ids }
}

private struct HostFakeExtensions: ExtensionsPort {
    var installed: [SystemExtensionInfo] = []
    func activeExtensionIdentifiers() -> Set<String> { [] }
    func installedExtensions() -> [SystemExtensionInfo] { installed }
    func disabledLabels() -> Set<String> { [] }
    func setDisabled(_ disabled: Bool, label: String) {}
}

/// The bug family this file exists for: an id matched as a bare character
/// prefix instead of as a namespace. `UninstallerEngine` (extension-host blame)
/// and `LeftoversScanner.owner(of:)` both spell it `$0 + "."`; the system
/// extension branch does not, and it is the one branch with no test.
final class ExtensionHostPrefixTests: XCTestCase {
    private func status(extensionID: String, installed: Set<String>) -> ItemStatus? {
        let info = SystemExtensionInfo(identifier: extensionID, teamID: "T1",
                                       name: "Ext", version: "1.0",
                                       state: "activated enabled", enabled: true)
        let scanner = LeftoversScanner(home: URL(fileURLWithPath: "/Users/x"),
                                       files: HostFakeFiles(),
                                       apps: HostFakeApps(ids: installed),
                                       extensions: HostFakeExtensions(installed: [info]))
        return scanner.scan().first { $0.kind == .systemExtension }?.status
    }

    /// "com.acme" and "com.acmecorp" are different vendors. Without the dot,
    /// the installed app lends its status to a stranger's extension: the row
    /// the user opened the module to find reads "in use" and is never shown as
    /// a leftover.
    func testAnUnrelatedVendorSharingLeadingCharactersIsNotTheHost() {
        XCTAssertEqual(status(extensionID: "com.acmecorp.vpn.ext",
                              installed: ["com.acme"]), .orphaned)
    }

    /// The same slip in the other direction: any installed app at all makes
    /// every extension look hosted once the prefix is allowed to stop
    /// mid-component.
    func testAShorterVendorPrefixIsNotTheHost() {
        XCTAssertEqual(status(extensionID: "com.vendorx.tunnel.ext",
                              installed: ["com.vendor"]), .orphaned)
    }

    /// The real relationship must keep working: an extension inside the
    /// installed app's namespace is in use.
    func testTheActualHostAppStillCounts() {
        XCTAssertEqual(status(extensionID: "com.acme.app.network",
                              installed: ["com.acme.app"]), .inUse)
    }

    /// A bundle id read off disk can be empty (`CFBundleIdentifier` missing or
    /// blank). An empty string is a prefix of everything, so one such app in
    /// the installed set silently marks the whole extension list as in use.
    func testAnEmptyInstalledIDHostsNothing() {
        XCTAssertEqual(status(extensionID: "com.acme.app.network",
                              installed: [""]), .orphaned)
    }
}
