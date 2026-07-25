import XCTest
@testable import Module_Uninstaller_Engine

final class GlobMatchTests: XCTestCase {
    func testPrefixStar() {
        XCTAssertTrue(GlobMatch.matches("com.acme.tool.helper", pattern: "com.acme.tool*"))
        XCTAssertTrue(GlobMatch.matches("com.acme.tool", pattern: "com.acme.tool*"))
        XCTAssertFalse(GlobMatch.matches("com.other.tool", pattern: "com.acme.tool*"))
    }

    func testSuffixStar() {
        XCTAssertTrue(GlobMatch.matches("2XZUN9L63Z.com.acme.tool", pattern: "*.com.acme.tool"))
        XCTAssertTrue(GlobMatch.matches("group.com.acme.tool", pattern: "*.com.acme.tool"))
        XCTAssertFalse(GlobMatch.matches("com.acme.toolbox", pattern: "*.com.acme.tool"))
    }

    /// Two stars: team prefix AND an extension suffix in one name.
    func testStarsOnBothSides() {
        XCTAssertTrue(GlobMatch.matches("2XZUN9L63Z.com.acme.tool.ext", pattern: "*com.acme.tool*"))
        XCTAssertTrue(GlobMatch.matches("com.acme.tool", pattern: "*com.acme.tool*"))
        XCTAssertFalse(GlobMatch.matches("com.acme.other", pattern: "*com.acme.tool*"))
    }

    func testNoStarIsExact() {
        XCTAssertTrue(GlobMatch.matches("com.acme.tool", pattern: "com.acme.tool"))
        XCTAssertFalse(GlobMatch.matches("com.acme.tool.ext", pattern: "com.acme.tool"))
    }

    /// The middle segment has to appear in order, not merely be present.
    func testOrderedSegments() {
        XCTAssertTrue(GlobMatch.matches("a-mid-b", pattern: "a*mid*b"))
        XCTAssertFalse(GlobMatch.matches("a-b-mid", pattern: "a*mid*b"))
    }
}
