import XCTest
@testable import Module_Uninstaller_Engine

/// A `com.apple.` identifier is the system's: macOS refuses the move, and the
/// answer is knowable before the click. The rule is `LeftoverActions.available`'s,
/// spelled again because the two engines do not depend on each other.
final class SystemAppTests: XCTestCase {

    func testAnAppleIdentifierIsTheSystems() {
        XCTAssertTrue(SystemApp.isSystem(bundleID: "com.apple.Safari"))
        XCTAssertTrue(SystemApp.isSystem(bundleID: "com.apple.dt.Xcode"))
    }

    func testAnOrdinaryAppIsNot() {
        XCTAssertFalse(SystemApp.isSystem(bundleID: "com.acme.tool"))
        XCTAssertFalse(SystemApp.isSystem(bundleID: "org.mozilla.firefox"))
    }

    /// The separator is the rule: an id may start with the letters of another
    /// without being under it.
    func testAVendorWhoseNameMerelyStartsTheSameWayIsNotApple() {
        XCTAssertFalse(SystemApp.isSystem(bundleID: "com.applesauce.jam"))
        XCTAssertFalse(SystemApp.isSystem(bundleID: "com.apple"))
        XCTAssertFalse(SystemApp.isSystem(bundleID: "net.com.apple.fake"))
    }
}
