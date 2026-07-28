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

/// "Can this be switched off" had two answers, and they disagreed.
///
/// `LaunchctlDisabled.canToggle` took a `status` and never read it, so it said
/// yes for a protected item that `LeftoverActions` — the rule the row's menu
/// obeys — says no to. The parameter that would have caught the disagreement
/// was the one going unused, and the test that covered it varied that very
/// parameter between two assertions that were both decided by the `com.apple.`
/// prefix instead.
final class OneToggleRuleTests: XCTestCase {

    private func item(kind: StaleKind, status: ItemStatus, identifier: String) -> StaleItem {
        StaleItem(path: "/tmp/\(identifier).plist", identifier: identifier, kind: kind,
                  sizeBytes: 0, status: status, writable: true)
    }

    func testAProtectedAgentIsNotToggleable() {
        let protected = item(kind: .launchAgent, status: .protectedItem, identifier: "com.vendor.tool")
        XCTAssertFalse(protected.canToggle,
                       "the row's menu refuses this and the checkbox's rule allowed it")
        XCTAssertFalse(LeftoverActions.available(for: protected, writable: true).contains(.turnOff))
    }

    /// And the two agree on every shape a scan can produce.
    func testTheTwoOffersAgreeEverywhere() {
        for kind in StaleKind.allCases {
            for status in [ItemStatus.orphaned, .inUse, .protectedItem] {
                for identifier in ["com.vendor.tool", "com.apple.thing", ""] {
                    let subject = item(kind: kind, status: status, identifier: identifier)
                    XCTAssertEqual(
                        subject.canToggle,
                        LeftoverActions.available(for: subject, writable: true).contains(.turnOff),
                        "\(kind)/\(status)/\(identifier.isEmpty ? "<no id>" : identifier)")
                }
            }
        }
    }
}

/// The cases that used to live on `LaunchctlDisabled.canToggle`, re-pointed at
/// the rule that survived it. They were real cases; only their subject is gone.
extension OneToggleRuleTests {

    /// Agents load in the user's own domain, so `launchctl disable` works
    /// without a password. Daemons are system-domain and would need root —
    /// offering a button that always fails is worse than offering none.
    func testOnlyAgentsAreOfferedTheSwitch() {
        XCTAssertTrue(offer(kind: .launchAgent, status: .inUse, id: "com.acme.helper"))
        XCTAssertFalse(offer(kind: .launchDaemon, status: .inUse, id: "com.acme.helper"))
        XCTAssertFalse(offer(kind: .preference, status: .inUse, id: "com.acme.helper"))
    }

    /// Apple's own agents keep the Mac working; Helm never offers to stop one.
    func testAppleAgentsAreNeverOffered() {
        XCTAssertFalse(offer(kind: .launchAgent, status: .protectedItem, id: "com.apple.Siri.agent"))
        XCTAssertFalse(offer(kind: .launchAgent, status: .inUse, id: "com.apple.Siri.agent"))
    }

    /// A job Helm could not read a label for. `launchctl` is addressed by
    /// label, so there is nothing to address.
    func testAnItemWithoutALabelIsNotOffered() {
        XCTAssertFalse(offer(kind: .launchAgent, status: .inUse, id: ""))
    }

    private func offer(kind: StaleKind, status: ItemStatus, id: String) -> Bool {
        StaleItem(path: "/tmp/x.plist", identifier: id, kind: kind, sizeBytes: 0,
                  status: status, writable: true).canToggle
    }
}
