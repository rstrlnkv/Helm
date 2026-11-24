import XCTest
@testable import Module_Leftovers_Engine

/// What Helm may actually do to an item, as opposed to what it would like to.
/// Each answer is a fact about the system, not a policy: a button that cannot
/// work is worse than no button, and a missing button that could have worked
/// is a complaint too.
final class LeftoverActionsTests: XCTestCase {
    /// `writable` is the item's own, not a second argument handed to
    /// `available`, so no test can ask about a shape a scan cannot produce.
    private func item(_ kind: StaleKind, _ status: ItemStatus,
                      id: String = "com.acme.helper",
                      path: String = "/Users/x/Library/LaunchAgents/com.acme.helper.plist",
                      writable: Bool = true)
        -> StaleItem {
        StaleItem(path: path, identifier: id, kind: kind, sizeBytes: 1, status: status,
                  writable: writable)
    }

    // MARK: - Turning off

    func testUserAgentCanBeTurnedOff() {
        let actions = LeftoverActions.available(for: item(.launchAgent, .inUse))
        XCTAssertTrue(actions.contains(.turnOff))
    }

    /// A system-wide agent still loads in the user's own launchd domain, so it
    /// can be switched off without a password even though its file cannot be
    /// touched.
    func testSystemWideAgentCanBeTurnedOffButNotDeleted() {
        let system = item(.launchAgent, .inUse,
                          path: "/Library/LaunchAgents/com.acme.helper.plist",
                          writable: false)
        let actions = LeftoverActions.available(for: system)
        XCTAssertTrue(actions.contains(.turnOff))
        XCTAssertFalse(actions.contains(.delete))
    }

    /// A daemon is never deleted from here, writable file or not: unloading it
    /// needs root, and a file moved out from under a loaded daemon is not a stop.
    func testAWritableDaemonStillHasNoDelete() {
        let actions = LeftoverActions.available(
            for: item(.launchDaemon, .orphaned, path: "/tmp/com.acme.helper.plist", writable: true))
        XCTAssertFalse(actions.contains(.delete))
    }

    func testDaemonsOfferNothingButReveal() {
        let actions = LeftoverActions.available(for: item(.launchDaemon, .inUse, writable: false))
        XCTAssertEqual(actions, [.reveal])
    }

    // MARK: - Deleting

    func testInUseUserAgentCanBeDeleted() {
        XCTAssertTrue(LeftoverActions.available(for: item(.launchAgent, .inUse))
            .contains(.delete))
    }

    func testUnwritableItemCannotBeDeleted() {
        XCTAssertFalse(LeftoverActions.available(for: item(.preference, .orphaned, writable: false))
            .contains(.delete))
    }

    func testAppleItemsAreNeverTouched() {
        let apple = item(.launchAgent, .protectedItem, id: "com.apple.Siri.agent")
        XCTAssertEqual(LeftoverActions.available(for: apple), [.reveal])
    }

    /// A system extension is not a file: nothing here applies, and the row
    /// sends the user to System Settings instead.
    func testSystemExtensionsHaveNoFileActions() {
        let ext = item(.systemExtension, .orphaned, path: "com.acme.app.network",
                       writable: false)
        XCTAssertEqual(LeftoverActions.available(for: ext), [.systemSettings])
    }

    /// The reason is macOS's, not an administrator's, even for a third-party
    /// extension the scan did not mark protected: SIP refuses everyone else.
    func testAThirdPartySystemExtensionIsWithheldByMacOS() {
        let ext = item(.systemExtension, .orphaned, id: "com.acme.app.network",
                       path: "com.acme.app.network", writable: false)
        XCTAssertEqual(LeftoverActions.whyDeleteIsWithheld(from: ext), .protectedByMacOS)
    }

    /// Deleting something that is in use is a different promise from clearing
    /// a leftover — the caller has to say so out loud.
    func testDeletingSomethingInUseNeedsConfirmation() {
        XCTAssertNotNil(LeftoverActions.askBeforeDeleting(item(.launchAgent, .inUse)))
        XCTAssertNil(LeftoverActions.askBeforeDeleting(item(.preference, .orphaned)))
    }
}

/// "Can this be switched off" has one answer, `LeftoverActions`, the rule the
/// row's menu obeys — including for a protected item, where a prefix check
/// alone would decide nothing.
final class OneToggleRuleTests: XCTestCase {

    /// A file in the folder this module actually reads, named after its own label —
    /// see `offer` below for why the fixture has to be a shape a scan can produce.
    /// Elsewhere these rows would be unswitchable for a second reason, and
    /// `testAProtectedAgentIsNotToggleable` would pass with the protected rule
    /// deleted.
    private func item(kind: StaleKind, status: ItemStatus, identifier: String) -> StaleItem {
        StaleItem(path: "/Users/x/Library/LaunchAgents/\(identifier).plist",
                  identifier: identifier, kind: kind,
                  sizeBytes: 0, status: status, writable: true)
    }

    func testAProtectedAgentIsNotToggleable() {
        let protected = item(kind: .launchAgent, status: .protectedItem, identifier: "com.vendor.tool")
        XCTAssertFalse(protected.canToggle,
                       "the row's menu refuses this and the checkbox's rule allowed it")
        XCTAssertFalse(LeftoverActions.available(for: protected).contains(.turnOff))
    }

    /// And the two agree on every shape a scan can produce.
    func testTheTwoOffersAgreeEverywhere() {
        for kind in StaleKind.allCases {
            for status in [ItemStatus.orphaned, .inUse, .protectedItem] {
                for identifier in ["com.vendor.tool", "com.apple.thing", ""] {
                    let subject = item(kind: kind, status: status, identifier: identifier)
                    XCTAssertEqual(
                        subject.canToggle,
                        LeftoverActions.available(for: subject).contains(.turnOff),
                        "\(kind)/\(status)/\(identifier.isEmpty ? "<no id>" : identifier)")
                }
            }
        }
    }
}

/// Whether a launch item can be switched off, asked of `LeftoverActions`.
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

    /// **The path is the file the label came from**: this module reads two
    /// LaunchAgents folders, and launchd's convention is that a job's file is named
    /// after its label. A file called `x.plist` claiming `com.acme.helper` is the
    /// shape `ALabelTheFileWouldNotRegisterTests` is about, and no scan produces it
    /// for the ordinary case, so what these three assertions vary is the kind.
    private func offer(kind: StaleKind, status: ItemStatus, id: String) -> Bool {
        StaleItem(path: "/Users/x/Library/LaunchAgents/\(id).plist", identifier: id, kind: kind,
                  sizeBytes: 0, status: status, writable: true).canToggle
    }
}
