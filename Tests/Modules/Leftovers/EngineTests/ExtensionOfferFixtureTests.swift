import Foundation
import XCTest
import HelmRuntime
@testable import Module_Leftovers_Engine

private struct SilentFiles: LeftoversFilePort {
    func isWritable(_ url: URL) -> Bool { true }
    func children(of url: URL) -> [URL] { [] }
    func exists(_ path: String) -> Bool { false }
    func size(_ url: URL) -> Int { 100 }
    func readPlist(_ url: URL) -> PlistData? { nil }
}

private struct NoApps: InstalledAppsPort {
    let ids: Set<String>
    func installedBundleIDs() -> Set<String> { ids }
}

/// The port as the existing suite fakes it. `ids` is a stored property and
/// nothing reads it: `installedExtensions()` answers `installed`, which is a
/// different field.
private struct FakeExtensions: ExtensionsPort {
    var installed: [SystemExtensionInfo] = []
    var disabled: Set<String> = []
    func installedExtensions() -> [SystemExtensionInfo] { installed }
    func disabledLabels() -> Set<String> { disabled }
    func setDisabled(_ disabled: Bool, label: String) {}
}

/// `LeftoversScanTests.testExtensionsOfMissingAppsAreOfferedUnlessStillActive`
/// builds its extension with `FakeExtensions(ids: ["com.gone.vendor.app.ext"])`
/// and then asserts that nothing removable came back.
///
/// Nothing removable came back because nothing came back. `ids` is not the
/// field `installedExtensions()` returns — the scan is handed an empty list, so
/// the assertion is about a list with no rows in it, and it would hold just the
/// same if every extension on the machine were offered for deletion in a batch.
///
/// This is the `LaunchctlDisabledTests` shape: a parameter varied between
/// fixtures that the code under test never reads.
final class ExtensionOfferFixtureTests: XCTestCase {

    private let home = URL(fileURLWithPath: "/Users/x")
    private let info = SystemExtensionInfo(identifier: "com.gone.vendor.app.ext",
                                           teamID: "T1", name: "Gone Network",
                                           version: "1.0", state: "activated enabled",
                                           enabled: true)

    private func scan(_ extensions: FakeExtensions, installed: Set<String> = []) -> [StaleItem] {
        LeftoversScanner(home: home, files: SilentFiles(),
                         apps: NoApps(ids: installed), extensions: extensions).scan()
    }

    /// The precondition the existing test never states. An assertion about what
    /// is offered has to be made over a list that has the thing in it.
    func testTheFixtureThatNamesAnActivatedExtensionActuallyContainsOne() {
        let items = scan(FakeExtensions(installed: [
            SystemExtensionInfo(identifier: "com.gone.vendor.app.ext", teamID: "T",
                                name: "Ext", version: "1", state: "activated enabled",
                                enabled: true),
        ]))

        XCTAssertFalse(items.filter { $0.kind == .systemExtension }.isEmpty,
                       "the scan returned \(items.count) rows for a fixture whose whole "
                       + "subject is one activated extension. The fixture used to set "
                       + "`ids`, a field left behind when `activeExtensionIdentifiers` was "
                       + "deleted and one the port never answered with, so the rule below "
                       + "was asserted over an empty list")
    }

    /// What the rule actually is, over a list that contains the extension:
    /// listed, called an orphan because its host is gone, and never offered —
    /// Helm cannot remove an extension by moving a file, and SIP would stop it
    /// if it tried. `LeftoversScanTests.testExtensionsAreNeverSelectable` says
    /// the same thing about the same items, which is why the "…AreOffered…"
    /// name above it should never have been able to pass.
    func testAnExtensionWhoseHostIsGoneIsListedOrphanedAndStillNotOffered() throws {
        let items = scan(FakeExtensions(installed: [info]))
        let extensionItem = try XCTUnwrap(items.first { $0.kind == .systemExtension })

        XCTAssertEqual(extensionItem.status, .orphaned, "its host app is not installed")
        XCTAssertFalse(extensionItem.removable,
                       "a ticked box here sends a batch at something the filesystem "
                       + "cannot deliver")
        XCTAssertEqual(extensionItem.actions, [.systemSettings],
                       "the row's own menu sends the person where the removal really is")
    }

    /// And with the host installed the same extension is in use — so the status
    /// above is a fact about the app being gone and not the only answer this
    /// branch can give.
    func testTheSameExtensionWithItsHostInstalledIsInUse() throws {
        let items = scan(FakeExtensions(installed: [info]), installed: ["com.gone.vendor.app"])
        let extensionItem = try XCTUnwrap(items.first { $0.kind == .systemExtension })

        XCTAssertEqual(extensionItem.status, .inUse)
        XCTAssertFalse(extensionItem.removable)
    }
}
