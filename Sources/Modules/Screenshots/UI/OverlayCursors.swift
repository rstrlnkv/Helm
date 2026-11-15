import AppKit

extension OverlayView {
    /// The opacity of a layer the eraser's drag has met, until the release takes it.
    static let fadedOpacity: Float = 0.3

    /// A circle of the eraser's radius, a white fill at 55 % and a 1 pt black edge at 55 %, the hot spot at its centre.
    static let eraserCursor: NSCursor = {
        let radius = CaptureOverlay.eraserRadius
        let size = NSSize(width: radius * 2 + 2, height: radius * 2 + 2)
        let image = NSImage(size: size, flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            OverlayInk.eraserFill.setFill()
            circle.fill()
            OverlayInk.eraserEdge.setStroke()
            circle.lineWidth = 1
            circle.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: size.width / 2, y: size.height / 2))
    }()

    static let cameraCursor = symbolCursor("camera.fill", size: NSSize(width: 28, height: 24), pointSize: 18)

    /// The eyedropper is on (`OverlayScene.sampling`): the cursor is its symbol, its tip at the hot spot, on every display and
    /// wherever the pointer is, so the mode shows before the pointer reaches the area.
    static let eyedropperCursor = symbolCursor("eyedropper", size: NSSize(width: 24, height: 24), pointSize: 18,
                                               hotSpot: NSPoint(x: 3, y: 21))

    /// A symbol on a white halo and then black: legible over a dark window and a light one. The hot spot is the middle unless given.
    private static func symbolCursor(_ name: String, size: NSSize, pointSize: CGFloat, hotSpot: NSPoint? = nil) -> NSCursor {
        let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: .regular))
        let image = NSImage(size: size, flipped: false) { rect in
            guard let base else { return false }
            let glyph = NSRect(x: (rect.width - base.size.width) / 2, y: (rect.height - base.size.height) / 2,
                               width: base.size.width, height: base.size.height)
            for offset in [(-1.0, 0.0), (1, 0), (0, -1), (0, 1)] {
                base.withSymbolConfiguration(.init(paletteColors: [.white]))?
                    .draw(in: glyph.offsetBy(dx: offset.0, dy: offset.1))
            }
            base.withSymbolConfiguration(.init(paletteColors: [.black]))?.draw(in: glyph)
            return true
        }
        return NSCursor(image: image, hotSpot: hotSpot ?? NSPoint(x: size.width / 2, y: size.height / 2))
    }
}
