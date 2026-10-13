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

/// A tag with nothing in it to read as a version.
///
/// The response is not trusted, so `v`, `V`, `-` and the empty string can reach
/// `UpdateVersion` in a tag name. The parser reads them as `[]`, which compares
/// as a final 0.0.0, and does not stop the process. What a row holds is that
/// such a tag is not newer than `0.0.0`, `1.0.0` or `0.7.2-dev.34`.
///
/// One method per tag, in a class of their own and nowhere else: a trap ends
/// the whole test process, so a filter that selects this class alone is how
/// the outcome is read, and `ATagWithNoVersionInItTests/testLowercaseV` is how
/// one tag is.
final class ATagWithNoVersionInItTests: XCTestCase {
    private func check(_ tag: String, file: StaticString = #filePath, line: UInt = #line) {
        let parsed = UpdateVersion.parse(tag)
        XCTAssertTrue(parsed.allSatisfy { $0 == 0 },
                      "\(tag.debugDescription) parsed as \(parsed)", file: file, line: line)
        for current in ["0.0.0", "1.0.0", "0.7.2-dev.34"] {
            XCTAssertFalse(UpdateVersion.isNewer(tag, than: current),
                           "\(tag.debugDescription) is newer than \(current)", file: file, line: line)
        }
    }

    func testLowercaseV() { check("v") }
    func testUppercaseV() { check("V") }
    func testDash() { check("-") }
    func testEmpty() { check("") }
}
