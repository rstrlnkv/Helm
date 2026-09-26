import XCTest
import HelmTestSupport
@testable import HelmUI

/// **An unknown or absent stored label style reads as words, the mockup's own
/// recommendation** (`ToolbarSwitcherStyle.init(stored:)`), and a known one
/// reads as itself.
@MainActor
final class AnUnknownStoredSwitcherStyleReadsAsWordsTests: XCTestCase {

    func testAnUnknownStoredStyleIsWords() {
        XCTAssertEqual(ToolbarSwitcherStyle(stored: ""), .text)
        XCTAssertEqual(ToolbarSwitcherStyle(stored: "nonsense"), .text)
        XCTAssertEqual(ToolbarSwitcherStyle(stored: "icons"), .icons)
    }
}
