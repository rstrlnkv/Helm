import AppKit

/// **One view, written as one PNG, over the ground its window gives it.**
///
/// `FrameRecorder` writes a run of frames for the judge of a motion; this writes
/// a still for a person to look at, into the folder `HELM_FRAMES_DIR` names — a
/// caller asks `directory`, or just calls `write`, which answers `nil` when the
/// variable is not set.
///
/// **The ground is composed here, because the capture has none.** A page draws
/// onto a transparent host, and a dark page photographed that way is white type
/// on nothing. The capture is drawn over `windowBackgroundColor` resolved in the
/// appearance the caller names, in an sRGB context of the capture's own pixel
/// size, and that is what is written. Not a `.background` on the page: a caller
/// handed a page whose root view a harness built cannot reach it.
///
/// **Scale is never a literal.** The capture is already at the backing scale of
/// the screen the suite runs on (`RenderedInk.read` says why its bands are in
/// points); its pixels are kept as they are and the written image's `size` is set
/// to the view's bounds, so a viewer shows it at the size the page has in points.
///
/// **Three things refuse a frame, and no file is made for any.** A view that drew
/// nothing has no ink over its own background — read on the view, as
/// `RenderedInk.read` takes it, before the ground goes under the capture. A view
/// whose appearance is not the one asked for would be written under a name that
/// says the other: a dark frame asked for and a light one written reads as a
/// finding about the page in a folder nobody re-checks. And a ground on the
/// other side of the appearance asked — a dark page over a light fill, however it
/// came about — is read **in the bytes that are written**: the commonest pixel of
/// the two outermost columns, as Rec. 709 luma of its sRGB bytes. That ground is
/// `windowBackgroundColor` unless the page paints over it, and on macOS 27.2 it
/// read 1.000 in light and 0.118 in dark; 0.60 and 0.40 are the lines between, so
/// a page that paints a card to its edges still reads as its own side.
@MainActor
public enum StillFrame {

    /// The folder the stills go to, or nil when `HELM_FRAMES_DIR` is not set or is
    /// empty; a value that does not begin with `/` throws, and nothing is made
    /// under it.
    public static var directory: String? {
        get throws {
            guard let value = ProcessInfo.processInfo.environment["HELM_FRAMES_DIR"],
                  !value.isEmpty else { return nil }
            guard value.hasPrefix("/") else {
                throw Refusal.notWritten("""
                    HELM_FRAMES_DIR is `\(value)`, which is not an absolute path (one that \
                    begins with /), so nothing is written
                    """)
            }
            return value
        }
    }

    public enum Refusal: Error, Equatable {
        /// No ink: the view drew nothing over its own background.
        case nothingDrawn
        /// The view draws in `drawn`, and `asked` is what the caller named.
        case wrongAppearance(asked: String, drawn: String)
        /// The ground at the edges of the written image has this luma, which is not
        /// on the side `asked` names.
        case wrongGround(asked: String, luma: Double)
        /// The folder is not an absolute path, the bitmap or the file could not be
        /// made, or an older file removed; the text says which.
        case notWritten(String)
    }

    /// Where `<directory>/<name>.png` goes, with any older file of that name
    /// removed so that a frame refused leaves none; nil when `HELM_FRAMES_DIR` is
    /// not set.
    @discardableResult
    public static func clear(named name: String) throws -> URL? {
        guard let directory = try Self.directory else { return nil }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        if FileManager.default.fileExists(atPath: url.path) {
            do { try FileManager.default.removeItem(at: url) } catch {
                throw Refusal.notWritten("\(name): the older file could not be removed: \(error)")
            }
        }
        return url
    }

    /// Writes `<directory>/<name>.png` and returns where, or returns nil — and
    /// writes nothing — when `HELM_FRAMES_DIR` is not set.
    @discardableResult
    public static func write(_ view: NSView, in appearance: NSAppearance.Name,
                             named name: String) throws -> URL? {
        guard let url = try clear(named: name) else { return nil }
        let drawn = view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
        guard drawn == appearance else {
            throw Refusal.wrongAppearance(asked: RenderedInk.label(of: appearance),
                                          drawn: drawn.map(RenderedInk.label(of:)) ?? "neither")
        }
        guard let ink = RenderedInk.read(view), ink > 0 else { throw Refusal.nothingDrawn }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw Refusal.notWritten("\(name): no bitmap for the view")
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        let whole = CGRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh)
        guard let capture = rep.cgImage,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: rep.pixelsWide, height: rep.pixelsHigh,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw Refusal.notWritten("\(name): no sRGB context of \(rep.pixelsWide) × \(rep.pixelsHigh)") }
        context.setFillColor(Contrast.system(\.windowBackgroundColor, appearance).cgColor)
        context.fill(whole)
        context.draw(capture, in: whole)
        guard let composed = context.makeImage() else {
            throw Refusal.notWritten("\(name): the composed image could not be made")
        }
        let written = NSBitmapImageRep(cgImage: composed)
        written.size = view.bounds.size
        guard let png = written.representation(using: .png, properties: [:]) else {
            throw Refusal.notWritten("\(name): the image could not be encoded as a PNG")
        }
        guard let luma = edgeLuma(ofPNG: png) else {
            throw Refusal.notWritten("\(name): the encoded image has a layout this cannot read back")
        }
        guard appearance == .darkAqua ? luma <= 0.40 : luma >= 0.60 else {
            throw Refusal.wrongGround(asked: RenderedInk.label(of: appearance), luma: luma)
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try png.write(to: url)
            return url
        } catch {
            throw Refusal.notWritten("\(name): \(error)")
        }
    }

    /// Luma, 0…1, of the commonest pixel in the leftmost and rightmost columns of
    /// an encoded PNG; nil when the image has a layout this does not read.
    private static func edgeLuma(ofPNG png: Data) -> Double? {
        guard let rep = NSBitmapImageRep(data: png), let data = rep.bitmapData,
              rep.bitsPerSample == 8, rep.samplesPerPixel >= 3, rep.pixelsWide > 0,
              !rep.bitmapFormat.contains(.alphaFirst) else { return nil }
        let width = rep.bitsPerPixel / 8
        var counts: [UInt32: Int] = [:]
        for y in 0..<rep.pixelsHigh {
            for x in [0, rep.pixelsWide - 1] {
                let at = y * rep.bytesPerRow + x * width
                counts[UInt32(data[at]) << 16 | UInt32(data[at + 1]) << 8 | UInt32(data[at + 2]),
                       default: 0] += 1
            }
        }
        // Ties broken by value, so two readings of one image agree.
        guard let modal = counts.max(by: { ($0.value, $0.key) < ($1.value, $1.key) })?.key else {
            return nil
        }
        return (0.2126 * Double(modal >> 16 & 255) + 0.7152 * Double(modal >> 8 & 255)
                + 0.0722 * Double(modal & 255)) / 255
    }
}
