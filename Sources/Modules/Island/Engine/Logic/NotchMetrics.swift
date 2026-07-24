import Foundation
import CoreGraphics

/// Island geometry, derived purely from screen numbers so it is testable.
/// Production feeds `NSScreen`: `topInset` = `safeAreaInsets.top`,
/// `auxTopLeftWidth` = `auxiliaryTopLeftArea?.width ?? 0` — both are non-zero
/// only on built-in displays with a notch.
public struct NotchMetrics: Equatable, Sendable {
    /// The physical notch strip (flush with the top edge, in screen space).
    public let notchRect: CGRect
    /// The island window: one static frame that accommodates every state —
    /// wider than the notch and extending downward for the expanded card.
    public let windowRect: CGRect

    /// Horizontal margin around the notch for the expanded card, and the
    /// downward room the window reserves (content animates inside it).
    static let horizontalMargin: CGFloat = 260
    static let dropHeight: CGFloat = 360

    public static func compute(screen: CGRect, topInset: CGFloat, auxTopLeftWidth: CGFloat) -> NotchMetrics? {
        guard topInset > 0, auxTopLeftWidth > 0 else { return nil }
        let notchWidth = screen.width - 2 * auxTopLeftWidth
        guard notchWidth > 0 else { return nil }

        let notch = CGRect(x: screen.midX - notchWidth / 2,
                           y: screen.maxY - topInset,
                           width: notchWidth,
                           height: topInset)

        var window = CGRect(x: notch.minX - horizontalMargin,
                            y: screen.maxY - dropHeight,
                            width: notchWidth + 2 * horizontalMargin,
                            height: dropHeight)
        // Clamp into the screen (narrow screens).
        if window.minX < screen.minX { window.origin.x = screen.minX }
        if window.maxX > screen.maxX { window.origin.x = screen.maxX - window.width }

        return NotchMetrics(notchRect: notch, windowRect: window)
    }
}
