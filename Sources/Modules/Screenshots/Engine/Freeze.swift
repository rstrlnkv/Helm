import CoreGraphics
import Foundation

/// A display, as the system numbers it.
public struct DisplayID: Hashable, Sendable {
    public let raw: UInt32
    public init(_ raw: UInt32) { self.raw = raw }
}

/// One display's frozen frame.
///
/// `@unchecked Sendable` because a `CGImage` is immutable and thread-safe and is
/// not declared so. `frame` is the display in CG-global points (see
/// `ScreenSpace`), `scale` the pixels to a point, and the image is at native
/// scale: a 5K display's frame is some sixty megabytes, which is why none of
/// this travels over the transport.
///
/// **`image` never has the pointer in it; `withCursor` does.** The overlay draws
/// `image` under a live crosshair, and a pointer baked into that would be a
/// second one beside it. The cut — `CaptureSession.crop` and the full-screen
/// shot — takes `withCursor` when it exists, which is a second capture of the same
/// display, taken just after `image`, with the pointer macOS draws, in the size and colour Accessibility
/// gives it. It exists only when the setting asked for it, and only for the
/// display the pointer was on: the others hold no pointer, and `shot` falls back
/// to `image` for them.
public struct FrozenDisplay: @unchecked Sendable {
    public let id: DisplayID
    public let frame: CGRect
    public let scale: CGFloat
    public let image: CGImage
    public let withCursor: CGImage?
    /// The display's UUID, which survives a re-plug where `id` may not — what a
    /// remembered selection is keyed to. Nil when the system would not give one.
    public let uuid: String?

    public init(id: DisplayID, frame: CGRect, scale: CGFloat, image: CGImage,
                withCursor: CGImage? = nil, uuid: String? = nil) {
        self.id = id
        self.frame = frame
        self.scale = scale
        self.image = image
        self.withCursor = withCursor
        self.uuid = uuid
    }

    /// What is cut and saved: the pointer's frame when there is one.
    public var shot: CGImage { withCursor ?? image }
}

/// What the freeze found for one display: its frame, or the fact that it was
/// listed and then could not be captured — unplugged between the two calls.
public enum DisplayShot: @unchecked Sendable {
    case image(FrozenDisplay)
    case gone(DisplayID)
}

/// A window that was on screen when the freeze was taken, frame in CG-global points.
public struct FrozenWindow: Sendable, Equatable {
    public let id: UInt32
    public let frame: CGRect
    public let layer: Int
    /// The owning process's name from the same list reading; empty when the list
    /// gave none.
    public let ownerName: String
    /// A system surface whose own picture is the thing itself (the Dock, placed by
    /// its Accessibility bounds): asked for by id, not cut from the freeze.
    public let drawnAlone: Bool

    public init(id: UInt32, frame: CGRect, layer: Int, ownerName: String = "", drawnAlone: Bool = false) {
        self.id = id
        self.frame = frame
        self.layer = layer
        self.ownerName = ownerName
        self.drawnAlone = drawnAlone
    }
}

/// Every display and the window list, taken in one go.
///
/// **The window list is a reading.** It describes the desktop at the moment of
/// the freeze, and the act — a click on one of them — comes seconds later, so
/// `CaptureSession.window` asks again before it believes any entry.
public struct Freeze: @unchecked Sendable {
    public let displays: [DisplayShot]
    /// Front to back.
    public let windows: [FrozenWindow]

    public init(displays: [DisplayShot], windows: [FrozenWindow]) {
        self.displays = displays
        self.windows = windows
    }

    /// The displays that came back with a picture, main first.
    public var frames: [FrozenDisplay] {
        displays.compactMap { if case .image(let frame) = $0 { frame } else { nil } }
    }
}

/// A finished picture laid over a fresh freeze, for the editor to open on: «Edit» on a shot that was already taken.
///
/// The overlay edits an area of a frozen display and knows nothing else, so the picture is drawn into the frame of
/// one display, in the middle of it, one pixel of the picture to one pixel of the display, and the editor's area is
/// the picture's own rectangle. **A picture larger than the display is drawn smaller and is not saved smaller:** the
/// export draws the layers over `picture` itself (`CaptureSession.annotated(_:local:layers:)`), their points
/// multiplied by `pixelsPerPoint`.
public struct PictureOnScreen: @unchecked Sendable {
    /// What the overlay draws: every display as it was frozen, and `display` with the picture in it.
    public let freeze: Freeze
    public let display: DisplayID
    /// Where the picture stands on `display`, in that display's own top-left points.
    public let rect: CGRect
    /// The picture at its own size.
    public let picture: CGImage

    /// The picture's pixels to one point of the screen: the display's scale while the picture fits, more when it
    /// was reduced. The two sides have ratios of their own, apart by the rounding of the reduced size to whole pixels
    /// of the display; the larger one is taken, so that the area of the whole picture reaches every pixel of it.
    /// `frame` rounds so that the width's is the larger; the height's decides only for a width of one pixel.
    public var pixelsPerPoint: CGFloat { max(CGFloat(picture.width) / rect.width, CGFloat(picture.height) / rect.height) }

    /// Where a picture of `pixels` stands on a display whose frame is `display` pixels at `scale`: centred, on
    /// whole pixels, reduced to fit with its proportions kept and never enlarged. **The side that does not decide the
    /// reduction is rounded so that the pixels per point read off the other side still reach the last row or column
    /// of the picture:** the height up where the width decides, the width down where the height does. Rounded to
    /// nearest, a picture of 12 × 250 at 2× lost its last rows to an edit. Nil for a size with no area or one that
    /// is not a number.
    public static func frame(pixels: CGSize, on display: CGSize, scale: CGFloat) -> CGRect? {
        guard pixels.width.isFinite, pixels.height.isFinite, pixels.width >= 1, pixels.height >= 1,
              display.width.isFinite, display.height.isFinite, display.width >= 1, display.height >= 1,
              scale.isFinite, scale > 0
        else { return nil }
        let width: CGFloat, height: CGFloat
        if pixels.width <= display.width, pixels.height <= display.height {
            (width, height) = (pixels.width.rounded(), pixels.height.rounded())
        } else if display.width * pixels.height <= display.height * pixels.width {
            // The width decides and is the display's; the height, rounded up, is still no more than the display's.
            width = display.width
            height = min(display.height, max(1, (pixels.height * display.width / pixels.width).rounded(.up)))
        } else {
            height = display.height
            width = min(display.width, max(1, (pixels.width * display.height / pixels.height).rounded(.down)))
        }
        let x = ((display.width - width) / 2).rounded(.down), y = ((display.height - height) / 2).rounded(.down)
        return CGRect(x: x / scale, y: y / scale, width: width / scale, height: height / scale)
    }

    /// `picture` over the frame of `display` in `freeze`, or of the first display when that one is not in it. Nil
    /// when the freeze has no frame or the bitmap could not be made. The composed frame carries no pointer and the
    /// freeze no windows: neither is asked of an edit.
    public static func place(_ picture: CGImage, over freeze: Freeze, on display: DisplayID?) -> PictureOnScreen? {
        let frames = freeze.frames
        guard let frame = frames.first(where: { $0.id == display }) ?? frames.first,
              let rect = Self.frame(pixels: CGSize(width: picture.width, height: picture.height),
                                    on: CGSize(width: frame.image.width, height: frame.image.height), scale: frame.scale),
              let composed = compose(picture, over: frame.image, at: rect, scale: frame.scale)
        else { return nil }
        let shown = FrozenDisplay(id: frame.id, frame: frame.frame, scale: frame.scale, image: composed, uuid: frame.uuid)
        let displays = freeze.displays.map { shot -> DisplayShot in
            if case .image(let other) = shot, other.id == frame.id { .image(shown) } else { shot }
        }
        return PictureOnScreen(freeze: Freeze(displays: displays, windows: []), display: frame.id, rect: rect, picture: picture)
    }

    /// The pool is inside the call, as in `CaptureSession.encode`: a 5K frame is one iteration of the caller's work.
    private static func compose(_ picture: CGImage, over ground: CGImage, at rect: CGRect, scale: CGFloat) -> CGImage? {
        autoreleasepool {
            for space in Pixelate.spaces(for: ground) {
                guard let context = CGContext(data: nil, width: ground.width, height: ground.height,
                                              bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { continue }
                context.draw(ground, in: CGRect(x: 0, y: 0, width: ground.width, height: ground.height))
                context.interpolationQuality = .high
                // Top-left points to this bitmap's pixels, bottom-left.
                context.draw(picture, in: CGRect(x: rect.minX * scale, y: CGFloat(ground.height) - rect.maxY * scale,
                                                 width: rect.width * scale, height: rect.height * scale))
                return context.makeImage()
            }
            return nil
        }
    }
}
