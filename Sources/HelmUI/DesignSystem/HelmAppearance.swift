import AppKit
import SwiftUI

/// Draws an `NSImage` in the appearance the SwiftUI view is actually in.
///
/// AppKit's dynamic colours — `labelColor`, `textBackgroundColor` — resolve
/// against `NSAppearance.current` at the moment the pixels are produced. Inside
/// a SwiftUI body that is not the view's appearance: nothing sets it, so the
/// colour comes out of whatever was current last. The menu-bar glyphs and the
/// language badges are both built this way, and in a light settings window they
/// came out white on white — a control drawn in a colour nobody chose.
///
/// So a preview says which appearance it means. `colorScheme` is the one fact
/// SwiftUI already tracks correctly, and the drawing runs inside the matching
/// `NSAppearance`.
public enum HelmAppearance {
    /// Runs `body` with `scheme`'s appearance current, so any dynamic colour
    /// it resolves matches the view doing the asking.
    public static func drawing<T>(_ scheme: ColorScheme, _ body: () -> T) -> T {
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        guard let appearance else { return body() }
        var result: T?
        appearance.performAsCurrentDrawingAppearance { result = body() }
        // `performAsCurrentDrawingAppearance` is synchronous, so this is set.
        return result ?? body()
    }

    /// Produces the image's pixels *now*, in `scheme`'s appearance.
    ///
    /// Wrapping the factory call is not enough for an `NSImage` built with a
    /// drawing handler: the handler is lazy and runs when the image is drawn,
    /// by which time the appearance block has long returned. Rasterizing here
    /// pins the colours to the appearance the caller means, whether the source
    /// image draws eagerly (`lockFocus`) or lazily.
    public static func rasterize(_ image: NSImage, scheme: ColorScheme) -> NSImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        return drawing(scheme) {
            let baked = NSImage(size: size)
            baked.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: size))
            baked.unlockFocus()
            return baked
        }
    }
}
