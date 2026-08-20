// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import AppKit
import SwiftUI

/// **Where each line of type sits, in points, read off a rendering.**
///
/// `RenderedInk` answers how *much* was drawn in a band and `RenderedField`
/// answers which column a **fill** is in. Neither can answer the one question a
/// wrapped headline poses: a sentence that runs onto a second line is drawn
/// twice, and whether the two are centred on the same axis is a fact about the
/// two lines' own extents. Summed over a band, a centred pair and a
/// left-aligned pair are the same number of pixels — which is why
/// `KeepAwakeHero` drew its German headline flush left for a release with every
/// render check on that page green.
///
/// The reading is deliberately blunt: rows that carry ink, grouped where they
/// run together. It cannot tell a caption from a figure and does not try — a
/// caller names the band it is asking about, the way every reader here does.
///
/// **The margin is not optional on a page, and the reason is not the window's
/// edge.** A view mounted alone over a window (`MountedRender`) is transparent
/// where it draws nothing, so the modal pixel of the band *is* transparent and
/// everything drawn departs from it. A whole page mounted in one paints its
/// pane — but not to the window's edge: measured on the Keep Awake page at
/// 845 pt, everything left of 52 pt is `(0, 0, 0, 0)` against a white pane, so
/// the unpainted strip reads as a full-height line and every row of the window
/// joins into one. That was the first reading this took, and it was confident
/// and wrong.
@MainActor
public enum RenderedLines {

    /// One run of rows that carry ink, in points from the top of the view.
    public struct Line: Equatable {
        public let top: CGFloat
        public let bottom: CGFloat
        public let left: CGFloat
        public let right: CGFloat

        /// The axis the line is drawn about, which is what a claim about
        /// centring is made of.
        public var centre: CGFloat { (left + right) / 2 }
    }

    /// The lines `view` drew, optionally inside a band given in points.
    ///
    /// - Parameter joining: how far apart, in points, a **mark** may be from the
    ///   line it belongs to. Zero is the wrong answer and so is «any two runs
    ///   this close», and one measurement gives both halves. The dot of an «i»:
    ///   on the Spanish idle headline at 40 pt, «como siempre» draws its dot as
    ///   a run 4 pt tall, 3 pt clear of the letters under it — a reader that
    ///   does not join is reading marks rather than lines, and a caller that
    ///   then tells a headline from a caption by how tall its ink is stops at
    ///   the dot and never sees the second line, which is a check that silently
    ///   cannot fail in whichever languages spell the word with an «i». But two
    ///   *ordinary* lines of 13 pt type are only 3.5 pt apart, so a rule that
    ///   joined on distance alone would fuse a two-line caption into one run
    ///   28 pt tall and hand it back as a line of 40 pt type. Only a run under
    ///   `markInk` joins: a mark is smaller than a line, and that is what tells
    ///   them apart. Measured on both heroes in all eight languages: dots and
    ///   accents 2 to 4 pt, the shortest real line 10.
    ///
    /// `nil` for anything that would make the reading a guess — no bounds, no
    /// bitmap, a format this arithmetic does not understand, or a band running
    /// off the end of the image. An empty array is a real answer: a band
    /// holding nothing at all.
    public static func read(_ view: NSView, points band: ClosedRange<Int>? = nil,
                            margin: Int = 0, tolerance: Int = 12,
                            joining: CGFloat = 6) -> [Line]? {
        guard view.bounds.width > 0, view.bounds.height > 0,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.bitmapData, rep.samplesPerPixel == 4, rep.bitsPerSample == 8,
              rep.pixelsWide > 2 * margin, rep.pixelsHigh > 0 else { return nil }
        let scale = max(1, rep.pixelsHigh / max(1, Int(view.bounds.height)))
        let rows: Range<Int>
        if let band {
            guard band.lowerBound >= 0, band.upperBound * scale <= rep.pixelsHigh else { return nil }
            rows = (band.lowerBound * scale)..<(band.upperBound * scale)
        } else {
            rows = 0..<rep.pixelsHigh
        }
        guard !rows.isEmpty else { return [] }
        let columns = (margin * scale)..<(rep.pixelsWide - margin * scale)
        guard !columns.isEmpty else { return nil }
        let ground = Ground(pixel: background(data, rep, rows, columns), tolerance: tolerance)
        var lines: [Line] = []
        var open: Run?
        for y in rows {
            guard let span = inked(data, rep, row: y, columns, ground) else {
                if let run = open { lines.append(run.closed(at: y, scale: scale)) }
                open = nil
                continue
            }
            open = open.map { $0.extended(to: span) } ?? Run(top: y, span: span)
        }
        if let run = open { lines.append(run.closed(at: rows.upperBound, scale: scale)) }
        return join(lines, closerThan: joining)
    }

    /// What the band is drawn *on*, and how far a pixel must depart from it
    /// before it counts as ink. One value, because neither answers anything
    /// without the other.
    private struct Ground {
        let pixel: [Int]
        let tolerance: Int
    }

    /// The leftmost and rightmost pixel of one row that departs from the
    /// ground, or nil for a row holding nothing but it.
    private static func inked(_ data: UnsafeMutablePointer<UInt8>, _ rep: NSBitmapImageRep,
                              row y: Int, _ columns: Range<Int>,
                              _ ground: Ground) -> ClosedRange<Int>? {
        let row = y * rep.bytesPerRow
        var lo = -1, hi = -1
        for x in columns {
            let at = row + x * 4
            var far = abs(Int(data[at]) - ground.pixel[0])
            for channel in 1..<4 {
                far = max(far, abs(Int(data[at + channel]) - ground.pixel[channel]))
            }
            guard far > ground.tolerance else { continue }
            if lo < 0 { lo = x }
            hi = x
        }
        return lo < 0 ? nil : lo...hi
    }

    /// A run of inked rows still being read, in device pixels.
    private struct Run {
        let top: Int
        var span: ClosedRange<Int>

        func extended(to next: ClosedRange<Int>) -> Run {
            let left = min(span.lowerBound, next.lowerBound)
            let right = max(span.upperBound, next.upperBound)
            return Run(top: top, span: left...right)
        }

        func closed(at bottom: Int, scale: Int) -> Line {
            Line(top: CGFloat(top) / CGFloat(scale), bottom: CGFloat(bottom) / CGFloat(scale),
                 left: CGFloat(span.lowerBound) / CGFloat(scale),
                 right: CGFloat(span.upperBound) / CGFloat(scale))
        }
    }

    /// The tallest a run may be and still be a mark rather than a line — see
    /// the note on `joining`.
    private static let markInk: CGFloat = 8

    /// A mark nearer than `gap` to a line belongs to it — see the note on
    /// `joining`. The mark may be on either side: an «i» draws its dot above
    /// the letters and a cedilla draws below them.
    private static func join(_ lines: [Line], closerThan gap: CGFloat) -> [Line] {
        lines.reduce(into: []) { joined, next in
            let mark = min(next.bottom - next.top, joined.last.map { $0.bottom - $0.top } ?? 0)
            guard let last = joined.last, next.top - last.bottom < gap, mark < markInk else {
                joined.append(next)
                return
            }
            joined[joined.count - 1] = Line(top: last.top, bottom: next.bottom,
                                            left: min(last.left, next.left),
                                            right: max(last.right, next.right))
        }
    }

    /// The band's own background: the pixel value that occurs most often in
    /// it, sampled every fourth row and column the way `RenderedInk` does —
    /// deterministic, so two readings of one drawing agree to the byte.
    private static func background(_ data: UnsafeMutablePointer<UInt8>,
                                   _ rep: NSBitmapImageRep,
                                   _ rows: Range<Int>, _ columns: Range<Int>) -> [Int] {
        var counts: [UInt32: Int] = [:]
        for y in stride(from: rows.lowerBound, to: rows.upperBound, by: 4) {
            for x in stride(from: columns.lowerBound, to: columns.upperBound, by: 4) {
                let at = y * rep.bytesPerRow + x * 4
                var key: UInt32 = 0
                for channel in 0..<4 { key = key << 8 | UInt32(data[at + channel]) }
                counts[key, default: 0] += 1
            }
        }
        guard let modal = counts.max(by: { ($0.value, $0.key) < ($1.value, $1.key) })?.key else {
            return [0, 0, 0, 0]
        }
        return (0..<4).reversed().map { Int(modal >> UInt32($0 * 8) & 255) }
    }
}
