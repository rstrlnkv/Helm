import HelmTestSupport
import XCTest

/// **macOS has one interface face, and Helm is set in it.**
///
/// `Font.system(size:)` already *is* that face — SF Pro — so the question a
/// scan can usefully ask is not «is this the system font» but «is this the
/// system font macOS draws its own interface in». `design:` is where that stops
/// being true: `.rounded` is SF Rounded, which is watchOS's face and Apple's own
/// Mac interface uses nowhere, and `.monospaced` is SF Mono, which belongs to
/// code and paths rather than to a badge or a figure.
///
/// The scan reads source because there is nothing else to read: both spellings
/// compile, both draw, and the difference is only visible to somebody holding
/// the two windows side by side.
final class TheAppIsSetInTheSystemFacesTests: XCTestCase {

    /// SF Rounded had reached two of the app's most-repeated marks — every
    /// `HelmBadge` drawn prominently, and the value of every panel widget — so
    /// the two places a person's eye lands most often were the two set in a
    /// face macOS does not use for its interface anywhere.
    func testNothingIsSetInSFRounded() throws {
        var offences: [String] = []
        for path in try RepoSource.swiftFiles(under: "Sources") {
            for (index, line) in try RepoSource.lines(of: path).enumerated()
            where RepoSource.code(line).contains("design: .rounded") {
                offences.append("\(path):\(index + 1)")
            }
        }
        XCTAssertEqual(offences, [], """
            SF Rounded is watchOS's face; the Mac interface is SF Pro. A figure that must not \
            jump as it changes asks for `.monospacedDigit()`, which is tabular SF Pro, not for \
            another typeface
            """)
    }

    /// And the scan can fail: the spelling it hunts for is one the compiler
    /// accepts everywhere, so a scan that found nothing because the whole
    /// `design:` API had been renamed would look exactly like a clean tree.
    func testTheScanIsLookingForSomethingThatStillExists() throws {
        let anyDesign = try RepoSource.swiftFiles(under: "Sources").contains { path in
            try RepoSource.text(of: path).contains("design: .")
        }
        XCTAssertTrue(anyDesign, """
            no file in the app names `design:` at all any more, so the scan above would pass \
            whatever anybody wrote — check the API has not been renamed under it
            """)
    }
}
