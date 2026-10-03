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
