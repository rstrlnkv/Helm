import CoreGraphics
import Foundation
import HelmRuntime

/// How far the person moved the capture panel from where it opens, in points, in the screen's own (bottom-left)
/// axes: one move for every display, with no memory of which display it was made on.
///
/// Read from a property list any process running as the user can write, so a number that is not one is **no move**
/// (a panel that opens where it always did), and one that is only large — an infinity too — is held to the ceiling of
/// every stored coordinate (`StoredNumber`), on its own side. Each axis is judged alone: a bad `y` does not take a
/// good `x` with it.
public struct PanelOffset: Equatable, Sendable {
    public var dx: Double
    public var dy: Double

    public static let zero = PanelOffset(dx: 0, dy: 0)
    static let ceiling = StoredNumber.ceiling

    public init(dx: Double, dy: Double) {
        self.dx = dx.clamped(to: -Self.ceiling...Self.ceiling, whenNotANumber: 0)
        self.dy = dy.clamped(to: -Self.ceiling...Self.ceiling, whenNotANumber: 0)
    }

    public static func read(_ store: NamespacedStore) -> PanelOffset {
        PanelOffset(dx: StoredNumber.read(store, ScreenshotsSettings.Key.panelOffsetX) ?? 0,
                    dy: StoredNumber.read(store, ScreenshotsSettings.Key.panelOffsetY) ?? 0)
    }

    public func write(to store: NamespacedStore) {
        store.set(dx, for: ScreenshotsSettings.Key.panelOffsetX)
        store.set(dy, for: ScreenshotsSettings.Key.panelOffsetY)
    }

    /// «Put the Panel Back»: both keys, so a half-written one is gone too.
    public static func erase(from store: NamespacedStore) {
        store.set(nil, for: ScreenshotsSettings.Key.panelOffsetX)
        store.set(nil, for: ScreenshotsSettings.Key.panelOffsetY)
    }
}

/// Where the capture panel stands: its place by default (bottom centre of the screen the pointer is on, a little above
/// the Dock) moved by the person's `PanelOffset` and then **held inside that screen's `visibleFrame` as it is now** —
/// the offset was made on a desk that may be gone (another display, another resolution), and a panel nobody can reach
/// is the failure this function exists to rule out.
public enum PanelPlace {
    /// The panel's bottom edge above the bottom of the visible frame, in points.
    public static let rise: CGFloat = 24

    public static func standard(size: CGSize, in visible: CGRect) -> CGPoint {
        CGPoint(x: visible.midX - size.width / 2, y: visible.minY + rise)
    }

    /// The panel's origin: the default place moved by `offset`, then pulled in so the whole panel is visible. A panel
    /// larger than the frame keeps its lower left corner at the frame's.
    public static func origin(size: CGSize, offset: PanelOffset, in visible: CGRect) -> CGPoint {
        let standard = standard(size: size, in: visible)
        let x = standard.x + CGFloat(offset.dx), y = standard.y + CGFloat(offset.dy)
        return CGPoint(x: x.clamped(to: visible.minX...max(visible.minX, visible.maxX - size.width)),
                       y: y.clamped(to: visible.minY...max(visible.minY, visible.maxY - size.height)))
    }

    /// The move that puts a panel standing at `origin` there: what is stored when the person lets go of it.
    public static func offset(of origin: CGPoint, size: CGSize, in visible: CGRect) -> PanelOffset {
        let standard = standard(size: size, in: visible)
        return PanelOffset(dx: Double(origin.x - standard.x), dy: Double(origin.y - standard.y))
    }
}
