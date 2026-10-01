import XCTest
@testable import HelmRuntime

/// An update revokes every grant of an ad-hoc signed app while the checkbox
/// stays ticked. What the user sees afterwards is decided here.
///
/// These are two strings and a comparison, so they are green whatever the app
/// hands over — which is exactly how the version-keyed defect survived them.
/// The wiring is `ThePermissionAuditAsksTheSignatureTests`, and what makes one
/// build tell itself apart from the next is `ARebuildIsANewProgramTests`.
final class PermissionAuditPlanTests: XCTestCase {
    func testOnlyWhatIsBothNeededAndMissingIsReported() {
        XCTAssertEqual(PermissionAuditPlan.missing(fullDisk: .denied, accessibility: .denied,
                                                   screenRecording: .denied,
                                                   needsFullDisk: true, needsAccessibility: true,
                                                   needsScreenRecording: false),
                       [.fullDiskAccess, .accessibility])
        XCTAssertEqual(PermissionAuditPlan.missing(fullDisk: .denied, accessibility: .denied,
                                                   screenRecording: .denied,
                                                   needsFullDisk: false, needsAccessibility: true,
                                                   needsScreenRecording: false),
                       [.accessibility])
    }

    /// A lapsed Screen Recording is named only when a module uses it, and never
    /// instead of the others.
    func testAScreenRecordingThatLapsedIsNamedOnlyWhenAModuleUsesIt() {
        XCTAssertEqual(PermissionAuditPlan.missing(fullDisk: .granted, accessibility: .granted,
                                                   screenRecording: .denied,
                                                   needsFullDisk: false, needsAccessibility: false,
                                                   needsScreenRecording: true),
                       [.screenRecording])
        XCTAssertTrue(PermissionAuditPlan.missing(fullDisk: .granted, accessibility: .granted,
                                                  screenRecording: .denied,
                                                  needsFullDisk: false, needsAccessibility: false,
                                                  needsScreenRecording: false).isEmpty,
                      "a grant nobody uses was reported as lapsed")
    }

    /// Nothing to say is the common case, and saying nothing is what it means.
    func testGrantedPermissionsAreSilent() {
        XCTAssertTrue(PermissionAuditPlan.missing(fullDisk: .granted, accessibility: .granted,
                                                  screenRecording: .granted,
                                                  needsFullDisk: true, needsAccessibility: true,
                                                  needsScreenRecording: true)
                        .isEmpty)
        XCTAssertTrue(PermissionAuditPlan.missing(fullDisk: .denied, accessibility: .denied,
                                                  screenRecording: .denied,
                                                  needsFullDisk: false, needsAccessibility: false,
                                                  needsScreenRecording: false)
                        .isEmpty)
    }

    /// The same build must not ask twice, and a new build must always ask —
    /// once there is a previous run to compare against.
    ///
    /// **Cdhashes, not version numbers.** Two builds of `0.7.1` are two
    /// programs to TCC and the same string to `CFBundleShortVersionString`;
    /// feeding this a version was the defect, so the fixtures here are the
    /// shape the app really hands over. `ARebuildIsANewProgramTests` is the
    /// half that proves those strings move where a version does not.
    func testItSpeaksOncePerBuild() {
        XCTAssertTrue(PermissionAuditPlan.shouldSpeak(lastSeenIdentity: "72580c71",
                                                      current: "62511e9b"))
        XCTAssertFalse(PermissionAuditPlan.shouldSpeak(lastSeenIdentity: "62511e9b",
                                                       current: "62511e9b"))
    }

    /// An unreadable identity is not a new identity: an unsigned bundle and a
    /// test host both read as nothing, and nothing must not mean «changed».
    func testAnEmptyIdentitySaysNothing() {
        XCTAssertFalse(PermissionAuditPlan.shouldSpeak(lastSeenIdentity: "62511e9b", current: ""))
    }

    /// And it must not be recorded either. Storing «cannot tell» makes the next
    /// run look like a first run, and a first run is silent — so one unreadable
    /// launch would cost the following update its audit.
    func testAnUnreadableRunLeavesTheBaselineAlone() {
        XCTAssertNil(PermissionAuditPlan.baseline(current: ""))
        XCTAssertEqual(PermissionAuditPlan.baseline(current: "62511e9b"), "62511e9b")
    }

    /// A first run has nothing to compare against. The audit exists to catch a
    /// grant that went away — "it was granted yesterday and is denied today" —
    /// and that is a question you can only ask the second time. Every module
    /// that needs a grant already shows its own note with a Grant button on its
    /// own page, so on day one the audit was asking for the two scariest
    /// permissions macOS has before the person had asked for anything.
    func testAFirstRunIsNotSpokenTo() {
        XCTAssertFalse(PermissionAuditPlan.shouldSpeak(lastSeenIdentity: "", current: "d395f05b"))
    }

    func testAChangedBuildStillSpeaks() {
        XCTAssertTrue(PermissionAuditPlan.shouldSpeak(lastSeenIdentity: "72580c71",
                                                      current: "d395f05b"))
    }

    func testTheSameBuildStaysQuiet() {
        XCTAssertFalse(PermissionAuditPlan.shouldSpeak(lastSeenIdentity: "d395f05b",
                                                       current: "d395f05b"))
    }
}
