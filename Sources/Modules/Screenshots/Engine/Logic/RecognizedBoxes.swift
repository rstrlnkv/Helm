import CoreGraphics

/// Where the system found text, put on the picture the person is editing: Vision's normalised rectangle (a
/// fraction of the picture it read, the origin at the **lower** left) → the pixels of that picture → the pixels
/// of the display's frozen frame it was cut from → the points the editor's layers are in (display-local, origin
/// at the top left). The reverse of what a layer's export does. The text's own box keeps the fractions of a pixel
/// (`ink`); the box of a find is rounded outward to whole pixels of the mosaic's grid (`place`).
///
/// **A box is made to hide a string, not to outline it.** A recognition box is tight, and a tight blur gives away
/// where an edge of the box falls inside a mosaic block: a glyph the partial block leaves half-covered. So the box
/// is **padded** — half a line's height each side across, a quarter up and down — and then **rounded outward to the
/// mosaic's grid**, the one `Pixelate` lays from the display's own pixel (0, 0): every block the box touches is whole,
/// so no edge of it cuts a glyph. Rounded and padded it is clipped to the area, where a partial block is `Pixelate`'s
/// own affair. **The padding does not hide the string's length:** the box is still about as wide as the string plus
/// the same padding, so a person who sees the blur can tell roughly how long what is under it was.
public enum RecognizedBoxes {
    /// The part of the frozen frame that was read and how it relates to the layers' points.
    public struct Source: Sendable, Equatable {
        /// The area as whole pixels of the display's frame, top-left origin — what `ScreenSpace.pixels` gives and
        /// what was cut and handed to the reader.
        public let pixels: CGRect
        /// Pixels to a point on that display.
        public let scale: CGFloat

        public init(pixels: CGRect, scale: CGFloat) {
            self.pixels = pixels
            self.scale = scale
        }
    }

    /// A box to blur: where, in points, and how coarse.
    public struct Placed: Sendable, Equatable {
        public let rect: CGRect
        public let step: AnnotationThickness
    }

    /// Of the padding: across, in lines' heights, each side.
    static let paddingAcross: CGFloat = 0.5
    /// Of the padding: up and down, in lines' heights, each side.
    static let paddingDown: CGFloat = 0.25

    /// The text's own box in the display's points, unpadded, kept to the area; nil when `normalised` is not a
    /// rectangle on the read picture, or nothing of it is in the area.
    public static func ink(of normalised: CGRect, in source: Source) -> CGRect? {
        guard let pixels = framePixels(of: normalised, in: source) else { return nil }
        return points(pixels, scale: source.scale)
    }

    /// The box that hides `normalised`: padded, grid-aligned and kept to the area, with the step its height
    /// calls for (`step(forTextHeight:)`); nil when `ink` is.
    public static func place(_ normalised: CGRect, in source: Source) -> Placed? {
        guard let text = framePixels(of: normalised, in: source) else { return nil }
        let step = step(forTextHeight: text.height / source.scale)
        let side = Pixelate.block(points: step.points(for: .blur), scale: source.scale)
        let padded = text.insetBy(dx: -text.height * paddingAcross, dy: -text.height * paddingDown)
        let grid = CGFloat(side)
        let left = (padded.minX / grid).rounded(.down) * grid, top = (padded.minY / grid).rounded(.down) * grid
        let right = (padded.maxX / grid).rounded(.up) * grid, bottom = (padded.maxY / grid).rounded(.up) * grid
        var box = CGRect(x: left, y: top, width: right - left, height: bottom - top).intersection(source.pixels)
        guard !box.isNull, box.width > 0, box.height > 0 else { return nil }
        // A box of one pixel is none the mosaic can make (`Pixelate.tile`) and the file would be refused for it: where the
        // rounding and the area's edge leave one, it grows inward to two pixels across, or the find is dropped when the area has no room.
        if box.width < 2, box.height < 2 {
            guard source.pixels.width >= 2 else { return nil }
            box.size.width = 2
            if box.maxX > source.pixels.maxX { box.origin.x = source.pixels.maxX - 2 }
        }
        return Placed(rect: points(box, scale: source.scale), step: step)
    }

    /// **The blur's step for an automatic blur comes from the height of the text found,** not from the step the
    /// editor remembers: the smallest of the three whose block is at least that high, the thickest when none is.
    /// Text taller than the thickest block (24 points) therefore gets a block lower than itself, the thickest the
    /// tool has, and what that leaves readable of such large text is not measured here; no fourth step was added.
    /// A block lower than the text it covers can leave digits that are read back out of the mosaic. A height that
    /// is not a number takes the thickest.
    public static func step(forTextHeight points: CGFloat) -> AnnotationThickness {
        guard points.isFinite else { return .thick }
        return AnnotationThickness.allCases.first { $0.points(for: .blur) >= points } ?? .thick
    }

    /// `normalised` in pixels of the display's frame, fractions kept, and kept to the area; nil if it is not a finite
    /// rectangle with area on the read picture or the picture was not.
    private static func framePixels(of normalised: CGRect, in source: Source) -> CGRect? {
        let area = source.pixels
        guard source.scale.isFinite, source.scale > 0, area.width >= 1, area.height >= 1,
              [normalised.minX, normalised.minY, normalised.width, normalised.height].allSatisfy(\.isFinite),
              case let unit = normalised.intersection(CGRect(x: 0, y: 0, width: 1, height: 1)),
              !unit.isNull, unit.width > 0, unit.height > 0
        else { return nil }
        // The lower-left origin turns over here: a top edge is one minus the box's top in the normalised space.
        let read = CGRect(x: unit.minX * area.width, y: (1 - unit.maxY) * area.height,
                          width: unit.width * area.width, height: unit.height * area.height)
        let out = CGRect(x: area.minX + read.minX, y: area.minY + read.minY, width: read.width, height: read.height)
        let kept = out.intersection(area)
        guard !kept.isNull, kept.width > 0, kept.height > 0 else { return nil }
        return kept
    }

    private static func points(_ pixels: CGRect, scale: CGFloat) -> CGRect {
        CGRect(x: pixels.minX / scale, y: pixels.minY / scale, width: pixels.width / scale, height: pixels.height / scale)
    }
}
