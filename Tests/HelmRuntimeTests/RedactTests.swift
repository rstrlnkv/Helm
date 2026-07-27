import XCTest
@testable import HelmRuntime

/// Package names in the log.
///
/// What somebody installs from Homebrew is the same class of fact as which
/// applications they keep: the log needs to tell one operation from another,
/// not to record the software. Added when the Homebrew module got logging at
/// all — until then it ran installs and uninstalls and wrote nothing, so there
/// was no line to redact.
final class RedactPackageTests: XCTestCase {

    func testAPackageNameIsTaggedNotWritten() {
        let tag = Redact.pkg("hello")
        XCTAssertFalse(tag.contains("hello"))
        XCTAssertTrue(tag.hasPrefix("pkg#"))
    }

    /// Stable, so two lines about the same package can be tied together, and
    /// distinct, so two packages cannot be confused.
    func testTheSamePackageAlwaysGetsTheSameTag() {
        XCTAssertEqual(Redact.pkg("caddy"), Redact.pkg("caddy"))
        XCTAssertNotEqual(Redact.pkg("caddy"), Redact.pkg("deno"))
    }
}
