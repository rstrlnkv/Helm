import XCTest
@testable import Module_Leftovers_Engine

/// What Helm may actually do to an item, as opposed to what it would like to.
/// Each answer is a fact about the system, not a policy: a button that cannot
/// work is worse than no button, and a missing button that could have worked
/// is the complaint that produced this file.
final class LeftoverActionsTests: XCTestCase {
    private func item(_ kind: StaleKind, _ status: ItemStatus,
                      id: String = "com.acme.helper",
                      path: String = "/Users/x/Library/LaunchAgents/com.acme.helper.plist")
        -> StaleItem {
        StaleItem(path: path, identifier: id, kind: kind, sizeBytes: 1, status: status)
    }

    // MARK: - Turning off

    func testUserAgentCanBeTurnedOff() {
        let actions = LeftoverActions.available(for: item(.launchAgent, .inUse), writable: true)
        XCTAssertTrue(actions.contains(.turnOff))
    }

    /// A system-wide agent still loads in the user's own launchd domain, so it
    /// can be switched off without a password even though its file cannot be
    /// touched.
    func testSystemWideAgentCanBeTurnedOffButNotDeleted() {
        let system = item(.launchAgent, .inUse,
                          path: "/Library/LaunchAgents/com.acme.helper.plist")
        let actions = LeftoverActions.available(for: system, writable: false)
        XCTAssertTrue(actions.contains(.turnOff))
        XCTAssertFalse(actions.contains(.delete))
    }

    func testDaemonsOfferNothingButReveal() {
        let actions = LeftoverActions.available(for: item(.launchDaemon, .inUse), writable: false)
        XCTAssertEqual(actions, [.reveal])
    }

    // MARK: - Deleting

    func testInUseUserAgentCanBeDeleted() {
        XCTAssertTrue(LeftoverActions.available(for: item(.launchAgent, .inUse), writable: true)
            .contains(.delete))
    }

    func testUnwritableItemCannotBeDeleted() {
        XCTAssertFalse(LeftoverActions.available(for: item(.preference, .orphaned), writable: false)
            .contains(.delete))
    }

    func testAppleItemsAreNeverTouched() {
        let apple = item(.launchAgent, .protectedItem, id: "com.apple.Siri.agent")
        XCTAssertEqual(LeftoverActions.available(for: apple, writable: true), [.reveal])
    }

    /// A system extension is not a file: nothing here applies, and the row
    /// sends the user to System Settings instead.
    func testSystemExtensionsHaveNoFileActions() {
        let ext = item(.systemExtension, .orphaned, path: "com.acme.app.network")
        XCTAssertEqual(LeftoverActions.available(for: ext, writable: false), [.systemSettings])
    }

    /// Deleting something that is in use is a different promise from clearing
    /// a leftover — the caller has to say so out loud.
    func testDeletingSomethingInUseNeedsConfirmation() {
        XCTAssertTrue(LeftoverActions.needsConfirmation(item(.launchAgent, .inUse)))
        XCTAssertFalse(LeftoverActions.needsConfirmation(item(.preference, .orphaned)))
    }
}
