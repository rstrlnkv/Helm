import CoreGraphics
import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **What colour space the real capture hands the JPEG encoder, and whether it
/// encodes.** `AJPEGIsMadeOfAnyPictureAPNGIsTests` shows the flattening refuses
/// an extended-range picture; this asks whether this Mac's displays and
/// windows ever produce one. Silent without `HELM_BENCH=1` (it reads the
/// screen), and with it set and no grant it fails rather than skipping. Nothing
/// is written and nothing is put on the clipboard.
final class ScreenshotsLiveJPEGBenchmark: XCTestCase {

    func testEveryLiveFrameAndAWindowBecomeAJPEG() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        let capture = SCKCapture(store: NamespacedStoreForTests.make())
        // Ended here without the grant, so the read below cannot raise the system's prompt.
        guard capture.access() == .granted else {
            return XCTFail("HELM_BENCH is set and this process cannot read the screen")
        }
        guard case .frozen(let freeze) = await capture.freeze(cursor: true) else { return XCTFail("no freeze") }
        XCTAssertFalse(freeze.frames.isEmpty, "no display came back, so nothing was encoded")
        for frame in freeze.frames {
            for (what, image) in [("frame", frame.image), ("shot", frame.shot)] {
                let space = image.colorSpace.flatMap { $0.name as String? } ?? "\(String(describing: image.colorSpace))"
                print("display \(frame.id.raw) \(what): \(space), \(image.bitsPerComponent) bpc, info \(image.bitmapInfo.rawValue)")
                XCTAssertNotNil(CaptureSession.encode(image, as: .jpeg), "display \(frame.id.raw) \(what) (\(space)) is no JPEG")
            }
        }
        let window = try XCTUnwrap(freeze.windows.first(where: { $0.layer == 0 && $0.frame.width > 100 }),
                                   "no ordinary window on screen, so no window was encoded")
        guard case .image(let image) = await capture.window(window.id, cursor: false) else { return XCTFail("no window picture") }
        let space = image.colorSpace.flatMap { $0.name as String? } ?? "\(String(describing: image.colorSpace))"
        print("window: \(space), \(image.bitsPerComponent) bpc, info \(image.bitmapInfo.rawValue)")
        XCTAssertNotNil(CaptureSession.encode(image, as: .jpeg), "the window (\(space)) is no JPEG")
    }
}
