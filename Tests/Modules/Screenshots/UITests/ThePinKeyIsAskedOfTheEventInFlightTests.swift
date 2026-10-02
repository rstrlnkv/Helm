import AppKit
import XCTest
@testable import Module_Screenshots_UI

/// **`canBecomeKey` reads the event AppKit is delivering, and this pin's own window number.** The predicate
/// `takesKey` is proved with events handed in; what only a wiring mistake breaks is that the property asks it
/// of `NSApp.currentEvent` with the panel's own `windowNumber` (a pin that never took key would lose Esc,
/// one that asked for another number would take key from a click on another window). The event is posted to the
/// application queue and dequeued, which is what makes it `currentEvent`; no window is ordered on a screen.
///
/// Total failure of the subject prints: a pin that refuses key under its own click, or accepts it under a stranger's.
@MainActor
final class ThePinKeyIsAskedOfTheEventInFlightTests: XCTestCase {

    private func image() -> CGImage {
        CGContext(data: nil, width: 20, height: 10, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
    }

    /// Delivers `type` aimed at `window` and reads what `pin.canBecomeKey` says while it is the current event.
    private func canBecomeKey(_ pin: PinPanel, during type: NSEvent.EventType, aimedAt window: Int) throws -> Bool {
        _ = NSApplication.shared
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                     windowNumber: window, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        NSApp.postEvent(event, atStart: true)
        let got = NSApp.nextEvent(matching: .any, until: Date(timeIntervalSinceNow: 1), inMode: .default, dequeue: true)
        XCTAssertEqual(got?.type, type, "the control: the posted event came back as the current one")
        XCTAssertEqual(got?.windowNumber, window, "the control: it kept its window number")
        XCTAssertNotNil(NSApp.currentEvent, "the control: the dequeued event is the current event")
        return pin.canBecomeKey
    }

    func testAPinTakesKeyUnderItsOwnClickAndNotUnderAStrangers() throws {
        let one = PinPanel(image: image(), frame: CGRect(x: 0, y: 0, width: 20, height: 10))
        let two = PinPanel(image: image(), frame: CGRect(x: 40, y: 0, width: 20, height: 10))
        XCTAssertNotEqual(one.windowNumber, two.windowNumber, "the control: two panels are two window numbers")
        XCTAssertGreaterThan(one.windowNumber, 0, "the control: a panel has a window number before it is ordered in")
        XCTAssertTrue(try canBecomeKey(one, during: .leftMouseDown, aimedAt: one.windowNumber), "a pin refused key under a click on itself")
        XCTAssertFalse(try canBecomeKey(one, during: .leftMouseDown, aimedAt: two.windowNumber), "a pin took key under a click on another pin")
        XCTAssertTrue(try canBecomeKey(two, during: .leftMouseDown, aimedAt: two.windowNumber), "the other pin refused key under its own click")
        XCTAssertFalse(try canBecomeKey(two, during: .leftMouseDown, aimedAt: one.windowNumber), "the other pin took key under the first one's click")
        XCTAssertFalse(try canBecomeKey(one, during: .leftMouseUp, aimedAt: one.windowNumber), "a pin took key from a release")
    }
}
