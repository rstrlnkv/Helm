import CoreGraphics
import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **The window list in a freeze is a reading, and the click is an act.** It is
/// asked again at the click; if the window has gone since, what was on screen at
/// the freeze is cut from the freeze — which is what the person was looking at
/// when they clicked.
final class AWindowClosedAfterTheFreezeIsCutFromTheFreezeTests: XCTestCase {
    override func setUp() { super.setUp(); ScreenshotsLog.begin() }
    override func tearDown() { ScreenshotsLog.end(); super.tearDown() }

    /// One display, 100×50 points at 2×, left half red and right half blue, and
    /// a window over the right half.
    private func freeze() -> Freeze {
        let frame = FrozenDisplay(id: DisplayID(1), frame: CGRect(x: 0, y: 0, width: 100, height: 50),
                                  scale: 2, image: makeSplitImage(width: 200, height: 100))
        return Freeze(displays: [.image(frame)],
                      windows: [FrozenWindow(id: 77, frame: CGRect(x: 60, y: 10, width: 30, height: 20), layer: 0)])
    }

    func testAClosedWindowIsCutFromTheFrozenFrame() async throws {
        let rig = Rig(home: scratchDirectory("shots-window-closed"))
        rig.capture.windows = [77: .gone]

        let result = await rig.session.window(77, in: freeze())

        guard case .image(let image) = result else { return XCTFail("a window that closed was refused: \(result)") }
        XCTAssertEqual(rig.capture.windowCalls, 1, "the window was not asked for again at the click")
        XCTAssertEqual(image.width, 60, "the cut is the window's size in pixels")
        XCTAssertEqual(image.height, 40)
        let pixel = firstPixel(image)
        XCTAssertGreaterThan(pixel.2, 200, "the cut came from the wrong place: it is not the blue half")
        XCTAssertLessThan(pixel.0, 40, "the red half leaked in")
    }

    func testAWindowThatIsStillThereIsTheSystemsOwnPicture() async throws {
        let rig = Rig(home: scratchDirectory("shots-window-there"))
        rig.capture.windows = [77: .image(makeImage(width: 61, height: 41, green: 255))]

        guard case .image(let image) = await rig.session.window(77, in: freeze()) else { return XCTFail("refused") }

        XCTAssertEqual(image.width, 61, "the freeze was cut when the window could still be asked for")
    }

    func testAWindowNeitherKnowsIsRefusedAndSaid() async throws {
        ScreenshotsLog.proveTheLogIsOn()
        let rig = Rig(home: scratchDirectory("shots-window-unknown"))
        rig.capture.windows = [:]

        guard case .refused(let reason) = await rig.session.window(99, in: freeze()) else { return XCTFail("a window nobody knows produced a picture") }

        XCTAssertEqual(reason, .windowGone)
        XCTAssertTrue(ScreenshotsLog.lines.contains { $0.contains("gone") }, "\(ScreenshotsLog.lines)")
    }

    func testAWithdrawnGrantEndsTheCaptureAndIsNotCutFromTheFreeze() async throws {
        let rig = Rig(home: scratchDirectory("shots-window-denied"))
        rig.capture.windows = [77: .denied]

        guard case .refused(let reason) = await rig.session.window(77, in: freeze()) else { return XCTFail("a denied window produced a picture") }
        XCTAssertEqual(reason, .noPermission)
    }

    func testAWindowThatCouldNotBeReadIsCutFromTheFreezeAndSaid() async throws {
        ScreenshotsLog.proveTheLogIsOn()
        let rig = Rig(home: scratchDirectory("shots-window-failed"))
        rig.capture.windows = [77: .failed]

        guard case .image = await rig.session.window(77, in: freeze()) else { return XCTFail("refused") }
        XCTAssertTrue(ScreenshotsLog.lines.contains { $0.contains("frozen frame") }, "\(ScreenshotsLog.lines)")
    }
}
