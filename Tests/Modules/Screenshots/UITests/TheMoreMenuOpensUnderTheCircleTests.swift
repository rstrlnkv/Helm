import AppKit
import CoreGraphics
import Foundation
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **Where the ⋯ menu opens:** under the ⋯ circle, not at the pointer: its left edge at the circle's left, its top
/// at or below the badge ring's bottom (the circle's bottom less `moreBadgeReach`, 1.5 pt tolerance). The
/// palette's reading is in the host's top-left points and `popUp` converts it to the overlay view; the menu's window is
/// read during tracking and compared with the circle's place worked out here from the host's screen rectangle.
@MainActor
final class TheMoreMenuOpensUnderTheCircleTests: XCTestCase {

    /// The pure half: the circle's lower left from a 36 pt zone with a 28 pt circle centred in it.
    func testTheCircleCornerIsFromTheZoneNotFromItsOrigin() {
        let zone = CGRect(x: 300, y: 10, width: 36, height: 36)
        let corner = EditorPalette.moreCircleBottomLeft(zone)
        XCTAssertEqual(corner.x, 304, accuracy: 0.001, "the circle's left is 4 pt in from the zone's")
        XCTAssertEqual(corner.y, 42, accuracy: 0.001, "the circle's bottom is 14 pt under the zone's middle, top-left points")
        let moved = EditorPalette.moreCircleBottomLeft(zone.offsetBy(dx: 50, dy: 7))
        XCTAssertEqual(moved.x - corner.x, 50, accuracy: 0.001)
        XCTAssertEqual(moved.y - corner.y, 7, accuracy: 0.001, "y grows downward: a lower zone gives a larger y")
    }

    func testTheMenuWindowOpensUnderTheCircleNotAtThePointer() throws {
        let (overlay, _, view) = try OverlayRig.overlay(scale: 1, area: CGRect(x: 100, y: 100, width: 400, height: 300)) { _ in }
        defer { overlay.close() }
        let panel = try XCTUnwrap(view.window)
        panel.orderFrontRegardless()
        panel.contentView?.layoutSubtreeIfNeeded()
        let host = try XCTUnwrap(view.subviews.first { String(describing: type(of: $0)).contains("EditorBarHostingView") })
        for _ in 0..<20 where overlay.palette.moreFrame == .zero { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        let zone = overlay.palette.moreFrame
        XCTAssertGreaterThan(zone.width, 20, "control: the palette reported the ⋯ zone (\(zone))")

        // Expected, from the host's screen rectangle alone (no flip arithmetic shared with the code under test).
        let hostScreen = panel.convertToScreen(host.convert(host.bounds, to: nil))
        let expected = CGPoint(x: hostScreen.minX + zone.minX + 4, y: hostScreen.maxY - (zone.midY + 14))

        var found: [(NSWindow, CGRect)] = []
        let probe = Timer(timeInterval: 0.4, repeats: false) { _ in
            MainActor.assumeIsolated {
                found = NSApp.windows.filter { $0 !== panel && $0.isVisible && String(describing: type(of: $0)).lowercased().contains("menu") }
                    .map { ($0, $0.frame) }
                overlay.close()
            }
        }
        let rescue = Timer(timeInterval: 3, repeats: false) { _ in
            MainActor.assumeIsolated {
                for down in [true, false] {
                    if let esc = NSEvent.keyEvent(with: down ? .keyDown : .keyUp, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                                                  isARepeat: false, keyCode: 53) { NSApp.postEvent(esc, atStart: true) }
                }
            }
        }
        RunLoop.main.add(probe, forMode: .common)
        RunLoop.main.add(rescue, forMode: .common)
        overlay.palette.openMenu()
        probe.invalidate(); rescue.invalidate()

        let menuWindow = try XCTUnwrap(found.max { $0.1.height < $1.1.height }, "control: no menu window found during tracking")
        let frame = menuWindow.1
        let topLeft = CGPoint(x: frame.minX, y: frame.maxY)
        // The menu's body must start at or below the badge ring's bottom (circle bottom + badge reach), so the pressed ⋯
        // and its badge stay in view. Screen y grows upward: "below" is a smaller y. The window's own top inset has no
        // public reader; the frame is judged with a stated tolerance instead.
        let ringBottom = expected.y - EditorPalette.moreBadgeReach
        let tolerance: CGFloat = 1.5
        XCTAssertLessThanOrEqual(frame.maxY, ringBottom + tolerance, "menu top \(frame.maxY) must be at or below the badge ring's bottom \(ringBottom) (circle bottom \(expected.y) less reach \(EditorPalette.moreBadgeReach)), tolerance \(tolerance)")
        XCTAssertGreaterThan(frame.maxY, expected.y - 24, "control: the menu is still attached to the circle, not far under it (\(frame.maxY) vs \(expected.y))")
        XCTAssertEqual(topLeft.x, expected.x, accuracy: 2, "menu left \(topLeft.x) vs circle left \(expected.x)")
    }
}
