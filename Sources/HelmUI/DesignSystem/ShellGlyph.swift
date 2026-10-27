import HelmRuntime
import SwiftUI

/// Helm's own set of single-colour shapes, one per module and two that no
/// module names, drawn on a 24-unit grid.
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
public enum ShellGlyph: CaseIterable, Hashable, Sendable {
    case disk, duplicates, trash, leftovers, homebrew, keepAwake, layout, vpn, screenshots, autopilot
    case settings, expand

    /// The side of the square every shape is drawn in. Paths are in these units
    /// and `ShellGlyphView` scales them to the size it is given.
    static let grid: CGFloat = 24

    var body: Path {
        switch self {
        case .disk: return Self.circle(12, 12, 8.5)
        case .duplicates: return Self.box(8, 8, 12.5, 12.5, 3.5)
        case .trash:
            var bin = Path()
            bin.move(to: Self.pt(6.2, 8))
            bin.addLine(to: Self.pt(7, 18.3))
            bin.addQuadCurve(to: Self.pt(9.4, 20.5), control: Self.pt(7.2, 20.5))
            bin.addLine(to: Self.pt(14.6, 20.5))
            bin.addQuadCurve(to: Self.pt(17, 18.3), control: Self.pt(16.8, 20.5))
            bin.addLine(to: Self.pt(17.8, 8))
            bin.closeSubpath()
            return bin
        case .leftovers:
            var star = Path()
            star.move(to: Self.pt(12, 3))
            star.addCurve(to: Self.pt(21, 12), control1: Self.pt(12.6, 8.5), control2: Self.pt(15.5, 11.4))
            star.addCurve(to: Self.pt(12, 21), control1: Self.pt(15.5, 12.6), control2: Self.pt(12.6, 15.5))
            star.addCurve(to: Self.pt(3, 12), control1: Self.pt(11.4, 15.5), control2: Self.pt(8.5, 12.6))
            star.addCurve(to: Self.pt(12, 3), control1: Self.pt(8.5, 11.4), control2: Self.pt(11.4, 8.5))
            star.closeSubpath()
            return star
        case .homebrew: return Self.box(4.5, 6, 11.5, 13.5, 3.5)
        case .keepAwake: return Self.circle(11, 13, 8.5).subtracting(Self.circle(16.5, 7.5, 7.3))
        case .layout: return Self.box(2.5, 6, 19, 12, 3.5)
        case .vpn:
            var shield = Path()
            shield.move(to: Self.pt(12, 3.5))
            shield.addLine(to: Self.pt(18.5, 6))
            shield.addQuadCurve(to: Self.pt(19.5, 7.5), control: Self.pt(19.5, 6.4))
            shield.addLine(to: Self.pt(19.5, 11.5))
            shield.addCurve(to: Self.pt(12, 20.8), control1: Self.pt(19.5, 16), control2: Self.pt(16.5, 19))
            shield.addCurve(to: Self.pt(4.5, 11.5), control1: Self.pt(7.5, 19), control2: Self.pt(4.5, 16))
            shield.addLine(to: Self.pt(4.5, 7.5))
            shield.addQuadCurve(to: Self.pt(5.5, 6), control: Self.pt(4.5, 6.4))
            shield.closeSubpath()
            return shield
        case .screenshots: return Self.box(3, 7.5, 18, 12.5, 3.5)
        case .autopilot:
            return Self.rounded([Self.pt(4.5, 5), Self.pt(20.5, 12), Self.pt(4.5, 19), Self.pt(8, 12)], 1.5)
        case .settings:
            return Self.rounded([Self.pt(12, 3), Self.pt(19.8, 7.5), Self.pt(19.8, 16.5),
                                 Self.pt(12, 21), Self.pt(4.2, 16.5), Self.pt(4.2, 7.5)], 2.5)
        case .expand: return Path()
        }
    }

    var extra: Path {
        switch self {
        case .duplicates:
            var back = Path()
            back.move(to: Self.pt(7.5, 16))
            back.addArc(tangent1End: Self.pt(3.5, 16), tangent2End: Self.pt(3.5, 3.5), radius: 3.5)
            back.addArc(tangent1End: Self.pt(3.5, 3.5), tangent2End: Self.pt(16, 3.5), radius: 3.5)
            back.addArc(tangent1End: Self.pt(16, 3.5), tangent2End: Self.pt(16, 16), radius: 3.5)
            back.addLine(to: Self.pt(16, 7.5))
            return back
        case .trash:
            var lid = Self.lines([[Self.pt(4, 8), Self.pt(20, 8)]])
            lid.move(to: Self.pt(9.5, 8))
            lid.addLine(to: Self.pt(9.5, 6))
            lid.addQuadCurve(to: Self.pt(11, 4.5), control: Self.pt(9.5, 4.5))
            lid.addLine(to: Self.pt(13, 4.5))
            lid.addQuadCurve(to: Self.pt(14.5, 6), control: Self.pt(14.5, 4.5))
            lid.addLine(to: Self.pt(14.5, 8))
            return lid
        case .homebrew:
            var handle = Path()
            handle.move(to: Self.pt(16, 9.5))
            handle.addLine(to: Self.pt(17, 9.5))
            handle.addQuadCurve(to: Self.pt(20, 12.5), control: Self.pt(20, 9.5))
            handle.addQuadCurve(to: Self.pt(17, 15.5), control: Self.pt(20, 15.5))
            handle.addLine(to: Self.pt(16, 15.5))
            return handle
        case .screenshots:
            var bump = Path()
            bump.move(to: Self.pt(8.5, 7.5))
            bump.addLine(to: Self.pt(9.6, 5.3))
            bump.addQuadCurve(to: Self.pt(10.9, 4.5), control: Self.pt(10, 4.5))
            bump.addLine(to: Self.pt(13.1, 4.5))
            bump.addQuadCurve(to: Self.pt(14.4, 5.3), control: Self.pt(14, 4.5))
            bump.addLine(to: Self.pt(15.5, 7.5))
            return bump
        case .expand: return Self.lines([[Self.pt(10, 7), Self.pt(15, 12), Self.pt(10, 17)]])
        case .disk, .leftovers, .keepAwake, .layout, .vpn, .autopilot, .settings: return Path()
        }
    }

    var detail: Path {
        switch self {
        case .disk: return Self.lines([[Self.pt(12, 3.5), Self.pt(12, 12), Self.pt(19.2, 16.4)]])
        case .layout:
            return Self.lines([Self.dot(7.5, 10.3), Self.dot(12, 10.3), Self.dot(16.5, 10.3),
                               [Self.pt(9, 13.9), Self.pt(15, 13.9)]])
        case .screenshots: return Self.circle(12, 13.7, 3)
        case .autopilot: return Self.lines([[Self.pt(8, 12), Self.pt(13.5, 12)]])
        case .settings: return Self.circle(12, 12, 3)
        case .duplicates, .trash, .leftovers, .homebrew, .keepAwake, .vpn, .expand: return Path()
        }
    }

    private static func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    private static func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }

    private static func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r, style: .continuous)
    }

    /// A closed polygon with every corner rounded to `radius`, started at the
    /// middle of the last edge so the first arc has a tangent to leave from.
    private static func rounded(_ points: [CGPoint], _ radius: CGFloat) -> Path {
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

    private static func lines(_ runs: [[CGPoint]]) -> Path {
        var path = Path()
        for run in runs {
            path.move(to: run[0])
            for point in run.dropFirst() { path.addLine(to: point) }
        }
        return path
    }

    /// A dot is a stroke a hundredth of a unit long: with the round cap it
    /// draws a circle the width of the pen.
    private static func dot(_ x: CGFloat, _ y: CGFloat) -> [CGPoint] { [pt(x, y), pt(x + 0.01, y)] }
}

/// One `ShellGlyph` at a size, in the foreground style it is given.
///
/// The pen is 2 units of the 24 grid with a round cap and join, scaled with
/// the size. With `filled`, the body is filled and `detail` is cut out of it with
/// `destinationOut`; the compositing group is there so the cut applies to the
/// glyph's own layers and not to what is behind it. An off-screen render does
/// not show the cut stopping at the glyph, and no window has shown either
/// answer.
public struct ShellGlyphView: View {
    private let glyph: ShellGlyph
    private let filled: Bool
    private let size: CGFloat

    public init(_ glyph: ShellGlyph, filled: Bool, size: CGFloat) {
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

    public var body: some View {
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
