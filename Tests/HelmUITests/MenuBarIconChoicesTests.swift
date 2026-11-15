import XCTest
@testable import HelmUI

/// Five sizes became three and five shapes became three, and nobody's icon
/// changes to something they did not choose.
///
/// A dropped case is not a compile error at the *storage* boundary: the raw
/// string is still on disk, `init(rawValue:)` answers nil, and every call site
/// had a `?? default` waiting to swallow it. Somebody who had picked the
/// smallest icon would have been handed the middle one, and the app would
/// have looked like it had forgotten.
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
    /// wears. It answered `.extraSmall` while `AppSettings` supplied `"small"`
    /// separately — 13 pt and «M» against 15 pt and «L» — and the disagreement
    /// was reachable the moment anybody dropped the literal for this fallback.
    func testSomethingUnrecognisedFallsBackToTheShippedDefault() {
        XCTAssertEqual(MenuBarIconSize(stored: "enormous"), .small)
        XCTAssertEqual(MenuBarIconSize(stored: ""), .small)
        XCTAssertEqual(MenuBarIconSize(stored: "").points, 15)
        XCTAssertEqual(MenuBarIconSize(stored: "").label, "L")
    }

    // MARK: - Shapes

    /// The three circles stayed; only `disc` and `dot` went, and they go to
    /// the ring rather than to whatever the default happens to be that day.
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
