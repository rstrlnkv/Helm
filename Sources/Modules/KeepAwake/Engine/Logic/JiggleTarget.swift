import CoreGraphics
import HelmRuntime

public enum JiggleTarget {
    /// Point 1px from origin, kept inside bounds (inset 2). nil if bounds degenerate.
    public static func nudge(from p: CGPoint, in bounds: CGRect) -> CGPoint? {
        let f = bounds.insetBy(dx: 2, dy: 2)
        guard f.width > 0, f.height > 0 else { return nil }
        let x = p.x.clamped(to: f.minX...f.maxX), y = p.y.clamped(to: f.minY...f.maxY)
        if x + 1 <= f.maxX { return CGPoint(x: x + 1, y: y) }
        if x - 1 >= f.minX { return CGPoint(x: x - 1, y: y) }
        return nil
    }
}
