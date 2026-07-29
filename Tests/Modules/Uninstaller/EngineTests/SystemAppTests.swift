import XCTest
@testable import Module_Uninstaller_Engine

/// Safari was offered for removal at "0 Б", with a checkbox.
///
/// `/Applications` is one of the folders the lister reads, and Safari lives
/// there. Ticking it costs a leftovers scan and a click, after which macOS
/// refuses the move and the failure report explains why — which is the right
/// screen at the wrong time: the answer was knowable before the click.
///
/// The test is the same one `LeftoverActions.available` already applies to the
/// leftovers list — a `com.apple.` identifier means the system owns it, so the
/// row offers looking and nothing else. It is spelled again here rather than
/// shared because the two engines do not depend on each other; the rule is one
/// line and the duplication is deliberate and noted.
final class SystemAppTests: XCTestCase {

    func testAnAppleIdentifierIsTheSystems() {
        XCTAssertTrue(SystemApp.isSystem(bundleID: "com.apple.Safari"))
        XCTAssertTrue(SystemApp.isSystem(bundleID: "com.apple.dt.Xcode"))
    }

    func testAnOrdinaryAppIsNot() {
        XCTAssertFalse(SystemApp.isSystem(bundleID: "com.acme.tool"))
        XCTAssertFalse(SystemApp.isSystem(bundleID: "org.mozilla.firefox"))
    }

    /// The separator is the rule, exactly as it is where a missing dot once sent
    /// somebody to turn off a different vendor's system extension: an id may
    /// start with the letters of another without being under it.
    func testAVendorWhoseNameMerelyStartsTheSameWayIsNotApple() {
        XCTAssertFalse(SystemApp.isSystem(bundleID: "com.applesauce.jam"))
        XCTAssertFalse(SystemApp.isSystem(bundleID: "com.apple"))
        XCTAssertFalse(SystemApp.isSystem(bundleID: "net.com.apple.fake"))
    }
}
