import XCTest
@testable import Module_Island_Engine

final class NotchMetricsTests: XCTestCase {
    // 14" MBP-like: 1512×982 points, top safe-area inset 32, aux area 500 wide.
    func testNotchScreenProducesRects() {
        let m = NotchMetrics.compute(screen: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                     topInset: 32, auxTopLeftWidth: 500)
        XCTAssertNotNil(m)
        guard let m else { return }
        // Notch strip: centred, exactly as tall as the inset, flush with the top.
        XCTAssertEqual(m.notchRect.width, 512, accuracy: 0.5)   // 1512 − 2×500
        XCTAssertEqual(m.notchRect.midX, 756, accuracy: 0.5)
        XCTAssertEqual(m.notchRect.height, 32)
        XCTAssertEqual(m.notchRect.maxY, 982)
        // Window rect: wider and taller than the notch, centred, top-anchored.
        XCTAssertGreaterThan(m.windowRect.width, m.notchRect.width)
        XCTAssertGreaterThan(m.windowRect.height, m.notchRect.height)
        XCTAssertEqual(m.windowRect.midX, 756, accuracy: 0.5)
        XCTAssertEqual(m.windowRect.maxY, 982)
        // The window stays inside the screen.
        XCTAssertGreaterThanOrEqual(m.windowRect.minX, 0)
        XCTAssertLessThanOrEqual(m.windowRect.maxX, 1512)
    }

    func testNoNotchReturnsNil() {
        // No safe-area inset at all.
        XCTAssertNil(NotchMetrics.compute(screen: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                          topInset: 0, auxTopLeftWidth: 500))
        // Plain menu bar without an aux area (external display).
        XCTAssertNil(NotchMetrics.compute(screen: CGRect(x: 0, y: 0, width: 2560, height: 1440),
                                          topInset: 24, auxTopLeftWidth: 0))
    }

    /// Screens with an origin offset (multi-display) keep rects in that space.
    func testOffsetScreenSpace() {
        let m = NotchMetrics.compute(screen: CGRect(x: 100, y: 50, width: 1512, height: 982),
                                     topInset: 32, auxTopLeftWidth: 500)
        XCTAssertEqual(m?.notchRect.midX ?? 0, 100 + 756, accuracy: 0.5)
        XCTAssertEqual(m?.notchRect.maxY ?? 0, 50 + 982)
    }
}
