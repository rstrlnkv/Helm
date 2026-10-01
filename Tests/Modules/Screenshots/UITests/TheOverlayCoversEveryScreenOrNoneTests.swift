import AppKit
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The overlay covers every screen there is, or it is not built.**
///
/// `CaptureOverlay.build` asks one direction only: that every display in the
/// freeze still has a screen. The other direction — that every screen has a
/// display in the freeze — is what a display plugged in during the freeze
/// breaks, and so does a display the freeze lists as `.gone` while it is still
/// there (`SCKCapture` files every capture error that is not a refused grant as
/// `.gone`). Either way the overlay dims some screens and leaves the rest live,
/// and the screen-change observer that would cancel it is registered only after
/// the change it needed to see.
///
/// Built and never ordered in, as in `TheOverlayDecidesWhatTheDragMeansTests`:
/// nothing appears on the screens of whoever runs this. It needs a Mac with two
/// screens or more and says so when it has fewer.
@MainActor
final class TheOverlayCoversEveryScreenOrNoneTests: XCTestCase {

    private var overlay: CaptureOverlay?

    override func tearDown() {
        overlay?.close()
        overlay = nil
        super.tearDown()
    }

    private func number(_ screen: NSScreen) throws -> UInt32 {
        try XCTUnwrap(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32)
    }

    private func frame(of screen: NSScreen) throws -> FrozenDisplay {
        let scale = screen.backingScaleFactor
        let size = screen.frame.size
        let context = try XCTUnwrap(CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                              bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return FrozenDisplay(id: DisplayID(try number(screen)), frame: CGRect(origin: .zero, size: size),
                             scale: scale, image: try XCTUnwrap(context.makeImage()))
    }

    private func screens() throws -> [NSScreen] {
        let screens = NSScreen.screens
        guard screens.count >= 2 else {
            throw XCTSkip("one screen: a freeze that misses a screen cannot be staged on this Mac")
        }
        return screens
    }

    /// The control: a freeze of every screen builds.
    func testAFreezeOfEveryScreenBuilds() throws {
        let frames = try screens().map { try frame(of: $0) }
        let overlay = CaptureOverlay(freeze: Freeze(displays: frames.map { .image($0) }, windows: [])) { _ in }
        self.overlay = overlay
        XCTAssertTrue(overlay.build(), "a freeze of every screen there is was refused")
    }

    /// A screen that arrived after the freeze: the freeze has the others only.
    func testAScreenTheFreezeNeverSawIsNotLeftLive() throws {
        let screens = try screens()
        let known = try frame(of: screens[0])
        let overlay = CaptureOverlay(freeze: Freeze(displays: [.image(known)], windows: [])) { _ in }
        self.overlay = overlay
        XCTAssertFalse(overlay.build(),
                       "the overlay was built over 1 of \(screens.count) screens; the rest stay live under a capture")
    }

    /// A screen the freeze lists as gone while it is still on the desk.
    func testAScreenTheFreezeCalledGoneIsNotLeftLive() throws {
        let screens = try screens()
        let known = try frame(of: screens[0])
        let others = try screens.dropFirst().map { DisplayShot.gone(DisplayID(try number($0))) }
        let overlay = CaptureOverlay(freeze: Freeze(displays: [.image(known)] + others, windows: [])) { _ in }
        self.overlay = overlay
        XCTAssertFalse(overlay.build(),
                       "the overlay was built over 1 of \(screens.count) screens while the others were called gone")
    }
}
