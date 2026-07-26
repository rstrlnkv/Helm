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
                                                          fullDisk: .denied), .granted)
        XCTAssertEqual(PermissionNeed.fullDiskAccess.state(accessibility: .granted,
                                                           fullDisk: .denied), .denied)
    }
}
