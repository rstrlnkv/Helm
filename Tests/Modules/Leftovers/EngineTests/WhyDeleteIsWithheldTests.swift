import XCTest
import Module_Leftovers_Engine

/// **«Needs an administrator to delete» was drawn where no administrator can
/// help.** The row's menu said it for anything without `.delete`, and
/// `LeftoverActions.available` withholds that from `com.apple.*` and from
/// `.protectedItem` as well — so the one line the page offers instead of a button
/// sent somebody looking for a password over a file the rule will not release at
/// any password.
///
/// Two answers, because the rule withholds delete for two different reasons: a
/// permission an administrator has, and a decision of Apple's that nobody on this
/// Mac can take back.
final class WhyDeleteIsWithheldTests: XCTestCase {

    private func item(_ kind: StaleKind, _ status: ItemStatus,
                      id: String = "com.acme.helper",
                      path: String = "/Users/x/Library/LaunchAgents/com.acme.helper.plist",
                      writable: Bool = true) -> StaleItem {
        StaleItem(path: path, identifier: id, kind: kind, sizeBytes: 1, status: status,
                  writable: writable)
    }

    func testARowThatCanBeDeletedIsWithheldNothing() {
        XCTAssertNil(LeftoverActions.whyDeleteIsWithheld(from: item(.launchAgent, .orphaned)))
    }

    /// A file in `/Library` whose folder belongs to root: this is the case the
    /// sentence was written for, and the only one it was right about.
    func testAFileHelmCannotMoveNeedsAnAdministrator() {
        let system = item(.launchAgent, .orphaned,
                          path: "/Library/LaunchAgents/com.acme.helper.plist", writable: false)
        XCTAssertEqual(LeftoverActions.whyDeleteIsWithheld(from: system), .needsAdministrator)
    }

    /// A daemon's file can be moved by an administrator; what needs root is
    /// unloading it, which is why the rule withholds the button either way.
    func testADaemonNeedsAnAdministrator() {
        XCTAssertEqual(LeftoverActions.whyDeleteIsWithheld(from: item(.launchDaemon, .orphaned,
                                                                     writable: false)),
                       .needsAdministrator)
    }

    func testApplesOwnItemIsProtectedRatherThanLocked() {
        let apple = item(.launchAgent, .orphaned, id: "com.apple.Siri.agent")
        XCTAssertEqual(LeftoverActions.whyDeleteIsWithheld(from: apple), .protectedByMacOS,
                       "an administrator password does nothing for this row, and the menu "
                       + "sent the person to find one")
    }

    func testAProtectedItemIsProtectedRatherThanLocked() {
        XCTAssertEqual(LeftoverActions.whyDeleteIsWithheld(from: item(.preference, .protectedItem)),
                       .protectedByMacOS)
    }

    /// Not a file at all: SIP stops anyone but the installing app from removing
    /// it. The row draws «Manage…» rather than this menu, and the answer still has
    /// to be the honest one.
    func testASystemExtensionIsProtectedByMacOS() {
        let ext = item(.systemExtension, .orphaned, path: "com.acme.app.network", writable: false)
        XCTAssertEqual(LeftoverActions.whyDeleteIsWithheld(from: ext), .protectedByMacOS)
    }

    /// **One rule, asked twice.** The reason exists only where the button does
    /// not, over every shape a scan can produce — otherwise the row can draw a
    /// delete button and an explanation of why it cannot delete, or neither.
    func testAReasonExistsExactlyWhereTheButtonDoesNot() {
        for kind in StaleKind.allCases {
            for status in [ItemStatus.orphaned, .inUse, .protectedItem] {
                for id in ["com.vendor.tool", "com.apple.thing", ""] {
                    for writable in [true, false] {
                        let subject = item(kind, status, id: id, writable: writable)
                        XCTAssertEqual(
                            LeftoverActions.whyDeleteIsWithheld(from: subject) == nil,
                            subject.actions.contains(.delete),
                            "\(kind)/\(status)/\(id.isEmpty ? "<no id>" : id)/writable=\(writable)")
                    }
                }
            }
        }
    }
}
