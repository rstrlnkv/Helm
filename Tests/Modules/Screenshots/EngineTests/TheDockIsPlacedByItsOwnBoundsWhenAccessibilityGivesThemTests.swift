import CoreGraphics
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// The Dock through Accessibility, the way macOS's own Screenshot finds it. Measured on
/// the owner's Mac (1512x982 points, Dock at the bottom, not hidden): the Dock process's
/// AXList is 216,904 1080x68; the strip `visibleFrame` gives up is 0,908 1512x74; the
/// system's own picture of the Dock window (`screencapture -l<id>`, and ScreenCaptureKit's
/// window capture, identical) is 2260x214 px with alpha and the shadow. Four states:
/// bounds on a display, no element, bounds off every display, not trusted.
final class TheDockIsPlacedByItsOwnBoundsWhenAccessibilityGivesThemTests: XCTestCase {
    override func setUp() { super.setUp(); ScreenshotsLog.begin() }
    override func tearDown() { ScreenshotsLog.end(); super.tearDown() }

    static let strip = CGRect(x: 0, y: 908, width: 1512, height: 74)
    static let list = CGRect(x: 216, y: 904, width: 1080, height: 68)
    static let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
    static let sheet = CGRect(x: 0, y: 0, width: 1512, height: 982)

    /// Helm's own window and a stranger's come first, the Dock's own window is third:
    /// the pid asked about must be the Dock's and no other.
    static var raw: [RawWindow] { [RawWindow(number: 5, layer: 0, ownerPID: 999, ownerName: "Helm", frame: CGRect(x: 0, y: 0, width: 50, height: 50)),
                      RawWindow(number: 24, layer: 24, ownerPID: 1, ownerName: "Window Server", frame: CGRect(x: 0, y: 0, width: 1512, height: 37)),
                      RawWindow(number: 20, layer: 20, ownerPID: 70, ownerName: "Dock", frame: sheet, ownedByDock: true),
                      RawWindow(number: 101, layer: 0, ownerPID: 300, ownerName: "Finder",
                                frame: CGRect(x: 100, y: 80, width: 700, height: 500))] }

    private func listed(_ fake: FakeDockBounds, strip: CGRect? = TheDockIsPlacedByItsOwnBoundsWhenAccessibilityGivesThemTests.strip,
                        displays: [CGRect] = [display]) -> [FrozenWindow] {
        let placement = DockStrip.placement(entries: Self.raw, ports: fake, displays: displays, strip: strip)
        let raw = Self.raw
        return WindowListing.visible(raw, excluding: 999, dock: placement)
    }

    private func freeze(_ windows: [FrozenWindow]) -> Freeze {
        let frame = FrozenDisplay(id: DisplayID(1), frame: Self.display, scale: 1,
                                  image: makeImage(width: 1512, height: 982, red: 255))
        return Freeze(displays: [.image(frame)], windows: windows)
    }

    // MARK: - Trusted, with bounds on a display

    func testTheBoundsArePickedAndNotTheStrip() {
        let windows = listed(FakeDockBounds(.bounds(Self.list)))
        let dock = windows.first { $0.id == 20 }
        XCTAssertEqual(dock?.frame, Self.list)
        XCTAssertEqual(dock?.drawnAlone, true)
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: 700, y: 940), in: windows)?.id, 20)
        // On the strip and outside the Dock's own bounds: the desktop, not the Dock.
        XCTAssertNil(WindowPick.window(at: CGPoint(x: 50, y: 940), in: windows), "the strip was picked beside the Dock")
        XCTAssertNil(WindowPick.window(at: CGPoint(x: 700, y: 980), in: windows))
    }

    func testThePictureIsTheSystemsWindowCaptureOfTheDockAndNotACut() async throws {
        let windows = listed(FakeDockBounds(.bounds(Self.list)))
        let rig = Rig(home: scratchDirectory("shots-dock-ax"))
        rig.capture.windows = [20: .image(makeImage(width: 2260, height: 214, green: 255))]
        guard case .image(let picture) = await rig.session.window(20, in: freeze(windows)) else { return XCTFail("refused") }
        XCTAssertEqual(rig.capture.windowCalls, 1, "the Dock was cut from the freeze")
        XCTAssertEqual(picture.width, 2260)
        XCTAssertEqual(picture.height, 214)
    }

    func testAWindowCaptureThatFailsFallsBackToACutAtTheBounds() async throws {
        let windows = listed(FakeDockBounds(.bounds(Self.list)))
        let rig = Rig(home: scratchDirectory("shots-dock-ax-gone"))
        rig.capture.windows = [20: .gone]
        guard case .image(let picture) = await rig.session.window(20, in: freeze(windows)) else { return XCTFail("refused") }
        XCTAssertEqual(picture.width, 1080)
        XCTAssertEqual(picture.height, 68)
    }

    func testBoundsOnASecondDisplayCountAsOnADisplay() {
        let second = CGRect(x: 1512, y: -300, width: 1920, height: 1080)
        let rect = CGRect(x: 2100, y: 700, width: 800, height: 70)
        XCTAssertEqual(DockStrip.placement(.bounds(rect), displays: [Self.display, second], strip: nil)?.rect, rect)
    }

    // MARK: - Trusted, no element / not trusted: the strip

    func testNoElementIsTheStripAndACut() async throws {
        let fake = FakeDockBounds(.noElement)
        let windows = listed(fake)
        XCTAssertEqual(windows.first { $0.id == 20 }?.frame, Self.strip)
        XCTAssertEqual(windows.first { $0.id == 20 }?.drawnAlone, false)
        let rig = Rig(home: scratchDirectory("shots-dock-noel"))
        rig.capture.windows = [20: .image(makeImage(width: 5, height: 5, green: 255))]
        guard case .image(let picture) = await rig.session.window(20, in: freeze(windows)) else { return XCTFail("refused") }
        XCTAssertEqual(rig.capture.windowCalls, 0)
        XCTAssertEqual(picture.height, 74)
    }

    func testNotTrustedIsTheStripAndACut() async throws {
        let windows = listed(FakeDockBounds(.notTrusted))
        XCTAssertEqual(windows.first { $0.id == 20 }?.frame, Self.strip)
        XCTAssertEqual(windows.first { $0.id == 20 }?.drawnAlone, false)
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: 50, y: 940), in: windows)?.id, 20)
    }

    func testNoAccessibilityAndNoStripIsNoDock() {
        for reading in [DockBoundsReading.notTrusted, .noElement] {
            let windows = listed(FakeDockBounds(reading), strip: nil)
            XCTAssertEqual(windows.map(\.id), [24, 101])
        }
    }

    // MARK: - Trusted, bounds off every display: a Dock that is hidden

    /// An auto-hiding Dock that is hidden reports its list off the display; not
    /// measured here (it needs the owner's Dock setting changed) — the state is
    /// represented and must not be pickable, and must not fall back to a strip.
    func testBoundsOffEveryDisplayAreNoDockAndNotTheStrip() {
        for rect in [CGRect(x: 216, y: 982, width: 1080, height: 68),
                     CGRect(x: 216, y: 975, width: 1080, height: 68),
                     CGRect(x: -2000, y: 904, width: 1080, height: 68)] {
            let windows = listed(FakeDockBounds(.bounds(rect)))
            XCTAssertEqual(windows.map(\.id), [24, 101], "a hidden Dock was listed at \(rect)")
            XCTAssertNil(WindowPick.window(at: CGPoint(x: 700, y: 978), in: windows))
        }
    }

    func testAShownAutoHideDockIsPickableWhereverItIsDrawn() {
        // Autohide shown: no strip is reserved, the bounds are on the display.
        let windows = listed(FakeDockBounds(.bounds(Self.list)), strip: nil)
        XCTAssertEqual(windows.first { $0.id == 20 }?.frame, Self.list)
    }

    func testBoundsTooSmallOrNotANumberAreNotARectangle() {
        for rect in [CGRect(x: 216, y: 904, width: 3, height: 68), CGRect(x: CGFloat.nan, y: 904, width: 1080, height: 68)] {
            let placement = DockStrip.placement(.bounds(rect), displays: [Self.display], strip: Self.strip)
            XCTAssertEqual(placement, DockPlacement(rect: Self.strip, drawnAlone: false))
        }
    }

    func testThePortIsAskedAboutTheDocksProcess() {
        let fake = FakeDockBounds(.notTrusted)
        _ = listed(fake)
        XCTAssertEqual(fake.asked, [70])
    }

    func testNoDockWindowMeansNoQuestionAndNoPlacement() {
        let fake = FakeDockBounds(.bounds(Self.list))
        let withoutDock = Self.raw.filter { !$0.ownedByDock }
        XCTAssertNil(DockStrip.placement(entries: withoutDock, ports: fake, displays: [Self.display], strip: Self.strip))
        XCTAssertEqual(fake.asked, [])
    }

    /// A Dock that did not answer is the strip, and it is the one reading that says so.
    func testADockThatDidNotAnswerIsTheStripAndIsReported() {
        let fake = FakeDockBounds(.timedOut)
        var reported = 0
        let placement = DockStrip.placement(entries: Self.raw, ports: fake, displays: [Self.display], strip: Self.strip) { reported += 1 }
        XCTAssertEqual(placement, DockPlacement(rect: Self.strip, drawnAlone: false))
        XCTAssertEqual(reported, 1)
        for quiet in [DockBoundsReading.noElement, .notTrusted, .bounds(Self.list)] {
            DockStrip.placement(entries: Self.raw, ports: FakeDockBounds(quiet), displays: [Self.display], strip: Self.strip) { reported += 1 }
        }
        XCTAssertEqual(reported, 1, "an absence was reported as a refusal")
    }
}
