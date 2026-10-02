import CoreGraphics
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// The inputs the first strip tests never fed: a Dock on a side edge with the
/// pointer on the display's very first column, displays left of and above the
/// primary one (negative CG origins, where the bottom-left to top-left flip is
/// easiest to get wrong), the menu bar of a non-primary display as this Mac
/// lists it, a strip's own edge, an owner name that is not the system's, and a
/// `visibleFrame` that is no inset at all.
final class TheDockStripHoldsOnEveryEdgeAndEveryDisplayTests: XCTestCase {
    override func setUp() { super.setUp(); ScreenshotsLog.begin() }
    override func tearDown() { ScreenshotsLog.end(); super.tearDown() }

    /// The primary display on the owner's Mac, as AppKit gives it.
    static let primaryHeight: CGFloat = 982

    private func dock(_ frame: CGRect) -> FrozenWindow {
        FrozenWindow(id: 20, frame: frame, layer: WindowPick.dockLevel, ownerName: "Dock")
    }

    // MARK: - Side edges

    /// A display to the left of the primary one, Dock on its left edge: the strip
    /// starts at the display's negative x and the pointer on column zero of that
    /// display is inside it.
    func testALeftDockOnADisplayLeftOfThePrimaryTakesItsFirstColumn() throws {
        let frame = CGRect(x: -1000, y: 0, width: 1000, height: 800)
        let visible = CGRect(x: -940, y: 0, width: 940, height: 770)
        let strip = try XCTUnwrap(DockStrip.rect(frame: frame, visible: visible, primaryHeight: Self.primaryHeight))
        XCTAssertEqual(strip, CGRect(x: -1000, y: Self.primaryHeight - 800, width: 60, height: 800))
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: -1000, y: 500), in: [dock(strip)])?.id, 20)
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: -940.5, y: 500), in: [dock(strip)])?.id, 20)
        XCTAssertNil(WindowPick.window(at: CGPoint(x: -940, y: 500), in: [dock(strip)]), "the strip ran past its own width")
    }

    /// A right Dock on the primary display: its last column is the Dock, its first is not.
    func testARightDockTakesTheLastColumnAndNotTheFirst() throws {
        let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visible = CGRect(x: 0, y: 0, width: 1450, height: 949)
        let strip = try XCTUnwrap(DockStrip.rect(frame: frame, visible: visible, primaryHeight: Self.primaryHeight))
        XCTAssertEqual(strip, CGRect(x: 1450, y: 0, width: 62, height: 982))
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: 1511.5, y: 500), in: [dock(strip)])?.id, 20)
        XCTAssertNil(WindowPick.window(at: CGPoint(x: 0, y: 500), in: [dock(strip)]))
    }

    /// The menu bar sits over a side Dock's strip at the top, and the list carries
    /// it in front, so the top of the strip is the menu bar.
    func testTheMenuBarWinsOverTheTopOfASideStrip() throws {
        let strip = try XCTUnwrap(DockStrip.rect(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                                 visible: CGRect(x: 60, y: 0, width: 1452, height: 949),
                                                 primaryHeight: Self.primaryHeight))
        let bar = FrozenWindow(id: 24, frame: CGRect(x: 0, y: 0, width: 1512, height: 33),
                               layer: WindowPick.menuBarLevel, ownerName: "Window Server")
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: 0, y: 10), in: [bar, dock(strip)])?.id, 24)
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: 0, y: 40), in: [bar, dock(strip)])?.id, 20)
    }

    // MARK: - Displays above and left: the flip

    /// Measured on this Mac: an external display at AppKit (-1793, 982) 2560x1440,
    /// above and left of the primary one. A bottom Dock there reserves its strip at
    /// the display's bottom, which in CG points is just above the primary display's
    /// top, at negative y — never at the external display's own top.
    func testABottomDockOnADisplayAboveAndLeftIsJustAboveThePrimary() throws {
        let frame = CGRect(x: -1793, y: 982, width: 2560, height: 1440)
        let visible = CGRect(x: -1793, y: 1052, width: 2560, height: 1340)
        let strip = try XCTUnwrap(DockStrip.rect(frame: frame, visible: visible, primaryHeight: Self.primaryHeight))
        XCTAssertEqual(strip, CGRect(x: -1793, y: -70, width: 2560, height: 70))
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: -1000, y: -1), in: [dock(strip)])?.id, 20)
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: -1000, y: -70), in: [dock(strip)])?.id, 20)
        XCTAssertNil(WindowPick.window(at: CGPoint(x: -1000, y: -71), in: [dock(strip)]))
        XCTAssertNil(WindowPick.window(at: CGPoint(x: -1000, y: -1420), in: [dock(strip)]), "the strip was flipped to the display's top")
        XCTAssertNil(WindowPick.window(at: CGPoint(x: 100, y: 10), in: [dock(strip)]), "the strip landed on the primary display")
    }

    /// The same display, Dock on its left edge: the strip spans the display's full
    /// height in CG points, from -1440 to 0.
    func testALeftDockOnADisplayAboveSpansItsOwnHeight() throws {
        let frame = CGRect(x: -1793, y: 982, width: 2560, height: 1440)
        let visible = CGRect(x: -1733, y: 982, width: 2500, height: 1410)
        let strip = try XCTUnwrap(DockStrip.rect(frame: frame, visible: visible, primaryHeight: Self.primaryHeight))
        XCTAssertEqual(strip, CGRect(x: -1793, y: -1440, width: 60, height: 1440))
    }

    // MARK: - The menu bar of another display

    /// This Mac lists a second menu bar, `Window Server` at layer 24, 2560x30 at
    /// CG (-1793, -1440). It is picked inside its own rect and nowhere below.
    func testTheMenuBarOfANonPrimaryDisplayIsPickedOnlyInItsRect() {
        let bar = FrozenWindow(id: 99478, frame: CGRect(x: -1793, y: -1440, width: 2560, height: 30),
                               layer: WindowPick.menuBarLevel, ownerName: "Window Server")
        let chrome = FrozenWindow(id: 126978, frame: CGRect(x: -1793, y: -1440, width: 1512, height: 1230),
                                  layer: 0, ownerName: "Google Chrome")
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: -1000, y: -1440), in: [bar, chrome])?.id, 99478)
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: -1000, y: -1411), in: [bar, chrome])?.id, 99478)
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: -1000, y: -1410), in: [bar, chrome])?.id, 126978)
    }

    /// Cut from the freeze, that menu bar comes from its own display's frame, at
    /// that display's scale, and is not refused for living at negative coordinates.
    func testTheMenuBarOfADisplayAboveAndLeftIsCutFromThatDisplay() async throws {
        let primary = FrozenDisplay(id: DisplayID(1), frame: CGRect(x: 0, y: 0, width: 100, height: 50),
                                    scale: 2, image: makeImage(width: 200, height: 100, green: 255))
        let above = FrozenDisplay(id: DisplayID(2), frame: CGRect(x: -200, y: -80, width: 200, height: 80),
                                  scale: 1, image: makeSplitImage(width: 200, height: 80))
        let freeze = Freeze(displays: [.image(primary), .image(above)],
                            windows: [FrozenWindow(id: 99478, frame: CGRect(x: -200, y: -80, width: 200, height: 6),
                                                   layer: WindowPick.menuBarLevel, ownerName: "Window Server"),
                                      FrozenWindow(id: 20, frame: CGRect(x: -200, y: -80, width: 12, height: 80),
                                                   layer: WindowPick.dockLevel, ownerName: "Dock")])
        let rig = Rig(home: scratchDirectory("shots-surface-above"))
        guard case .image(let bar) = await rig.session.window(99478, in: freeze) else { return XCTFail("the menu bar was refused") }
        XCTAssertEqual(bar.width, 200)
        XCTAssertEqual(bar.height, 6, "cut at scale 1 from the display above, not at the primary's 2x")
        guard case .image(let side) = await rig.session.window(20, in: freeze) else { return XCTFail("the side Dock was refused") }
        XCTAssertEqual(side.width, 12)
        XCTAssertEqual(side.height, 80)
        XCTAssertEqual(rig.capture.windowCalls, 0, "a system surface was asked for by id")
    }

    // MARK: - Owner names

    /// Read on this Mac with the interface in Russian: the owner of the layer-24
    /// windows is `Window Server`, not a translation. A menu bar whose owner came
    /// back empty or translated is not taken for an application window either: the
    /// pick falls through to what lies below.
    func testAMenuBarWhoseOwnerIsNotTheSystemsFallsThroughToWhatIsBelow() {
        let window = FrozenWindow(id: 101, frame: CGRect(x: 0, y: 0, width: 700, height: 500), layer: 0, ownerName: "Finder")
        for owner in ["", "Сервер окон"] {
            let bar = FrozenWindow(id: 24, frame: CGRect(x: 0, y: 0, width: 1512, height: 33),
                                   layer: WindowPick.menuBarLevel, ownerName: owner)
            XCTAssertNil(WindowPick.window(at: CGPoint(x: 1000, y: 10), in: [bar, window]), "owner \(owner.debugDescription)")
            XCTAssertEqual(WindowPick.window(at: CGPoint(x: 100, y: 10), in: [bar, window])?.id, 101, "owner \(owner.debugDescription)")
        }
    }

    // MARK: - Edges and garbage

    /// The strip's top edge belongs to the strip; half a point above it does not.
    func testTheStripsTopEdgeIsTheDocksAndHalfAPointAboveIsNot() throws {
        let strip = try XCTUnwrap(DockStrip.rect(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                                 visible: CGRect(x: 0, y: 74, width: 1512, height: 875),
                                                 primaryHeight: Self.primaryHeight))
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: 700, y: 908), in: [dock(strip)])?.id, 20)
        XCTAssertNil(WindowPick.window(at: CGPoint(x: 700, y: 907.5), in: [dock(strip)]))
    }

    /// A `visibleFrame` that reserves nothing anywhere — larger than the display,
    /// or holding a not-a-number or an infinity — is no strip at all, never a
    /// rect that swallows the display.
    func testAVisibleFrameThatIsNoInsetIsNoStrip() {
        let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let garbage: [CGRect] = [
            CGRect(x: -10, y: -10, width: 1532, height: 1002),
            CGRect(x: CGFloat.nan, y: CGFloat.nan, width: CGFloat.nan, height: CGFloat.nan),
            CGRect(x: CGFloat.nan, y: 74, width: 1512, height: 875).standardized,
            CGRect(x: -CGFloat.infinity, y: 0, width: CGFloat.infinity, height: 982),
            .null,
        ]
        for visible in garbage {
            let strip = DockStrip.rect(frame: frame, visible: visible, primaryHeight: Self.primaryHeight)
            XCTAssertFalse(strip.map { $0.width >= frame.width && $0.height >= frame.height } ?? false,
                           "visible \(visible) gave a strip the size of the display: \(String(describing: strip))")
            XCTAssertTrue(strip.map { $0.minX.isFinite && $0.minY.isFinite && $0.width.isFinite && $0.height.isFinite } ?? true,
                          "visible \(visible) gave a strip that is not finite: \(String(describing: strip))")
        }
    }
}
