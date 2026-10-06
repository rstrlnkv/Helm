import CoreGraphics
import HelmTestSupport
import XCTest
@testable import HelmApp

/// **`ShellGeometry` is the shell's arithmetic and nothing else: the card sits
/// 4 pt inside the window on three sides and takes its radius from the window's
/// own corner, the sidebar's width stays inside 150...320, and the capsule that
/// stands in for the window buttons in the rail has a closed frame, an open frame
/// and a hover zone that holds both while the buttons' minX is at least
/// `capsulePad.width`, their minY at least `capsulePad.height` and their midY at
/// least half of `capsuleSize.height`.**
///
/// No window, no screen, no view: every function under test takes numbers and
/// returns numbers. This class is deliberately not `@MainActor`, so a function
/// that were main-actor-isolated would not compile here; the geometry is read
/// from any thread.
///
/// What is an input and what is arithmetic. The window of 1060x760 is the
/// Settings window's default size (`defaultSize` in `SettingsWindow`), and the
/// sidebar of 200 is `defaultSidebarWidth`. The buttons' rect, x 19, y 19, 60
/// wide and 14 high, is an input that stands for where the system puts the three
/// window buttons: no test here reads it from a window, and the size of one
/// button (14) is an assumption these tests feed. The card frames (200, 4, 856,
/// 752) and (56, 4, 1000, 752) at the rail, and every other expectation derived
/// from those inputs, are arithmetic on them. 26 as a window radius is only a
/// value that is not 16.
///
/// `inset` is the owner's fixed gap; 56, 200, 150...320, 40x18, 9x6, 2 and 6 are
/// the owner's numbers too, tuned by eye on a running window. This file pins
/// them so that a change is deliberate, it does not prove they are right.
final class TheCardIsConcentricWithTheWindowTests: XCTestCase {

    // MARK: - inputs

    /// A window of the Settings window's default size.
    private static let window = CGSize(width: 1060, height: 760)

    /// The three window buttons' union, in the content's top-left coordinates:
    /// an input standing for where the system puts them (see the class comment):
    /// x 19...79, y 19...33, the 14-point button size an assumption.
    private static let buttons = CGRect(x: 19, y: 19, width: 60, height: 14)

    private static let nan = CGFloat.nan
    private static let inf = CGFloat.infinity
    private static let huge = CGFloat.greatestFiniteMagnitude

    /// Every kind of number a size, a width or a translation could arrive as.
    private static let awkward: [CGFloat] = [
        0, -1, -200, 1, 3.5, nan, inf, -inf, huge, -huge, .leastNonzeroMagnitude,
    ]

    private static func isFiniteRect(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.size.width.isFinite && rect.size.height.isFinite
    }

    // MARK: - the card

    func testTheCardSitsFourInsideAndFollowsTheWindowsCorner() {
        let fills = "the card fills the window: no 4 pt gap, so the backdrop never shows and the window reads as the toolbar plus a sidebar"

        let atSidebar = ShellGeometry.cardFrame(in: Self.window, sidebarWidth: 200)
        let atRail = ShellGeometry.cardFrame(in: Self.window, sidebarWidth: 56)

        // The subject happened: a card was produced, with room on three sides.
        XCTAssertGreaterThan(atSidebar.width, 0, "a card with no width proves nothing")
        XCTAssertGreaterThan(atRail.height, 0, "a card with no height proves nothing")
        XCTAssertGreaterThan(atSidebar.minY, 0, fills)
        XCTAssertLessThan(atSidebar.maxY, Self.window.height, fills)
        XCTAssertLessThan(atSidebar.maxX, Self.window.width, fills)

        XCTAssertEqual(atSidebar, CGRect(x: 200, y: 4, width: 856, height: 752), fills)
        XCTAssertEqual(atRail, CGRect(x: 56, y: 4, width: 1000, height: 752), fills)

        // Concentric: the radius is the window's less the 4 pt gap, from whatever
        // the window's corner is. 26 is only an input that is not 16, so a
        // function that returned a constant would be caught.
        XCTAssertEqual(ShellGeometry.cardRadius(windowRadius: 16), 12)
        XCTAssertEqual(ShellGeometry.cardRadius(windowRadius: 3), 0, "a corner smaller than the gap is square, not negative")
        XCTAssertEqual(ShellGeometry.cardRadius(windowRadius: 26), 22)
    }

    func testTheCardKeepsTheGapAtOtherWindowSizes() {
        // Not the default window size: the gap is arithmetic, not a snapshot.
        let sizes = [CGSize(width: 640, height: 480), CGSize(width: 1920, height: 1080),
                     CGSize(width: 500, height: 9), CGSize(width: 325, height: 100)]
        for size in sizes {
            for sidebar in [CGFloat(56), 150, 200, 320] {
                let card = ShellGeometry.cardFrame(in: size, sidebarWidth: sidebar)
                let label = "\(size) at \(sidebar): \(card)"
                XCTAssertEqual(card.minX, sidebar, label)
                XCTAssertEqual(card.minY, ShellGeometry.inset, label)
                XCTAssertEqual(size.width - card.maxX, ShellGeometry.inset, label)
                XCTAssertEqual(size.height - card.maxY, ShellGeometry.inset, label)
            }
        }
        // A 9 pt window leaves 1 pt for the card, not 0 and not 9.
        XCTAssertEqual(ShellGeometry.cardFrame(in: CGSize(width: 500, height: 9), sidebarWidth: 56).height, 1)
    }

    func testTheCardNeverHasANegativeOrNonFiniteSize() {
        var tried = 0
        for width in Self.awkward {
            for height in Self.awkward {
                for sidebar in Self.awkward {
                    let card = ShellGeometry.cardFrame(in: CGSize(width: width, height: height),
                                                       sidebarWidth: sidebar)
                    tried += 1
                    let label = "window \(width)x\(height), sidebar \(sidebar): \(card)"
                    XCTAssertTrue(card.size.width.isFinite && card.size.width >= 0, label)
                    XCTAssertTrue(card.size.height.isFinite && card.size.height >= 0, label)
                }
            }
        }
        XCTAssertEqual(tried, Self.awkward.count * Self.awkward.count * Self.awkward.count,
                       "every combination was fed in")
    }

    func testAWindowNarrowerThanTheSidebarGivesAZeroWidthCardNotANegativeOne() {
        // The sidebar alone is wider than the window.
        let narrow = ShellGeometry.cardFrame(in: CGSize(width: 150, height: 760), sidebarWidth: 200)
        XCTAssertEqual(narrow.width, 0)
        XCTAssertEqual(narrow.height, 752, "height is its own arithmetic: a narrow window is still 760 high")

        // Exactly the sidebar plus the gap: nothing left, still not negative.
        XCTAssertEqual(ShellGeometry.cardFrame(in: CGSize(width: 204, height: 760), sidebarWidth: 200).width, 0)
        XCTAssertEqual(ShellGeometry.cardFrame(in: CGSize(width: 205, height: 760), sidebarWidth: 200).width, 1)

        // Zero and negative windows.
        XCTAssertEqual(ShellGeometry.cardFrame(in: CGSize.zero, sidebarWidth: 200).size, CGSize.zero)
        XCTAssertEqual(ShellGeometry.cardFrame(in: CGSize(width: -10, height: -10), sidebarWidth: 200).size, CGSize.zero)

        // A window no taller than the two gaps: 7 is shorter, 8 is equal.
        XCTAssertEqual(ShellGeometry.cardFrame(in: CGSize(width: 1060, height: 7), sidebarWidth: 200).height, 0)
        XCTAssertEqual(ShellGeometry.cardFrame(in: CGSize(width: 1060, height: 8), sidebarWidth: 200).height, 0)
    }

    // MARK: - the radius

    func testTheCardRadiusTakesTheGapOffAndNeverGoesBelowZeroOrOutOfRange() {
        XCTAssertEqual(ShellGeometry.cardRadius(windowRadius: 4), 0)
        XCTAssertEqual(ShellGeometry.cardRadius(windowRadius: 5), 1)
        XCTAssertEqual(ShellGeometry.cardRadius(windowRadius: 0), 0)
        XCTAssertEqual(ShellGeometry.cardRadius(windowRadius: -8), 0)
        XCTAssertEqual(ShellGeometry.cardRadius(windowRadius: 100), 96)

        // Not a number and infinities read 0: a card with a NaN or infinite
        // corner is drawn square.
        XCTAssertEqual(ShellGeometry.cardRadius(windowRadius: Self.nan), 0)
        XCTAssertEqual(ShellGeometry.cardRadius(windowRadius: Self.inf), 0)
        XCTAssertEqual(ShellGeometry.cardRadius(windowRadius: -Self.inf), 0)

        // The largest finite radius stays finite and non-negative.
        let biggest = ShellGeometry.cardRadius(windowRadius: Self.huge)
        XCTAssertTrue(biggest.isFinite && biggest >= 0)
    }

    func testTheGeometryHoldsNoWindowRadiusOfItsOwnAndNoView() throws {
        let path = "Sources/HelmApp/ShellGeometry.swift"
        let code = SwiftSource.code(try RepoSource.text(of: path))

        // The subject happened: the file was read and it is the geometry.
        XCTAssertTrue(code.contains("enum ShellGeometry"), "\(path) did not read as the geometry")
        XCTAssertTrue(code.contains("cardRadius"), "\(path) has no radius function to look in")

        // The scan can fail: the same pattern finds a 16 where one is written.
        let sixteen = #"(?<![0-9.])16(?![0-9])"#
        XCTAssertNotNil("let r = 16".range(of: sixteen, options: .regularExpression),
                        "the scan's own pattern does not see a 16")
        XCTAssertNil("let r = 116.5".range(of: sixteen, options: .regularExpression))

        XCTAssertNil(code.range(of: sixteen, options: .regularExpression),
                     "\(path) writes the number 16: the window's corner is handed in, never held")

        // No view and no AppKit view type: the geometry is values only.
        for forbidden in ["import SwiftUI", "import AppKit", "NSView", "NSWindow", "some View"] {
            XCTAssertFalse(code.contains(forbidden), "\(path) mentions \(forbidden)")
        }

        // The sidebar's range goes through the shared clamp, not a hand-written one:
        // looked for inside the bodies of `sidebarWidth`, since `cardFrame` clamps
        // through it too and would keep a bare `clamped(` in the file green.
        let widthBodies = SwiftSource.bodiesNamed("sidebarWidth", in: code)
        XCTAssertEqual(widthBodies.count, 2, "\(path) no longer has the stored and the dragged `sidebarWidth`")
        XCTAssertTrue(widthBodies.contains { $0.contains("clamped(to: sidebarRange") },
                      "\(path): sidebarWidth(stored:) does not clamp through Clamped.swift")
    }

    // MARK: - the owner's numbers

    func testTheOwnersNumbersAreWhatTheyTunedByEye() {
        // `inset` is the owner's fixed gap; 56, 200, 150...320, 40x18, 9x6, 2 and 6
        // are the owner's too, tuned by eye; this pins them so that a change is a
        // decision.
        XCTAssertEqual(ShellGeometry.inset, 4)
        XCTAssertEqual(ShellGeometry.railWidth, 56)
        XCTAssertEqual(ShellGeometry.sidebarRange, 150...320)
        XCTAssertEqual(ShellGeometry.defaultSidebarWidth, 200)
        XCTAssertEqual(ShellGeometry.capsuleSize, CGSize(width: 40, height: 18))
        XCTAssertEqual(ShellGeometry.capsuleShift, 2)
        XCTAssertEqual(ShellGeometry.capsulePad, CGSize(width: 9, height: 6))
        XCTAssertEqual(ShellGeometry.hoverMargin, 6)
        XCTAssertTrue(ShellGeometry.sidebarRange.contains(ShellGeometry.defaultSidebarWidth))
    }

    // MARK: - the sidebar's width

    func testAStoredSidebarWidthIsBroughtInsideTheRange() {
        XCTAssertEqual(ShellGeometry.sidebarWidth(stored: 40), 150)
        XCTAssertEqual(ShellGeometry.sidebarWidth(stored: 4000), 320)
        XCTAssertEqual(ShellGeometry.sidebarWidth(stored: 0), 150)
        XCTAssertEqual(ShellGeometry.sidebarWidth(stored: -300), 150)
        XCTAssertEqual(ShellGeometry.sidebarWidth(stored: 150), 150)
        XCTAssertEqual(ShellGeometry.sidebarWidth(stored: 320), 320)
        XCTAssertEqual(ShellGeometry.sidebarWidth(stored: 200), 200)
        XCTAssertEqual(ShellGeometry.sidebarWidth(stored: 233.5), 233.5)
        // Just outside each end.
        XCTAssertEqual(ShellGeometry.sidebarWidth(stored: 149.5), 150)
        XCTAssertEqual(ShellGeometry.sidebarWidth(stored: 320.5), 320)

        // Not a number reads the default, which is not a bound.
        XCTAssertEqual(ShellGeometry.sidebarWidth(stored: Self.nan), ShellGeometry.defaultSidebarWidth)
        XCTAssertEqual(ShellGeometry.sidebarWidth(stored: Self.nan), 200)

        // Infinities and the extremes land inside the range, whichever end.
        for stored in [Self.inf, -Self.inf, Self.huge, -Self.huge, CGFloat.leastNonzeroMagnitude] {
            let width = ShellGeometry.sidebarWidth(stored: stored)
            XCTAssertTrue(ShellGeometry.sidebarRange.contains(width), "\(stored) read \(width)")
        }
    }

    func testADragNeverLeavesTheRange() {
        // Ordinary drags: origin plus translation.
        XCTAssertEqual(ShellGeometry.sidebarWidth(draggedFrom: 200, by: 30), 230)
        XCTAssertEqual(ShellGeometry.sidebarWidth(draggedFrom: 200, by: -30), 170)
        XCTAssertEqual(ShellGeometry.sidebarWidth(draggedFrom: 200, by: 0), 200)
        // Past each end it stops.
        XCTAssertEqual(ShellGeometry.sidebarWidth(draggedFrom: 200, by: 500), 320)
        XCTAssertEqual(ShellGeometry.sidebarWidth(draggedFrom: 200, by: -500), 150)
        XCTAssertEqual(ShellGeometry.sidebarWidth(draggedFrom: 300, by: 20), 320)
        XCTAssertEqual(ShellGeometry.sidebarWidth(draggedFrom: 300, by: 21), 320)
        XCTAssertEqual(ShellGeometry.sidebarWidth(draggedFrom: 160, by: -10), 150)

        // An origin already outside the range: the sum is clamped, the origin is
        // not clamped first (1000 - 700 is 300, not 320 - 700 clamped to 150).
        XCTAssertEqual(ShellGeometry.sidebarWidth(draggedFrom: 1000, by: -700), 300)
        XCTAssertEqual(ShellGeometry.sidebarWidth(draggedFrom: 1000, by: -10), 320)
        XCTAssertEqual(ShellGeometry.sidebarWidth(draggedFrom: 40, by: 5), 150)
        XCTAssertEqual(ShellGeometry.sidebarWidth(draggedFrom: 40, by: 200), 240)
        XCTAssertEqual(ShellGeometry.sidebarWidth(draggedFrom: -50, by: 250), 200)

        // Every awkward origin against every awkward translation stays inside.
        var tried = 0
        for origin in Self.awkward + [1000, 40] {
            for translation in Self.awkward + [-700, 5] {
                let width = ShellGeometry.sidebarWidth(draggedFrom: origin, by: translation)
                tried += 1
                XCTAssertTrue(ShellGeometry.sidebarRange.contains(width),
                              "from \(origin) by \(translation) gave \(width)")
            }
        }
        XCTAssertEqual(tried, (Self.awkward.count + 2) * (Self.awkward.count + 2))
    }

    // MARK: - the capsule

    func testTheClosedCapsuleSitsOnTheButtonsRow() {
        let closed = ShellGeometry.capsuleClosedFrame(buttons: Self.buttons)
        XCTAssertEqual(closed.size, CGSize(width: 40, height: 18))
        XCTAssertEqual(closed.minX, 10, "(56 - 40) / 2 + 2")
        XCTAssertEqual(closed.midY, Self.buttons.midY, "the row where the buttons are; there is no drop")
        XCTAssertEqual(closed, CGRect(x: 10, y: 17, width: 40, height: 18))

        // Follows the row, not a constant, and not the buttons' x.
        let lower = CGRect(x: 100, y: 40, width: 60, height: 20)
        let other = ShellGeometry.capsuleClosedFrame(buttons: lower)
        XCTAssertEqual(other.midY, 50)
        XCTAssertEqual(other.minX, 10, "the capsule's x belongs to the rail, not to the buttons")
        XCTAssertEqual(other.size, CGSize(width: 40, height: 18))
    }

    func testTheOpenCapsuleSurroundsTheButtonsWhereTheSystemPutThem() {
        let open = ShellGeometry.capsuleOpenFrame(buttons: Self.buttons)
        XCTAssertEqual(open, CGRect(x: 10, y: 13, width: 78, height: 26),
                       "the capsule opens at the rail's centre while the buttons stay at 19: the dots open onto nothing")
        XCTAssertEqual(open, Self.buttons.insetBy(dx: -9, dy: -6))
        XCTAssertTrue(open.contains(Self.buttons))

        // Follows the buttons wherever they are.
        let moved = CGRect(x: 30, y: 50, width: 61, height: 15)
        XCTAssertEqual(ShellGeometry.capsuleOpenFrame(buttons: moved), CGRect(x: 21, y: 44, width: 79, height: 27))
    }

    func testTheHoverZoneContainsBothFrames() {
        // For buttons whose minX is at least `capsulePad.width`, minY at least
        // `capsulePad.height` and midY at least half of `capsuleSize.height`; the
        // rects below keep to that; a rect that does not is pinned at the end of
        // this file, and `.zero` is asked only for finiteness.
        let zone = ShellGeometry.capsuleHoverZone(buttons: Self.buttons)
        let open = ShellGeometry.capsuleOpenFrame(buttons: Self.buttons)
        let closed = ShellGeometry.capsuleClosedFrame(buttons: Self.buttons)

        XCTAssertEqual(zone.origin, CGPoint.zero)
        XCTAssertEqual(zone.width, 94, "open.maxX 88 + 6")
        XCTAssertEqual(zone.height, 45, "open.maxY 39 + 6")
        XCTAssertTrue(zone.contains(open))
        XCTAssertTrue(zone.contains(closed))
        XCTAssertGreaterThan(zone.width, open.maxX, "the zone is wider than the drawing")
        XCTAssertGreaterThan(zone.height, open.maxY)

        // Buttons narrow enough that the open frame ends short of the rail: the
        // zone still covers the whole rail's width.
        let small = CGRect(x: 19, y: 19, width: 1, height: 1)
        let narrow = ShellGeometry.capsuleHoverZone(buttons: small)
        XCTAssertEqual(narrow.width, ShellGeometry.railWidth)
        XCTAssertTrue(narrow.contains(ShellGeometry.capsuleOpenFrame(buttons: small)))
        XCTAssertTrue(narrow.contains(ShellGeometry.capsuleClosedFrame(buttons: small)))

        // Buttons wide enough that the open frame passes the rail: the margin wins.
        let wide = CGRect(x: 19, y: 19, width: 100, height: 14)
        let broad = ShellGeometry.capsuleHoverZone(buttons: wide)
        XCTAssertEqual(broad.width, 19 + 100 + 9 + 6)
        XCTAssertTrue(broad.contains(ShellGeometry.capsuleOpenFrame(buttons: wide)))
    }

    func testAZeroSizeButtonsRectAtARealPlaceStillHasAZoneHoldingBothFrames() {
        // The size of the buttons is an input here, and 0x0 is the smallest one.
        let point = CGRect(x: 19, y: 19, width: 0, height: 0)
        let closed = ShellGeometry.capsuleClosedFrame(buttons: point)
        let open = ShellGeometry.capsuleOpenFrame(buttons: point)
        let zone = ShellGeometry.capsuleHoverZone(buttons: point)

        XCTAssertEqual(closed.size, ShellGeometry.capsuleSize, "the closed frame does not shrink with the buttons")
        XCTAssertEqual(open, CGRect(x: 10, y: 13, width: 18, height: 12))
        XCTAssertGreaterThan(open.width, 0, "the open frame has the padding even around nothing")
        XCTAssertTrue(zone.contains(closed))
        XCTAssertTrue(zone.contains(open))
        XCTAssertGreaterThanOrEqual(zone.width, ShellGeometry.railWidth)

        // At the origin the closed frame reaches above the content (y -9) and
        // the zone starts at 0; only finiteness and the sizes are asked here.
        let atOrigin = CGRect.zero
        XCTAssertEqual(ShellGeometry.capsuleClosedFrame(buttons: atOrigin).size, ShellGeometry.capsuleSize)
        XCTAssertEqual(ShellGeometry.capsuleOpenFrame(buttons: atOrigin).size, CGSize(width: 18, height: 12))
        XCTAssertTrue(Self.isFiniteRect(ShellGeometry.capsuleHoverZone(buttons: atOrigin)))
    }

    func testACapsuleOverANonFiniteButtonsRectStaysFinite() {
        // Rects with a NaN or infinite origin or size, a negative size, and the
        // `.null` and `.infinite` rects.
        let rects: [CGRect] = [
            CGRect(x: Self.nan, y: 19, width: 60, height: 14),
            CGRect(x: 19, y: Self.nan, width: 60, height: 14),
            CGRect(x: 19, y: 19, width: Self.nan, height: 14),
            CGRect(x: 19, y: 19, width: 60, height: Self.nan),
            CGRect(x: Self.inf, y: 19, width: 60, height: 14),
            CGRect(x: 19, y: -Self.inf, width: 60, height: 14),
            CGRect(x: 19, y: 19, width: Self.inf, height: 14),
            CGRect(x: 19, y: 19, width: -60, height: -14),
            .null, .infinite,
        ]
        for rect in rects {
            let label = "buttons \(rect)"
            XCTAssertTrue(Self.isFiniteRect(ShellGeometry.capsuleClosedFrame(buttons: rect)), "closed, \(label)")
            XCTAssertTrue(Self.isFiniteRect(ShellGeometry.capsuleOpenFrame(buttons: rect)), "open, \(label)")
            XCTAssertTrue(Self.isFiniteRect(ShellGeometry.capsuleHoverZone(buttons: rect)), "zone, \(label)")
        }
        XCTAssertEqual(rects.count, 10, "every shape was fed in")
    }

    // MARK: - what the card and the capsule read a bad input as

    func testASidebarWidthThatIsNotFiniteReadsZeroForXAndForTheWidthLostToIt() {
        let reference = ShellGeometry.cardFrame(in: Self.window, sidebarWidth: 0)
        XCTAssertEqual(reference, CGRect(x: 0, y: 4, width: 1056, height: 752), "the reference reading")
        for sidebar in [Self.nan, Self.inf, -Self.inf] {
            XCTAssertEqual(ShellGeometry.cardFrame(in: Self.window, sidebarWidth: sidebar), reference,
                           "sidebar \(sidebar)")
        }

        // A finite width is used as given: past the window's edge and below zero.
        let past = ShellGeometry.cardFrame(in: Self.window, sidebarWidth: 2000)
        XCTAssertEqual(past, CGRect(x: 2000, y: 4, width: 0, height: 752))
        let below = ShellGeometry.cardFrame(in: Self.window, sidebarWidth: -50)
        XCTAssertEqual(below, CGRect(x: -50, y: 4, width: 1106, height: 752))

        // Whatever came in, the origin is a number.
        var tried = 0
        for width in Self.awkward {
            for sidebar in Self.awkward {
                let card = ShellGeometry.cardFrame(in: CGSize(width: width, height: 760), sidebarWidth: sidebar)
                tried += 1
                XCTAssertTrue(card.origin.x.isFinite && card.origin.y.isFinite,
                              "window \(width), sidebar \(sidebar): \(card)")
            }
        }
        XCTAssertEqual(tried, Self.awkward.count * Self.awkward.count)
    }

    func testAButtonsRectThatIsNotAPlaceReadsAsTheEmptyRectAtTheCorner() {
        let atCorner = (closed: ShellGeometry.capsuleClosedFrame(buttons: .zero),
                        open: ShellGeometry.capsuleOpenFrame(buttons: .zero),
                        zone: ShellGeometry.capsuleHoverZone(buttons: .zero))
        // The reference is not the real buttons' answer: the check can tell them apart.
        XCTAssertNotEqual(atCorner.open, ShellGeometry.capsuleOpenFrame(buttons: Self.buttons))

        let rects: [CGRect] = [
            CGRect(x: Self.nan, y: 19, width: 60, height: 14),
            CGRect(x: 19, y: Self.nan, width: 60, height: 14),
            CGRect(x: 19, y: 19, width: Self.nan, height: 14),
            CGRect(x: 19, y: 19, width: 60, height: Self.nan),
            CGRect(x: Self.inf, y: 19, width: 60, height: 14),
            CGRect(x: 19, y: 19, width: Self.inf, height: 14),
            .null, .infinite,
            // A finite origin and a finite size whose far edge is not a number's:
            // each is finite alone and the edge overflows.
            CGRect(x: Self.huge, y: 19, width: Self.huge, height: 14),
            CGRect(x: 19, y: Self.huge, width: 60, height: Self.huge),
            CGRect(x: -Self.huge, y: 19, width: -Self.huge, height: 14),
        ]
        for rect in rects {
            XCTAssertEqual(ShellGeometry.capsuleClosedFrame(buttons: rect), atCorner.closed, "closed, \(rect)")
            XCTAssertEqual(ShellGeometry.capsuleOpenFrame(buttons: rect), atCorner.open, "open, \(rect)")
            XCTAssertEqual(ShellGeometry.capsuleHoverZone(buttons: rect), atCorner.zone, "zone, \(rect)")
        }
        XCTAssertEqual(rects.count, 11, "every shape was fed in")
    }

    func testAHugeButtonsRectThatStillHasAFiniteFarEdgeStaysFinite() {
        // Large and finite on every edge: none of the four may be read as the corner.
        let rects: [CGRect] = [
            CGRect(x: Self.huge, y: 19, width: 0, height: 14),
            CGRect(x: 19, y: Self.huge, width: 60, height: 0),
            CGRect(x: -Self.huge, y: -Self.huge, width: 0, height: 0),
            CGRect(x: 0, y: 0, width: Self.huge, height: Self.huge),
        ]
        for rect in rects {
            let label = "buttons \(rect)"
            XCTAssertTrue(Self.isFiniteRect(ShellGeometry.capsuleClosedFrame(buttons: rect)), "closed, \(label)")
            XCTAssertTrue(Self.isFiniteRect(ShellGeometry.capsuleOpenFrame(buttons: rect)), "open, \(label)")
            XCTAssertTrue(Self.isFiniteRect(ShellGeometry.capsuleHoverZone(buttons: rect)), "zone, \(label)")
        }
        // Not the corner: every one of the four reads as itself, not as the empty
        // rect at the corner (each is told apart from `.zero` by its open frame,
        // which follows the rect where it is).
        for rect in rects {
            XCTAssertNotEqual(ShellGeometry.capsuleOpenFrame(buttons: rect),
                              ShellGeometry.capsuleOpenFrame(buttons: .zero), "open, buttons \(rect)")
        }
    }

    func testAButtonsRectOfNegativeSizeIsStillGrownAndItsRowIsStillRead() {
        let negative = CGRect(x: 19, y: 19, width: -60, height: -14)
        let standard = negative.standardized
        XCTAssertEqual(standard, CGRect(x: -41, y: 5, width: 60, height: 14), "the rect the same area standardizes to")

        let closed = ShellGeometry.capsuleClosedFrame(buttons: negative)
        let open = ShellGeometry.capsuleOpenFrame(buttons: negative)
        let zone = ShellGeometry.capsuleHoverZone(buttons: negative)

        XCTAssertEqual(closed, CGRect(x: 10, y: 3, width: 40, height: 18), "the row is the area's middle, y 12")
        XCTAssertEqual(open.size, CGSize(width: 78, height: 26), "grown by the padding, not shrunk by the sign")
        XCTAssertTrue(open.contains(standard), "the open frame is around the area the buttons cover")
        XCTAssertEqual(open, CGRect(x: -50, y: -1, width: 78, height: 26), "grown from the standardized rect")
        XCTAssertTrue(zone.contains(closed))
        XCTAssertTrue(Self.isFiniteRect(zone))
        XCTAssertGreaterThanOrEqual(zone.width, ShellGeometry.railWidth)
        // Pinned as it is: the zone starts at the content's corner, so the part of
        // the open frame left of and above the corner is outside it.
        XCTAssertEqual(zone, CGRect(x: 0, y: 0, width: 56, height: 31))
    }
}
