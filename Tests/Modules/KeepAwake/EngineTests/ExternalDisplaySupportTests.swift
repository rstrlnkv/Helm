import XCTest
@testable import Module_KeepAwake_Engine

final class ExternalDisplaySupportTests: XCTestCase {
    func test_empty_flags_no_external() {
        XCTAssertFalse(ExternalDisplaySupport.hasExternal(builtInFlags: []))
    }
    func test_only_builtin_no_external() {
        XCTAssertFalse(ExternalDisplaySupport.hasExternal(builtInFlags: [true]))
    }
    func test_builtin_and_external_has_external() {
        XCTAssertTrue(ExternalDisplaySupport.hasExternal(builtInFlags: [true, false]))
    }
    func test_only_external_has_external() {
        XCTAssertTrue(ExternalDisplaySupport.hasExternal(builtInFlags: [false]))
    }
}
