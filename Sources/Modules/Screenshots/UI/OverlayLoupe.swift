import AppKit
import QuartzCore
import Module_Screenshots_Engine

/// The selection's loupe: the nine by nine pixels around the pointer, magnified without smoothing in a
/// round window with a grid, the middle pixel boxed, and a plate under it that reads the middle pixel's
/// colour and place. Shown only where `OverlayScene.loupeAt` is set, which two things do: a handle of the area held, so the
/// person sees the pixel the edge will land on, and the eyedropper on, so the person sees the pixel a click will pick.
///
/// The layer covers the view and its parts are placed in the view's own layer space (origin bottom-left).
final class LoupeLayer: CALayer {
    /// One source pixel's side on the screen, in points.
    static let cell: CGFloat = 12
    static var diameter: CGFloat { CGFloat(PixelLoupe.side) * cell }
    /// How far the round window stands to the right of the pointer and above it, and the gap between plate and window.
    private static let reach: CGFloat = 18
    private static let gap: CGFloat = 6
    private static let margin: CGFloat = 4

    private let picture = CALayer()
    private let grid = CAShapeLayer()
    private let middle = CAShapeLayer()
    private let halo = CAShapeLayer()
    private let ring = CAShapeLayer()
    private let plate = LabelLayer()

    /// What the plate says, nil while the loupe is hidden: a test reads it.
    var reading: String? { isHidden ? nil : plate.string }
    /// Where the round window stands, in the view's layer space.
    private(set) var disc: CGRect = .zero

    override init() {
        super.init()
        let side = Self.diameter
        picture.magnificationFilter = .nearest
        picture.minificationFilter = .nearest
        picture.contentsGravity = .resize
        let round = CAShapeLayer()
        round.path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: side, height: side), transform: nil)
        picture.mask = round

        let lines = CGMutablePath()
        for index in 1..<PixelLoupe.side {
            let at = CGFloat(index) * Self.cell
            lines.move(to: CGPoint(x: at, y: 0)); lines.addLine(to: CGPoint(x: at, y: side))
            lines.move(to: CGPoint(x: 0, y: at)); lines.addLine(to: CGPoint(x: side, y: at))
        }
        grid.path = lines
        grid.strokeColor = NSColor.black.withAlphaComponent(0.12).cgColor
        grid.fillColor = nil
        grid.lineWidth = 1
        let box = CGRect(x: CGFloat(PixelLoupe.side / 2) * Self.cell, y: CGFloat(PixelLoupe.side / 2) * Self.cell,
                         width: Self.cell, height: Self.cell)
        // The middle pixel's box: black 2 points outside the pixel, with white beyond it, so it reads on a dark
        // pixel as on a light one.
        middle.path = CGPath(rect: box.insetBy(dx: -1, dy: -1), transform: nil)
        middle.fillColor = nil
        middle.strokeColor = NSColor.black.cgColor
        middle.lineWidth = 2
        halo.path = CGPath(rect: box.insetBy(dx: -1.5, dy: -1.5), transform: nil)
        halo.fillColor = nil
        halo.strokeColor = NSColor.white.cgColor
        halo.lineWidth = 3
        picture.addSublayer(grid)
        picture.addSublayer(halo)
        picture.addSublayer(middle)

        // A white disc three points wider than the window, under it: its rim is the ring, and the shadow is the
        // whole loupe's, so the edge reads over a white page as over a black one.
        let rim: CGFloat = 3
        ring.fillColor = NSColor.white.cgColor
        ring.path = CGPath(ellipseIn: CGRect(x: -rim, y: -rim, width: side + 2 * rim, height: side + 2 * rim), transform: nil)
        ring.shadowColor = NSColor.black.cgColor
        ring.shadowOpacity = 0.45
        ring.shadowRadius = 9
        ring.shadowOffset = CGSize(width: 0, height: -6)

        for part in [ring, picture, plate] as [CALayer] { addSublayer(part) }
        isHidden = true
    }
    override init(layer: Any) { super.init(layer: layer) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    /// The round window and the plate for a pointer at `pointer`, inside `bounds`: the window `reach` points to the
    /// right of the pointer with its foot `reach` above it, the plate under the window with their edges aligned.
    /// Where there is no room on the right both go to the left, and where there is none above the plate the window
    /// goes under it.
    static func place(pointer: CGPoint, plate: CGSize, within bounds: CGRect) -> (disc: CGRect, plate: CGRect) {
        let side = diameter
        let width = max(plate.width, side)
        var x = pointer.x + reach
        if x + width > bounds.maxX - margin { x = pointer.x - reach - width }
        x = min(max(x, bounds.minX + margin), bounds.maxX - width - margin)
        let y = min(max(pointer.y + reach - gap - plate.height, bounds.minY + margin), bounds.maxY - plate.height - margin)
        let plateFrame = CGRect(origin: CGPoint(x: x, y: y), size: plate)
        var top = plateFrame.maxY + gap
        if top + side > bounds.maxY - margin { top = max(bounds.minY + margin, plateFrame.minY - gap - side) }
        return (CGRect(x: x, y: top, width: side, height: side), plateFrame)
    }

    func show(_ loupe: PixelLoupe, at pointer: CGPoint, within bounds: CGRect) {
        frame = bounds
        let text = "\(loupe.hex) · \(loupe.pixel.x), \(loupe.pixel.y)"
        let placed = Self.place(pointer: pointer, plate: LabelLayer.size(of: text), within: bounds)
        disc = placed.disc
        picture.contents = loupe.image
        picture.frame = placed.disc
        ring.frame = placed.disc
        plate.show(text, near: placed.plate.origin, within: bounds)
        isHidden = false
    }
}
