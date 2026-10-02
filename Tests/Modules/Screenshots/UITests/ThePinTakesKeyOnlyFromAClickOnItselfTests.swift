import AppKit
import XCTest
@testable import Module_Screenshots_UI

/// **A pin becomes key only from a left mouse down on itself.** When a capture's bar or overlay is ordered out,
/// AppKit offers key to the next window that can take it; a pin that always could would take the person's typing
/// and Esc from the app they are in. Read here is the predicate `canBecomeKey` asks, with an event handed in:
/// no window is ordered on a screen. That AppKit asks it of a clicked pin before `mouseDown`, and that a pin
/// is not made key when a bar closes over it, only a rendered, live run can show.
///
/// Total failure of the subject prints: a pin that takes key with no event, or from another window's click.
@MainActor
final class ThePinTakesKeyOnlyFromAClickOnItselfTests: XCTestCase {

    private func event(_ type: NSEvent.EventType, window: Int) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window,
                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    func testOnlyALeftMouseDownOnThePinTakesKey() {
        XCTAssertTrue(PinPanel.takesKey(from: event(.leftMouseDown, window: 7), windowNumber: 7))
        XCTAssertFalse(PinPanel.takesKey(from: nil, windowNumber: 7), "key was taken with no event under way")
        XCTAssertFalse(PinPanel.takesKey(from: event(.leftMouseDown, window: 8), windowNumber: 7), "another window's click")
        XCTAssertFalse(PinPanel.takesKey(from: event(.leftMouseUp, window: 7), windowNumber: 7))
        XCTAssertFalse(PinPanel.takesKey(from: event(.rightMouseDown, window: 7), windowNumber: 7))
    }

    /// With no event in flight, as in a test, a panel is not offered key at all.
    func testAPanelOfferedKeyWithNoClickRefusesIt() {
        let pin = PinPanel(image: makeOne(), frame: CGRect(x: 0, y: 0, width: 20, height: 10))
        XCTAssertFalse(pin.canBecomeKey)
    }

    private func makeOne() -> CGImage {
        CGContext(data: nil, width: 20, height: 10, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
    }
}
