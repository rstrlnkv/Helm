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
        XCTAssertEqual(MenuBarIconStyle.allCases, [.squircle, .hexagon, .capsule])
    }

    /// The circle is gone and there is no nearest survivor to map to — the
    /// family changed, not the members. Every shape Helm has shipped lands on
    /// the square, which is the shape of its own icon and of every module
    /// plate, so the menu bar and the app agree.
    func testEveryShapeEverShippedLandsOnTheSquare() {
        for raw in ["ring", "doubleRing", "ringDot", "disc", "dot"] {
            XCTAssertEqual(MenuBarIconStyle(stored: raw), .squircle,
                           "\(raw) reads back as nothing this build can draw")
        }
    }

    func testTheThreeShapesReadBackAsThemselves() {
        for style in MenuBarIconStyle.allCases {
            XCTAssertEqual(MenuBarIconStyle(stored: style.rawValue), style)
        }
    }

    /// The control both halves need. Without it every assertion above passes
    /// on an initialiser that returns one constant.
    func testTheInitialiserIsNotAnsweringOneThingToEverything() {
        XCTAssertNotEqual(MenuBarIconSize(stored: "xxSmall"), MenuBarIconSize(stored: "small"))
        XCTAssertNotEqual(MenuBarIconStyle(stored: "hexagon"),
                          MenuBarIconStyle(stored: "capsule"))
    }

    /// Every size the app has ever written still reads back as something it
    /// can draw. The list is the shipped one, not `allCases` — the point is
    /// the values that are no longer cases.
    func testEverySizeEverShippedStillReadsBack() {
        for raw in ["xxxSmall", "xxSmall", "extraSmall", "small", "medium"] {
            XCTAssertTrue(MenuBarIconSize.allCases.contains(MenuBarIconSize(stored: raw)),
                          "\(raw) reads back as nothing this build can draw")
        }
    }
}
