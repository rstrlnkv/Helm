import XCTest
import HelmRuntime
@testable import Module_Leftovers_Engine

/// An id is matched as a namespace, not as a bare character prefix:
/// `UninstallerEngine` (extension-host blame), `StaleItemRules.isOwned` and the
/// system extension branch all spell it `$0 + "."`.
final class ExtensionHostPrefixTests: XCTestCase {
    private func status(extensionID: String, installed: Set<String>) -> ItemStatus? {
        let info = SystemExtensionInfo(identifier: extensionID, version: "1.0", enabled: true)
        let scanner = LeftoversScanner(home: URL(fileURLWithPath: "/Users/x"),
                                       files: LeftoversFakeFiles(),
                                       apps: LeftoversFakeApps(ids: installed),
                                       extensions: LeftoversFakeLoaded(installed: [info]))
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
