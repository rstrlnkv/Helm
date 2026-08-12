// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import AppKit
import SwiftUI

/// Where a **filled field** sits, in points, read off a rendering.
///
/// `RenderedInk` answers how much was drawn in a band; `MountedRender` answers
/// how tall the whole thing is; and AppKit's own view frames answer for anything
/// SwiftUI backs with a real `NSView` — a section card, a control's focus ring.
/// None of the three answers the one question a banner poses: **which column is
/// it in.** A `HelmBanner` is a rounded fill drawn straight into its parent's
/// layer, so it has no frame to read, and its whole defect class is horizontal —
/// VPN's refusal banner ran 30…713 against 20…723 for every card on the page, and
/// the survey that found it recorded that no test could see it.
///
/// A private `edges(_:atPoint:)` had been hand-rolled in a VPN test for exactly
/// this before it moved here, with its own idea of what «the background» is. That
/// is the argument for one reader — and for the pane being an **argument**: a
/// modal-value background reads a full-width field as the pane and then finds
/// nothing drawn at all, and the first version of this took the pane from row 3,
/// which on a scrolling form is the scroll pocket's backdrop and a different
/// colour from the pane, so every row of the window measured as one enormous
/// field. Both readings were confident and wrong.
///
/// `coverage` is what tells a field from a line of type: a fill covers
/// essentially every pixel between its edges, and a sentence covers a fifth of
/// them. Without it «the widest thing on the page» is a caption.
@MainActor
public enum RenderedField {

    /// One row of `view`'s own rendering.
    ///
    /// - Parameters:
    ///   - y: the row, in points from the top of `view`.
    ///   - paneAtX: where on **this same row** the pane's own colour is read
    ///     from, in points. Per row rather than from one fixed point, so the
    ///     reading survives a scroll pocket, a backdrop or a gradient: the x to
    ///     give is the gutter between the scrolling container and the cards,
    ///     which is bare pane on every row of the page.
    ///   - margin: points ignored at each side. The hosting view is wider than
    ///     the settings column it centres, and the space beside it is not the
    ///     same colour as the pane.
    /// - Returns: the extent of what is drawn and the fraction of that extent
    ///   that is drawn on, or nil when the row holds nothing but pane.
    public static func row(_ view: NSView, atPoint y: Int,
                           paneAtX: Int,
                           margin: Int = 0,
                           tolerance: Int = 3) -> (span: ClosedRange<Int>, coverage: Double)? {
        guard view.bounds.width > 0, view.bounds.height > 0,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return row(rep, height: view.bounds.height, atPoint: y,
                   paneAtX: paneAtX, margin: margin, tolerance: tolerance)
    }

    /// The same reading against a bitmap already taken, so a caller scanning a
    /// band of rows photographs the view once rather than once a row — the whole
    /// page is 1.7 million pixels and a 200-row scan of it is a minute.
    public static func row(_ rep: NSBitmapImageRep,
                           height: CGFloat,
                           atPoint y: Int,
                           paneAtX: Int,
                           margin: Int = 0,
                           tolerance: Int = 3) -> (span: ClosedRange<Int>, coverage: Double)? {
        guard let data = rep.bitmapData, rep.samplesPerPixel == 4, rep.bitsPerSample == 8,
              rep.pixelsWide > 0, rep.pixelsHigh > 0 else { return nil }
        // The scale is a fact about whichever display the suite runs on; the
        // arguments are in points, so they are not.
        let scale = max(1, rep.pixelsHigh / max(1, Int(height)))
        let base = y * scale * rep.bytesPerRow
        let paneColumn = paneAtX * scale
        guard y * scale < rep.pixelsHigh, paneColumn >= 0, paneColumn < rep.pixelsWide
        else { return nil }
        let lo = margin * scale, hi = rep.pixelsWide - margin * scale
        guard lo < hi else { return nil }
        let pane = (0..<3).map { Int(data[base + paneColumn * 4 + $0]) }
        var first = -1, last = -1, on = 0
        for x in lo..<hi {
            let at = base + x * 4
            let d = abs(Int(data[at]) - pane[0]) + abs(Int(data[at + 1]) - pane[1])
                + abs(Int(data[at + 2]) - pane[2])
            guard d > tolerance else { continue }
            if first < 0 { first = x }
            last = x
            on += 1
        }
        guard first >= 0 else { return nil }
        let width = last - first + 1
        return ((first / scale)...(last / scale), Double(on) / Double(width))
    }

    /// The **widest** filled field in a band of rows, or nil if the band holds
    /// none. Widest rather than the only one, because a band that reaches a card
    /// contains that card's fill too — so a caller that wants «did a banner
    /// appear» compares this reading against the same band with no banner in it
    /// rather than against nil.
    ///
    /// - Parameter floor: how much of a row's own extent has to be drawn on for
    ///   it to be a fill rather than type. 0.9 with antialiased corners in the
    ///   band; a `HelmBanner`'s middle rows measure 1.0.
    public static func field(_ view: NSView, inPoints band: ClosedRange<Int>,
                             paneAtX: Int,
                             margin: Int = 0,
                             floor: Double = 0.9) -> ClosedRange<Int>? {
        guard view.bounds.width > 0, view.bounds.height > 0,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        var found: Set<ClosedRange<Int>> = []
        for y in band {
            guard let read = row(rep, height: view.bounds.height, atPoint: y,
                                 paneAtX: paneAtX, margin: margin),
                  read.coverage >= floor else { continue }
            found.insert(read.span)
        }
        // A rounded field's first and last rows are narrower than its middle by
        // the corner radius, so the widest reading is the field's own column.
        return found.max { $0.count < $1.count }
    }
}
