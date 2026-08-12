import AppKit
import SwiftUI

/// What a view drew, measured so the answer does not depend on which appearance
/// the Mac happens to be in.
///
/// **The reading this replaces was the weather.** Six pixel checks summed the
/// three colour channels — «colour mass» — of a band of text. A label is drawn
/// in `labelColor`, which resolves to white in dark and to black in light, and a
/// bitmap from `cacheDisplay` is premultiplied: black type on a transparent view
/// is `(0, 0, 0, α)`, so *r + g + b is exactly zero for every pixel of it*. The
/// whole family was green while this Mac was in dark mode and read 0 in light —
/// and `AppleInterfaceStyleSwitchesAutomatically` is on here, so the suite went
/// red at 04:34:58 on 2026-08-12 with nothing committed in between. Seven tests,
/// one sunrise.
///
/// `Contrast` already carried this lesson for colours — "a dynamic colour has to
/// be resolved in an appearance, or the reading is about whatever appearance the
/// test process happens to be in" — and the pixel readers never learned it.
///
/// So two things are fixed here, and they are separate:
///
/// - **the appearance is pinned**, by name, at the window and the host: never
///   inherited from the machine. `bothAppearances` is there so a claim about
///   what somebody sees is checked on both screens rather than on whichever one
///   this Mac is showing, which is the same argument
///   `StringsCoverageTests` makes about a language;
/// - **and the ink is a departure from the background, not a brightness.** For
///   every pixel, the largest distance of any of its four channels from the
///   band's own background, summed. On a transparent view that is the alpha
///   coverage of what was drawn, identical in either appearance for a fill and
///   within 14 % of itself for antialiased type; on the panel's opaque card,
///   where alpha is 255 everywhere and useless, it is the colour difference from
///   the card — measured equal to the byte in both appearances. `.opacity(0.35)`
///   reads as 0.358 of the full value in *both*, so «it went dim» is a ratio
///   that means the same thing on either screen.
///
/// Measured, one hero at 744 pt, colour mass against this:
///
/// | render               | colour light | colour dark | ink light | ink dark |
/// |---------------------|-------------:|------------:|----------:|---------:|
/// | a line of type      |            0 |     698 787 |   203 316 |  232 929 |
/// | five buttons        |            0 |   2 874 105 |   900 246 |  958 035 |
/// | the same, dimmed    |            0 |   1 029 363 |   321 996 |  343 121 |
/// | type on an opaque card | 110 054 361 |  13 065 639 |    35 213 |   35 213 |
/// | nothing at all      |            0 |           0 |         0 |        0 |
@MainActor
public enum RenderedInk {

    /// The two appearances a Mac draws in, in the order a reading reports them.
    ///
    /// Light first, deliberately: it is the one the old instrument could not see
    /// at all, so a check written against this list fails in the appearance that
    /// was never measured before it fails in the one that was.
    public static let bothAppearances: [NSAppearance.Name] = [.aqua, .darkAqua]

    /// For a failure message, so «which screen» is in the text rather than in
    /// the reader's head.
    public static func label(of appearance: NSAppearance.Name) -> String {
        appearance == .darkAqua ? "dark" : "light"
    }

    /// Ink in a band of `view`'s own rendering, in points from the top.
    ///
    /// `nil` for anything that would make the reading a guess: a view with no
    /// bounds, no bitmap at all, a format this arithmetic does not understand, or
    /// a band that runs off the end of the image. That last one is not a skip —
    /// a band past the bottom reads as no ink, which is exactly what «the row is
    /// gone» looks like, so the two have to be told apart.
    ///
    /// Zero, on the other hand, is a real answer: it is a band holding nothing
    /// but its own background. Which is why every check built on this asserts
    /// first that the thing was drawn, and only then that it went away.
    public static func read(_ view: NSView, points band: ClosedRange<Int>? = nil) -> Int? {
        guard view.bounds.width > 0, view.bounds.height > 0,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.bitmapData, rep.samplesPerPixel == 4, rep.bitsPerSample == 8,
              rep.pixelsWide > 0, rep.pixelsHigh > 0 else { return nil }
        // The scale is a fact about whichever display the suite runs on; the
        // bands are in points, so they are not.
        let scale = max(1, rep.pixelsHigh / max(1, Int(view.bounds.height)))
        let rows: Range<Int>
        if let band {
            guard band.lowerBound >= 0, band.upperBound * scale <= rep.pixelsHigh else { return nil }
            rows = (band.lowerBound * scale)..<(band.upperBound * scale)
        } else {
            rows = 0..<rep.pixelsHigh
        }
        guard !rows.isEmpty else { return nil }
        // Unrolled, and the four channels are locals: the settle loop below reads
        // 1.2 million pixels a frame and a hundred frames a still, and the same
        // arithmetic written as a nested loop over `ground` took this file's tests
        // from 10 s to 69 s.
        let ground = background(data, rep, rows)
        let (g0, g1, g2, g3) = (ground[0], ground[1], ground[2], ground[3])
        let stride = rep.bytesPerRow, width = rep.pixelsWide
        var ink = 0
        for y in rows {
            let row = y * stride
            for x in 0..<width {
                let at = row + x * 4
                var far = abs(Int(data[at]) - g0)
                let g = abs(Int(data[at + 1]) - g1)
                if g > far { far = g }
                let b = abs(Int(data[at + 2]) - g2)
                if b > far { far = b }
                let a = abs(Int(data[at + 3]) - g3)
                if a > far { far = a }
                ink += far
            }
        }
        return ink
    }

    /// The band's own background: the pixel value that occurs most often in it.
    ///
    /// Sampled every fourth row and column rather than counted in full — a
    /// dictionary over 1.2 million pixels a frame would make the settle loop
    /// below take minutes, and the background of one of these bands is a
    /// majority of it by a wide margin. The sample is deterministic, so two
    /// readings of one drawing still agree to the byte, which is what the
    /// equality checks in `BothNoticesShareOneSlotTests` compare.
    private static func background(_ data: UnsafeMutablePointer<UInt8>,
                                   _ rep: NSBitmapImageRep,
                                   _ rows: Range<Int>) -> [Int] {
        var counts: [UInt32: Int] = [:]
        for y in stride(from: rows.lowerBound, to: rows.upperBound, by: 4) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
                let at = y * rep.bytesPerRow + x * 4
                var key: UInt32 = 0
                for channel in 0..<4 { key = key << 8 | UInt32(data[at + channel]) }
                counts[key, default: 0] += 1
            }
        }
        // Ties broken by value, so the answer is the same on two runs of the
        // same drawing: a dictionary's `max` is otherwise free to pick either.
        guard let modal = counts.max(by: { ($0.value, $0.key) < ($1.value, $1.key) })?.key else {
            return [0, 0, 0, 0]
        }
        return (0..<4).reversed().map { Int(modal >> UInt32($0 * 8) & 255) }
    }
}

/// A view mounted the way AppKit needs it before it will draw anything, in a
/// named appearance.
///
/// **A window, not a bare view**: a `List` is an AppKit table and draws nothing
/// without one, and `NSHostingView` will not lay out a `Form`'s chrome outside
/// one either. **And `NSHostingView`, never `ImageRenderer`**, which hands back a
/// blank image for the same content — the story is in `ModulePageRender`.
///
/// The appearance is a required argument. There is no default, because the
/// default was the bug: every one of these readings used to inherit
/// `NSApp.effectiveAppearance`, and `NSApp` in a test process is whatever the
/// person's Mac is set to that hour.
@MainActor
public final class MountedRender {

    public let host: NSHostingView<AnyView>
    public let appearance: NSAppearance.Name
    private var window: NSWindow?

    public init<V: View>(_ view: V, width: CGFloat, height: CGFloat,
                         appearance: NSAppearance.Name) {
        self.appearance = appearance
        let named = NSAppearance(named: appearance)
        host = NSHostingView(rootView: AnyView(VStack(spacing: 0) { view }.frame(width: width)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = named
        window.contentView = host
        host.appearance = named
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        window.layoutIfNeeded()
        self.window = window
    }

    /// Turns of the run loop. Both notices arrive by *growing*, over 300 ms and
    /// two round trips through `onGeometryChange`, so a reading taken on the
    /// first turn is of a frame nobody sees.
    public func settle(_ turns: Int = 40) {
        for _ in 0..<turns {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    public func ink(_ band: ClosedRange<Int>? = nil) -> Int? {
        RenderedInk.read(host, points: band)
    }

    /// The first reading that has repeated `steady` turns running, or `nil` if
    /// the drawing never stops moving.
    ///
    /// Settling on `fittingSize` looked like the answer and is blind to this: a
    /// panel tile's own height is fixed by its card, so the outer measurement is
    /// stable from the first turn while the notice inside is still ramping. Three
    /// consecutive runs then gave six different numbers for two renders. An
    /// unsettled still is not a slower measurement, it is a different one every
    /// time — so it is refused rather than returned.
    public func settledInk(_ band: ClosedRange<Int>? = nil,
                           turns: Int = 200, steady: Int = 8) -> Int? {
        var previous = -1
        var same = 0
        for _ in 0..<turns {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            guard let ink = ink(band) else { return nil }
            same = ink == previous ? same + 1 : 0
            previous = ink
            if same >= steady { return ink }
        }
        return nil
    }

    public var fittingHeight: CGFloat { host.fittingSize.height }

    /// Let go of the window. Called from a test's own teardown: a window left
    /// holding a hosting view holds the view model behind it too.
    public func drop() {
        window?.contentView = nil
        window = nil
    }
}
