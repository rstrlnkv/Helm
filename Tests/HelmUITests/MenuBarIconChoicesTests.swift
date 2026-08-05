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

    func testThreeSizes() {
        XCTAssertEqual(MenuBarIconSize.allCases.map(\.label), ["S", "M", "L"])
        XCTAssertEqual(MenuBarIconSize.allCases.map(\.points), [11, 13, 15])
    }

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
    func testSomethingUnrecognisedFallsBack() {
        XCTAssertEqual(MenuBarIconSize(stored: "enormous"), .extraSmall)
        XCTAssertEqual(MenuBarIconSize(stored: ""), .extraSmall)
    }

    // MARK: - Shapes

    func testThreeShapes() {
        XCTAssertEqual(MenuBarIconStyle.allCases, [.ring, .doubleRing, .ringDot])
    }

    /// `disc` and `dot` had no outer ring, and the ring is what the countdown
    /// and the spinner replace — so on those two the timer setting sat beside
    /// them on the page and meant nothing.
    func testTheTwoDroppedShapesBecomeTheRing() {
        XCTAssertEqual(MenuBarIconStyle(stored: "disc"), .ring)
        XCTAssertEqual(MenuBarIconStyle(stored: "dot"), .ring)
    }

    func testTheThreeShapesThatStayedAreUnchanged() {
        for style in MenuBarIconStyle.allCases {
            XCTAssertEqual(MenuBarIconStyle(stored: style.rawValue), style)
        }
    }

    /// The control both halves need. Without it every assertion above passes
    /// on an initialiser that returns one constant.
    func testTheInitialiserIsNotAnsweringOneThingToEverything() {
        XCTAssertNotEqual(MenuBarIconSize(stored: "xxSmall"), MenuBarIconSize(stored: "small"))
        XCTAssertNotEqual(MenuBarIconStyle(stored: "doubleRing"),
                          MenuBarIconStyle(stored: "ringDot"))
    }

    /// Every raw value the app has ever written still reads back as something.
    /// The list is the shipped one, not `allCases` — the point is the values
    /// that are no longer cases.
    func testEveryValueEverShippedStillReadsBack() {
        let everShipped = ["xxxSmall", "xxSmall", "extraSmall", "small", "medium"]
        for raw in everShipped {
            XCTAssertTrue(MenuBarIconSize.allCases.contains(MenuBarIconSize(stored: raw)),
                          "\(raw) reads back as nothing this build can draw")
        }
        for raw in ["ring", "doubleRing", "ringDot", "disc", "dot"] {
            XCTAssertTrue(MenuBarIconStyle.allCases.contains(MenuBarIconStyle(stored: raw)))
        }
    }
}
