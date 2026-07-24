import XCTest
@testable import HelmRuntime

final class UpdateVersionTests: XCTestCase {
    func test_newer_patch_minor_major() {
        XCTAssertTrue(UpdateVersion.isNewer("v0.2.0", than: "0.1.0"))
        XCTAssertTrue(UpdateVersion.isNewer("1.0.0", than: "0.9.9"))
        XCTAssertTrue(UpdateVersion.isNewer("0.1.1", than: "0.1.0"))
    }
    func test_same_or_older_is_not_newer() {
        XCTAssertFalse(UpdateVersion.isNewer("0.1.0", than: "0.1.0"))
        XCTAssertFalse(UpdateVersion.isNewer("v1.2.3", than: "1.2.3"))
        XCTAssertFalse(UpdateVersion.isNewer("0.1.0", than: "0.2.0"))
    }
    func test_uneven_component_counts() {
        XCTAssertTrue(UpdateVersion.isNewer("1.0", than: "0.9.9"))
        XCTAssertFalse(UpdateVersion.isNewer("1.0", than: "1.0.0"))
        XCTAssertTrue(UpdateVersion.isNewer("1.0.1", than: "1.0"))
    }
}
