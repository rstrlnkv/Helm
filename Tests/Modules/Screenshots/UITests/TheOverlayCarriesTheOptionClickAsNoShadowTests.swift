import AppKit
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The overlay says what the click was: a window with its shadow, or, under ⌥, without.** The engine half
/// (what the port is asked) is `TheOptionClickTakesTheWindowWithoutItsShadowTests`; this is the other end of the
/// same flag, the result the overlay hands the controller.
@MainActor
final class TheOverlayCarriesTheOptionClickAsNoShadowTests: XCTestCase {

    private var overlay: CaptureOverlay?
    private var results: [OverlayResult] = []

    override func tearDown() {
        overlay?.close()
        overlay = nil
        super.tearDown()
    }

    private func windowOverlay() throws -> DisplayID {
        let frames = try OverlayRig.frames()
        let id = try XCTUnwrap(frames.first?.id)
        let window = FrozenWindow(id: 11, frame: CGRect(x: 100, y: 100, width: 300, height: 200), layer: 0)
        overlay = CaptureOverlay(freeze: Freeze(displays: frames.map { .image($0) }, windows: [window]), mode: .window) { [weak self] in
            self?.results.append($0)
        }
        XCTAssertTrue(try XCTUnwrap(overlay).build())
        overlay?.mouseMoved(on: id, at: CGPoint(x: 150, y: 150))
        return id
    }

    private func picked(flags: NSEvent.ModifierFlags) throws -> (UInt32, Bool) {
        let id = try windowOverlay()
        overlay?.mouseDown(on: id, at: CGPoint(x: 150, y: 150), flags: flags)
        guard case .window(let window, let shadow)? = results.first, results.count == 1 else {
            XCTFail("\(results)")
            return (0, false)
        }
        return (window, shadow)
    }

    func testAPlainClickTakesTheWindowWithItsShadow() throws {
        let (window, shadow) = try picked(flags: [])
        XCTAssertEqual(window, 11)
        XCTAssertTrue(shadow, "the default is the shadow, as macOS's")
    }

    func testAnOptionClickTakesTheWindowWithoutIt() throws {
        let (window, shadow) = try picked(flags: [.option])
        XCTAssertEqual(window, 11)
        XCTAssertFalse(shadow)
    }

    /// The other modifiers do not stand for the option.
    func testShiftAndCommandAreNotTheOption() throws {
        XCTAssertTrue(try picked(flags: [.shift, .command]).1)
    }
}
