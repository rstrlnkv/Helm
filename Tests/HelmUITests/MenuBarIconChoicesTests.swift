import XCTest
@testable import HelmUI

/// A stored size or shape this build does not offer reads back as the nearest
/// it does, so nobody's icon changes to something they did not choose. A
/// dropped case is not a compile error at the storage boundary: the raw string
/// is still on disk and `init(rawValue:)` answers nil.
final class MenuBarIconChoicesTests: XCTestCase {

    // MARK: - Sizes

    /// Mapped to the nearest survivor, not to the default. Somebody who chose
    /// the smallest icon wanted a small icon.
    func testTheTwoDroppedSizesLandOnTheirNeighbour() {
        XCTAssertEqual(MenuBarIconSize(stored: "xxxSmall"), .xxSmall,   // 9 → 11
                       "the smallest choice became the middle one")
        XCTAssertEqual(MenuBarIconSize(stored: "medium"), .small)       // 18 → 15
    }

    func testTheThreeThatStayedAreUnchanged() {
        for size in MenuBarIconSize.allCases {
            XCTAssertEqual(MenuBarIconSize(stored: size.rawValue), size)
        }
    }

    /// A value from a build that has not been written yet — what a downgrade
    /// looks like — is the one case where falling back is right.
    ///
    /// **And this is where the shipped default lives**, which is why the empty
    /// string is asserted beside the nonsense one: `AppSettings.menuBarIconSize`
    /// passes `""` for «never chosen», so this fallback is what a fresh install
    /// wears, `.small`, 15 pt, «L».
    func testSomethingUnrecognisedFallsBackToTheShippedDefault() {
        XCTAssertEqual(MenuBarIconSize(stored: "enormous"), .small)
        XCTAssertEqual(MenuBarIconSize(stored: ""), .small)
        XCTAssertEqual(MenuBarIconSize(stored: "").points, 15)
        XCTAssertEqual(MenuBarIconSize(stored: "").label, "L")
    }

    // MARK: - Shapes

    /// `disc` and `dot` go to the ring rather than to whatever the default is.
    func testTheTwoDroppedShapesBecomeTheRing() {
        XCTAssertEqual(MenuBarIconStyle(stored: "disc"), .ring)
        XCTAssertEqual(MenuBarIconStyle(stored: "dot"), .ring)
    }

    func testEveryShapeReadsBackAsItself() {
        for style in MenuBarIconStyle.allCases {
            XCTAssertEqual(MenuBarIconStyle(stored: style.rawValue), style)
        }
    }
}
