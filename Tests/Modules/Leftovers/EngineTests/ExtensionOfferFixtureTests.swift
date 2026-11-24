import Foundation
import XCTest
import HelmRuntime
@testable import Module_Leftovers_Engine

/// An assertion that nothing removable comes back holds just as well for a
/// list with no rows in it. A fixture that sets a field `installedExtensions()`
/// does not return hands the scan an empty list, and the assertion would hold
/// if every extension on the machine were offered for deletion.
final class ExtensionOfferFixtureTests: XCTestCase {

    private let home = URL(fileURLWithPath: "/Users/x")
    private let info = SystemExtensionInfo(identifier: "com.gone.vendor.app.ext",
                                           version: "1.0", enabled: true)

    private func scan(_ extensions: LeftoversFakeLoaded, installed: Set<String> = []) -> [StaleItem] {
        LeftoversScanner(home: home, files: LeftoversFakeFiles(),
                         apps: LeftoversFakeApps(ids: installed), extensions: extensions).scan()
    }

    /// The precondition the existing test never states. An assertion about what
    /// is offered has to be made over a list that has the thing in it.
    func testTheFixtureThatNamesAnActivatedExtensionActuallyContainsOne() {
        let items = scan(LeftoversFakeLoaded(installed: [
            SystemExtensionInfo(identifier: "com.gone.vendor.app.ext", version: "1", enabled: true),
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
    /// if it tried (`LeftoversScanTests.testExtensionsAreNeverSelectable`).
    func testAnExtensionWhoseHostIsGoneIsListedOrphanedAndStillNotOffered() throws {
        let items = scan(LeftoversFakeLoaded(installed: [info]))
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
        let items = scan(LeftoversFakeLoaded(installed: [info]), installed: ["com.gone.vendor.app"])
        let extensionItem = try XCTUnwrap(items.first { $0.kind == .systemExtension })

        XCTAssertEqual(extensionItem.status, .inUse)
        XCTAssertFalse(extensionItem.removable)
    }
}
