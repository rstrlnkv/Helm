import XCTest
@testable import Module_Hosts_Engine

/// The verdict on a key's mode, and the three states of the agent.
final class KeyPermissionsAndAgentTests: XCTestCase {

    /// A mode straight out of `stat`, type bits and all, gets the same verdict
    /// as the permission bits alone.
    ///
    /// **This is why there is no masking in the subject.** The first draft
    /// masked with `0o777` and this test claimed the mask was the point;
    /// deleting the mask changed no answer here, because the type bits are
    /// `0o170000` and every question is asked with `0o077` or `0o022`. The
    /// helper went, and what is asserted now is the property that made it
    /// unnecessary — which is a thing that can be false in a later build, where
    /// «the mask is applied» was not.
    func testAModeStraightFromStatGetsTheSameVerdictAsItsPermissionBits() {
        XCTAssertEqual(KeyPermissions.privateKey(mode_t(S_IFREG) | 0o644),
                       KeyPermissions.privateKey(0o644))
        XCTAssertEqual(KeyPermissions.privateKey(mode_t(S_IFREG) | 0o600),
                       KeyPermissions.privateKey(0o600))
        XCTAssertEqual(KeyPermissions.directory(mode_t(S_IFDIR) | 0o755),
                       KeyPermissions.directory(0o755))
        XCTAssertEqual(KeyPermissions.privateKey(mode_t(S_IFREG) | 0o644), .tooOpen(fix: 0o600))
        XCTAssertEqual(KeyPermissions.directory(mode_t(S_IFDIR) | 0o755), .tooOpen(fix: 0o700))
    }

    func testThePrivateKeyModesSSHAccepts() {
        XCTAssertEqual(KeyPermissions.privateKey(0o600), .ok)
        XCTAssertEqual(KeyPermissions.privateKey(0o400), .ok)
    }

    /// 0644 is the mode a copy through a file sharing service, an unzip or a
    /// `cp` from a backup leaves behind, and it is the one `ssh` refuses with
    /// «UNPROTECTED PRIVATE KEY FILE».
    func testTheModeThatMakesSSHRefuseTheKey() {
        XCTAssertEqual(KeyPermissions.privateKey(0o644), .tooOpen(fix: 0o600))
        XCTAssertEqual(KeyPermissions.privateKey(0o660), .tooOpen(fix: 0o600))
        XCTAssertEqual(KeyPermissions.privateKey(0o604), .tooOpen(fix: 0o600))
    }

    /// The public half is meant to be readable by anyone; only somebody else
    /// being able to *write* it is a fault.
    func testThePublicHalfIsAllowedToBeReadable() {
        XCTAssertEqual(KeyPermissions.publicKey(0o644), .ok)
        XCTAssertEqual(KeyPermissions.publicKey(0o666), .tooOpen(fix: 0o644))
    }

    // MARK: - The agent

    private let oneKey = "256 SHA256:abc user@mac (ED25519)"

    func testAnAgentHoldingKeysIsReadAsHolding() {
        XCTAssertEqual(AgentList.read(status: 0, output: oneKey),
                       .holding(["SHA256:abc"]))
    }

    /// Reachable and empty is not the same as no agent: the load buttons on the
    /// page will work in the first case and cannot in the second, so a page that
    /// folded them would invite a press that fails.
    func testAnEmptyAgentAndADeadOneAreDifferentAnswers() {
        XCTAssertEqual(AgentList.read(status: 1, output: "The agent has no identities."), .empty)
        XCTAssertEqual(AgentList.read(status: 2, output: "Error connecting to agent: No such file"),
                       .unreachable)
    }

    /// Exit 0 with output this build cannot read is **not** «holding nothing».
    /// Saying empty there would be a claim about somebody's agent made out of a
    /// parse failure.
    func testASuccessThisBuildCannotParseIsNotAnEmptyAgent() {
        XCTAssertEqual(AgentList.read(status: 0, output: "something new in a later macOS"),
                       .unreachable)
    }

    func testTheBadgeAsksTheListRatherThanTheStatus() {
        XCTAssertTrue(AgentList.read(status: 0, output: oneKey).holds("SHA256:abc"))
        XCTAssertFalse(AgentList.read(status: 0, output: oneKey).holds("SHA256:other"))
        XCTAssertFalse(AgentList.empty.holds("SHA256:abc"))
        XCTAssertFalse(AgentList.unreachable.holds("SHA256:abc"))
    }
}
