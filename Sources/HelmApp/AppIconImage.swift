import AppKit

/// The app icon drawn in the dark appearance regardless of the system theme.
/// The light variant is a white slab: inside Helm's own dark-leaning surfaces
/// it reads as a bright hole, and the glass slab of the dark variant sits
/// correctly in both themes. AppKit resolves the variant at draw time, so the
/// appearance has to be forced around the draw call, not around the image.
@MainActor enum AppIconImage {
    static let dark: NSImage = render(size: NSSize(width: 512, height: 512))

    private static func render(size: NSSize) -> NSImage {
        guard let source = NSApplication.shared.applicationIconImage else { return NSImage() }
        let image = NSImage(size: size)
        image.lockFocus()
        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
            source.draw(in: NSRect(origin: .zero, size: size))
        }
        image.unlockFocus()
        return image
    }
}
