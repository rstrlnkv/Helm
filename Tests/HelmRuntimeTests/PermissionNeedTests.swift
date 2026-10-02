import XCTest
@testable import HelmRuntime

/// Every option that needs a grant must be able to say which one, so the UI can
/// warn instead of failing silently — the pointer nudge shipped for months
/// doing nothing because nothing connected the setting to the permission.
final class PermissionNeedTests: XCTestCase {
    func testEveryNeedNamesItsPermission() {
        for need in PermissionNeed.allCases {
            XCTAssertFalse(need.title.isEmpty, "\(need) has no title")
            XCTAssertFalse(need.why.isEmpty, "\(need) does not say why it is needed")
        }
    }

    func testFeaturesMapToTheirPermission() {
        XCTAssertEqual(PermissionNeed.of(.pointerNudge), .accessibility)
        XCTAssertEqual(PermissionNeed.of(.appContainers), .fullDiskAccess)
        XCTAssertEqual(PermissionNeed.of(.wholeDiskScan), .fullDiskAccess)
        XCTAssertEqual(PermissionNeed.of(.leftoverRemoval), .fullDiskAccess)
        XCTAssertEqual(PermissionNeed.of(.screenCapture), .screenRecording)
    }

    /// A feature that needs nothing must say so rather than pointing at a
    /// permission it does not use — a false warning trains people to ignore
    /// real ones.
    func testFeaturesWithoutARequirement() {
        XCTAssertNil(PermissionNeed.of(.vpnControl))
        XCTAssertNil(PermissionNeed.of(.homebrew))
    }

    func testStateReadsBackFromTheProbe() {
        XCTAssertEqual(PermissionNeed.accessibility.state(accessibility: .granted,
                                                          fullDisk: .denied,
                                                          screenRecording: .denied), .granted)
        XCTAssertEqual(PermissionNeed.fullDiskAccess.state(accessibility: .granted,
                                                           fullDisk: .denied,
                                                           screenRecording: .granted), .denied)
    }

    /// The third grant answers for itself and for nobody else: each of the three
    /// is denied alone, and only its own need reads it.
    func testEachGrantAnswersOnlyForItsOwnNeed() {
        for denied in PermissionNeed.allCases {
            let reading = (accessibility: denied == .accessibility ? PermissionState.denied : .granted,
                           fullDisk: denied == .fullDiskAccess ? PermissionState.denied : .granted,
                           screenRecording: denied == .screenRecording ? PermissionState.denied : .granted)
            for need in PermissionNeed.allCases {
                let state = need.state(accessibility: reading.accessibility, fullDisk: reading.fullDisk,
                                       screenRecording: reading.screenRecording)
                XCTAssertEqual(state, need == denied ? .denied : .granted,
                               "\(need) read the answer for \(denied)")
            }
        }
    }

    func testTheDeclaredNameOfScreenRecordingIsTheContractsOwn() {
        XCTAssertEqual(PermissionNeed.screenRecording.declaredName, "screenRecording")
    }
}
