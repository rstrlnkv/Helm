import XCTest
@testable import HelmRuntime

/// An update revokes every grant of an ad-hoc signed app while the checkbox
/// stays ticked. What the user sees afterwards is decided here.
final class PermissionAuditPlanTests: XCTestCase {
    func testOnlyWhatIsBothNeededAndMissingIsReported() {
        XCTAssertEqual(PermissionAuditPlan.missing(fullDisk: .denied, accessibility: .denied,
                                                   needsFullDisk: true, needsAccessibility: true),
                       [.fullDiskAccess, .accessibility])
        XCTAssertEqual(PermissionAuditPlan.missing(fullDisk: .denied, accessibility: .denied,
                                                   needsFullDisk: false, needsAccessibility: true),
                       [.accessibility])
    }

    /// Nothing to say is the common case, and saying nothing is what it means.
    func testGrantedPermissionsAreSilent() {
        XCTAssertTrue(PermissionAuditPlan.missing(fullDisk: .granted, accessibility: .granted,
                                                  needsFullDisk: true, needsAccessibility: true)
                        .isEmpty)
        XCTAssertTrue(PermissionAuditPlan.missing(fullDisk: .denied, accessibility: .denied,
                                                  needsFullDisk: false, needsAccessibility: false)
                        .isEmpty)
    }

    /// The same build must not ask twice, and a new build must always ask —
    /// once there is a previous version to compare against.
    func testItSpeaksOncePerVersion() {
        XCTAssertTrue(PermissionAuditPlan.shouldSpeak(lastSeenVersion: "0.7.0", current: "0.7.1"))
        XCTAssertFalse(PermissionAuditPlan.shouldSpeak(lastSeenVersion: "0.7.1", current: "0.7.1"))
    }

    /// An unreadable version is not a new version.
    func testAnEmptyVersionSaysNothing() {
        XCTAssertFalse(PermissionAuditPlan.shouldSpeak(lastSeenVersion: "0.7.1", current: ""))
    }

    /// A first run has nothing to compare against. The audit exists to catch a
    /// grant that went away — "it was granted yesterday and is denied today" —
    /// and that is a question you can only ask the second time. Every module
    /// that needs a grant already shows its own note with a Grant button on its
    /// own page, so on day one the audit was asking for the two scariest
    /// permissions macOS has before the person had asked for anything.
    func testAFirstRunIsNotSpokenTo() {
        XCTAssertFalse(PermissionAuditPlan.shouldSpeak(lastSeenVersion: "", current: "0.8.0"))
    }

    func testAChangedVersionStillSpeaks() {
        XCTAssertTrue(PermissionAuditPlan.shouldSpeak(lastSeenVersion: "0.7.1", current: "0.8.0"))
    }

    func testTheSameVersionStaysQuiet() {
        XCTAssertFalse(PermissionAuditPlan.shouldSpeak(lastSeenVersion: "0.8.0", current: "0.8.0"))
    }
}
