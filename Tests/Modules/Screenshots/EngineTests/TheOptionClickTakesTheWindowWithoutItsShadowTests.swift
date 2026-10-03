import CoreGraphics
import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **A window comes with its shadow unless the click was an option-click.** The flag is the person's act at
/// the click, so it goes from `CaptureSession.window` to the port as it was given, and a window that is cut
/// from the freeze instead has no shadow of its own to leave out and still comes back as a picture.
final class TheOptionClickTakesTheWindowWithoutItsShadowTests: XCTestCase {

    private func freeze() -> Freeze {
        let frame = FrozenDisplay(id: DisplayID(1), frame: CGRect(x: 0, y: 0, width: 100, height: 50), scale: 2,
                                  image: makeImage(width: 200, height: 100, red: 255))
        return Freeze(displays: [.image(frame)],
                      windows: [FrozenWindow(id: 9, frame: CGRect(x: 0, y: 0, width: 50, height: 25), layer: 0)])
    }

    func testAPlainPickAsksForTheShadowAndAnOptionPickAsksForNone() async {
        let rig = Rig(home: scratchDirectory("shots-shadow-ask"))
        rig.capture.windows = [9: .image(makeImage(width: 4, height: 4))]
        _ = await rig.session.window(9, in: freeze())
        _ = await rig.session.window(9, in: freeze(), shadow: true)
        _ = await rig.session.window(9, in: freeze(), shadow: false)
        XCTAssertEqual(rig.capture.windowShadows, [true, true, false],
                       "the default is the shadow, as macOS's; the flag is passed on as it was given")
    }

    func testTheFlagDoesNotChangeWhichPictureIsReturnedByTheCutFromTheFreeze() async throws {
        let rig = Rig(home: scratchDirectory("shots-shadow-gone"))
        // The port has no such window any more (its default answer): the cut is from the freeze, with or without a shadow.
        for shadow in [true, false] {
            guard case .image(let image) = await rig.session.window(9, in: freeze(), shadow: shadow) else {
                return XCTFail("shadow \(shadow): the window was refused")
            }
            XCTAssertEqual(image.width, 100); XCTAssertEqual(image.height, 50)
        }
        XCTAssertEqual(rig.capture.windowShadows, [true, false], "the subject: the port was asked both times")
    }

    func testARefusedWindowIsRefusedWhateverTheFlagIs() async {
        let rig = Rig(home: scratchDirectory("shots-shadow-denied"))
        rig.capture.windows = [9: .denied]
        for shadow in [true, false] {
            guard case .refused(let why) = await rig.session.window(9, in: freeze(), shadow: shadow) else {
                return XCTFail("shadow \(shadow): a withdrawn grant gave a picture")
            }
            XCTAssertEqual(why, .noPermission)
        }
    }
}
