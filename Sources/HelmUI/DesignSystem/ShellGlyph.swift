import HelmRuntime
import SwiftUI

/// Helm's own set of single-colour shapes, one per module (each descriptor
/// declares its own) and two that no module names, drawn on a 24-unit grid.
///
/// **Why not SF Symbols.** The symbols a module names in its metadata are
/// drawn by the system with the system's weights, while this set wants one
/// simple shape, one uniform thick rounded line and as little detail inside as
/// the shape allows, so the shapes are Helm's, and so is the pen.
///
/// **Three paths per shape.** `body` is the closed outline and is what fills
/// when `filled` is set; `extra` is strokes outside it that stay lines
/// either way (a handle, a lid, a second sheet behind); `detail` is strokes
/// inside it. Filled, `detail` is cut out of the fill instead of drawn in
/// another colour, so a glyph needs no second colour and reads on whatever
/// background it is given.
public struct ShellGlyph: Sendable {
    let body: Path
    let extra: Path
    let detail: Path

    public init(body: Path, extra: Path = Path(), detail: Path = Path()) {
        self.body = body
        self.extra = extra
        self.detail = detail
    }

    /// The side of the square every shape is drawn in. Paths are in these units
    /// and `ShellGlyphView` scales them to the size it is given.
    static let grid: CGFloat = 24

    /// The two shapes no module names; a module's own is declared by its descriptor.
    public static let settings = ShellGlyph(
        body: rounded([pt(12, 3), pt(19.8, 7.5), pt(19.8, 16.5), pt(12, 21), pt(4.2, 16.5), pt(4.2, 7.5)], 2.5),
        detail: circle(12, 12, 3))
    public static let expand = ShellGlyph(body: Path(), extra: lines([[pt(10, 7), pt(15, 12), pt(10, 17)]]))

    // Builders for the paths a descriptor assembles; public because the descriptors live in other targets.
    public static func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    public static func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }

    public static func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r, style: .continuous)
    }

    /// A closed polygon with every corner rounded to `radius`, started at the
    /// middle of the last edge so the first arc has a tangent to leave from.
    public static func rounded(_ points: [CGPoint], _ radius: CGFloat) -> Path {
        var path = Path()
        let last = points[points.count - 1]
        path.move(to: pt((last.x + points[0].x) / 2, (last.y + points[0].y) / 2))
        for index in points.indices {
            path.addArc(tangent1End: points[index],
                        tangent2End: points[(index + 1) % points.count], radius: radius)
        }
        path.closeSubpath()
        return path
    }

    public static func lines(_ runs: [[CGPoint]]) -> Path {
        var path = Path()
        for run in runs {
            path.move(to: run[0])
            for point in run.dropFirst() { path.addLine(to: point) }
        }
        return path
    }

    /// A dot is a stroke a hundredth of a unit long: with the round cap it
    /// draws a circle the width of the pen.
    public static func dot(_ x: CGFloat, _ y: CGFloat) -> [CGPoint] { [pt(x, y), pt(x + 0.01, y)] }
}

/// One `ShellGlyph` at a size, in the foreground style it is given.
///
/// The pen is 2 units of the 24 grid with a round cap and join, scaled with
/// the size. With `filled`, the body is filled and `detail` is cut out of it with
/// `destinationOut`; the compositing group is there so the cut applies to the
/// glyph's own layers and not to what is behind it. An off-screen render does
/// not show the cut stopping at the glyph, and no window has shown either
/// answer.
struct ShellGlyphView: View {
    private let glyph: ShellGlyph
    private let filled: Bool
    private let size: CGFloat

    init(_ glyph: ShellGlyph, filled: Bool, size: CGFloat) {
        self.glyph = glyph
        self.filled = filled
        self.size = size
    }

    /// The largest side a glyph is drawn at, far beyond the size any caller asks
    /// for; it exists so an infinite size has an answer.
    nonisolated static let largest: CGFloat = 1024

    /// The side that is drawn for a size asked for. **A size that is not a
    /// number or is negative draws nothing**, because there is no glyph to
    /// show for a size nobody can name and none can be smaller than nothing; 0
    /// draws nothing too. An infinite size is a size, only a huge one, and
    /// draws at `largest`, which is the answer a bound gives a value past it.
    nonisolated static func side(for size: CGFloat) -> CGFloat {
        size.clamped(to: 0...largest, whenNotANumber: 0)
    }

    var body: some View {
        let side = Self.side(for: size)
        if side > 0 {
            let scale = CGAffineTransform(scaleX: side / ShellGlyph.grid, y: side / ShellGlyph.grid)
            let pen = StrokeStyle(lineWidth: 2 * side / ShellGlyph.grid, lineCap: .round, lineJoin: .round)
            ZStack {
                glyph.extra.applying(scale).stroke(style: pen)
                glyph.body.applying(scale).stroke(style: pen)
                if filled {
                    glyph.body.applying(scale).fill()
                    glyph.detail.applying(scale).stroke(style: pen).blendMode(.destinationOut)
                } else {
                    glyph.detail.applying(scale).stroke(style: pen)
                }
            }
            .compositingGroup()
            .frame(width: side, height: side)
        }
    }
}
