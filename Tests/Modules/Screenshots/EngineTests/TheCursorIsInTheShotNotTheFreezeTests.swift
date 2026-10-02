import CoreGraphics
import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **The pointer is in the picture that is cut and never in the one the overlay
/// draws.** A freeze taken with the pointer in it would show two under the live
/// crosshair, so the freeze is taken twice — the overlay's frame without, the
/// cut's with — and only when the setting asks. `crop` and the full-screen shot
/// take the second when there is one.
final class TheCursorIsInTheShotNotTheFreezeTests: XCTestCase {

    private func freeze(withCursor: Bool) -> Freeze {
        let frame = FrozenDisplay(id: DisplayID(1), frame: CGRect(x: 0, y: 0, width: 100, height: 50), scale: 2,
                                  image: makeImage(width: 200, height: 100, red: 255),
                                  withCursor: withCursor ? makeImage(width: 200, height: 100, blue: 255) : nil)
        return Freeze(displays: [.image(frame)], windows: [FrozenWindow(id: 9, frame: CGRect(x: 0, y: 0, width: 50, height: 25), layer: 0)])
    }

    func testACropTakesTheFrameWithThePointerWhenThereIsOne() throws {
        let rig = Rig(home: scratchDirectory("shots-cursor-crop"))
        let cut = try XCTUnwrap(rig.session.crop(freeze(withCursor: true), display: DisplayID(1),
                                                 local: CGRect(x: 10, y: 10, width: 20, height: 10)))
        let (red, _, blue) = firstPixel(cut)
        // Colour-managed on the way to a pixel, so "blue" is about, not exactly, 0,0,255.
        XCTAssertGreaterThan(blue, 200, "the cut was taken from the frame without the pointer")
        XCTAssertLessThan(red, 60)
        XCTAssertEqual(cut.width, 40); XCTAssertEqual(cut.height, 20)
    }

    func testACropWithNoPointerFrameTakesTheFrame() throws {
        let rig = Rig(home: scratchDirectory("shots-cursor-crop-none"))
        let cut = try XCTUnwrap(rig.session.crop(freeze(withCursor: false), display: DisplayID(1),
                                                 local: CGRect(x: 10, y: 10, width: 20, height: 10)))
        XCTAssertGreaterThan(firstPixel(cut).0, 200)
    }

    func testAWindowCutFromTheFreezeAndTheWholeScreenTakeItToo() async throws {
        let rig = Rig(home: scratchDirectory("shots-cursor-window"))
        guard case .image(let window) = await rig.session.window(9, in: freeze(withCursor: true)) else {
            return XCTFail("the window was refused")
        }
        XCTAssertGreaterThan(firstPixel(window).2, 200, "a window cut from the freeze has no pointer")
        rig.capture.outcome = .frozen(freeze(withCursor: true))
        let delivery = await rig.session.captureScreens()
        XCTAssertGreaterThan(firstPixel(try XCTUnwrap(delivery.image)).2, 200, "the whole-screen shot has no pointer")
    }

    /// What the setting does to the port: asked for, and not asked for.
    func testTheSettingIsWhatThePortIsAskedFor() async throws {
        for showCursor in [false, true] {
            let rig = Rig(home: scratchDirectory("shots-cursor-ask"), settings: ScreenshotsSettings(showCursor: showCursor))
            rig.capture.outcome = .frozen(freeze(withCursor: showCursor))
            rig.capture.windows = [5: .image(makeImage(width: 4, height: 4))]
            _ = await rig.session.begin()
            _ = await rig.session.window(5, in: freeze(withCursor: false))
            XCTAssertEqual(rig.capture.freezeCursors, [showCursor], "the freeze was asked for the wrong frames")
            XCTAssertEqual(rig.capture.windowCursors, [showCursor], "the window was asked for the wrong pointer")
        }
    }
}
