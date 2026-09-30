import AppKit

/// **How far past its last row a list can be scrolled**, read off the list's
/// own `NSScrollView` at the furthest offset AppKit will actually allow.
///
/// The offset is not computed from the document height; it is asked of the
/// clip view (`constrainBoundsRect` with an origin far below the end), so the
/// content insets, the table's own padding and whatever SwiftUI put in the
/// document all count exactly as scrolling counts them. The list is then
/// left at that offset for a number of run-loop turns — rows realised on the
/// way down may change the document — and asked again until two readings
/// agree, at most 8 tries; if none agree, the last reading is returned.
///
/// `overscroll` is what a person sees at the bottom of the list: the distance
/// from the last row's bottom edge to the bottom of the visible area, a
/// bottom content inset included. A list whose rows fill less than the clip view
/// cannot scroll at all and reads `scrollable == false`.
public enum StripedListEnd {

    public struct Reading: CustomStringConvertible {
        public let rows: Int
        public let rowHeight: CGFloat
        public let documentHeight: CGFloat
        public let lastRowMaxY: CGFloat
        public let clipHeight: CGFloat
        public let insetTop: CGFloat
        public let insetBottom: CGFloat
        public let maxOffset: CGFloat
        public let overscroll: CGFloat
        public var scrollable: Bool { maxOffset > -insetTop + 0.5 }

        public var description: String {
            String(format: "rows=%d rowHeight=%.1f doc=%.1f lastRowMaxY=%.1f docBelowLastRow=%.1f clip=%.1f "
                   + "insets=%.1f/%.1f maxOffset=%.1f overscroll=%.1f",
                   rows, rowHeight, documentHeight, lastRowMaxY, documentHeight - lastRowMaxY,
                   clipHeight, insetTop, insetBottom, maxOffset, overscroll)
        }
    }

    /// The rows that are not `Section` headers — a trailing row that stands
    /// for nothing (a spacer, a footer section) counts here and shows up as a
    /// count that is not the fixture's.
    @MainActor
    public static func contentRows(_ table: NSTableView) -> Int {
        (0..<table.numberOfRows).filter {
            table.rowView(atRow: $0, makeIfNecessary: true)?.isGroupRowStyle != true
        }.count
    }

    /// The table under `host` with the most rows — the list being read, not a
    /// console or an inspector that also happens to be a table.
    @MainActor
    public static func table(in host: NSView) -> NSTableView? {
        var found: [NSTableView] = []
        func walk(_ view: NSView) {
            if let table = view as? NSTableView { found.append(table) }
            view.subviews.forEach(walk)
        }
        walk(host)
        return found.max { $0.numberOfRows < $1.numberOfRows }
    }

    /// Scrolls `table` to the furthest offset its clip view allows, lets the
    /// page settle there, and reads.
    @MainActor
    public static func read(_ table: NSTableView, host: NSView, settleTurns: Int = 20) -> Reading? {
        guard let scroll = table.enclosingScrollView, let document = scroll.documentView else { return nil }
        let clip = scroll.contentView
        var last: Reading?
        for _ in 0..<8 {
            let far = NSRect(origin: NSPoint(x: clip.bounds.minX, y: 1_000_000), size: clip.bounds.size)
            let end = clip.constrainBoundsRect(far).origin
            clip.scroll(to: end)
            scroll.reflectScrolledClipView(clip)
            for _ in 0..<settleTurns {
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            }
            let reading = measure(table, scroll: scroll, document: document)
            if let previous = last, abs(previous.maxOffset - reading.maxOffset) < 0.5,
               abs(previous.documentHeight - reading.documentHeight) < 0.5 {
                return reading
            }
            last = reading
        }
        return last
    }

    /// **Where the list rests now, without scrolling it.** The same reading as
    /// `read`, except `overscroll` is taken at the clip view's current origin:
    /// a list left past its end by a change underneath it — the clip view
    /// growing, the document shrinking — shows that space here, and `read`,
    /// which scrolls to the end AppKit allows, would put it back first.
    @MainActor
    public static func resting(_ table: NSTableView) -> (reading: Reading, origin: CGFloat)? {
        guard let scroll = table.enclosingScrollView, let document = scroll.documentView else { return nil }
        let clip = scroll.contentView
        let full = measure(table, scroll: scroll, document: document)
        let origin = clip.bounds.minY
        let visibleBottom = origin + clip.bounds.height
        let atRest = Reading(rows: full.rows, rowHeight: full.rowHeight, documentHeight: full.documentHeight,
                             lastRowMaxY: full.lastRowMaxY, clipHeight: full.clipHeight,
                             insetTop: full.insetTop, insetBottom: full.insetBottom,
                             maxOffset: full.maxOffset, overscroll: visibleBottom - full.lastRowMaxY)
        return (atRest, origin)
    }

    @MainActor
    private static func measure(_ table: NSTableView, scroll: NSScrollView, document: NSView) -> Reading {
        let clip = scroll.contentView
        let insets = clip.contentInsets
        let far = NSRect(origin: NSPoint(x: clip.bounds.minX, y: 1_000_000), size: clip.bounds.size)
        let maxOffset = clip.constrainBoundsRect(far).origin.y
        let rows = table.numberOfRows
        var lastMaxY: CGFloat = 0
        if rows > 0 {
            let rect = table.convert(table.rect(ofRow: rows - 1), to: document)
            lastMaxY = document.isFlipped ? rect.maxY : document.bounds.height - rect.minY
        }
        // The bottom inset is *not* taken off: at the end, whatever the inset
        // reserves is on screen below the last row, and nothing in these pages
        // draws over a list's bottom edge the way the toolbar covers its top.
        let visibleBottom = maxOffset + clip.bounds.height
        return Reading(rows: rows, rowHeight: table.rowHeight, documentHeight: document.frame.height,
                       lastRowMaxY: lastMaxY, clipHeight: clip.bounds.height,
                       insetTop: insets.top, insetBottom: insets.bottom,
                       maxOffset: maxOffset, overscroll: visibleBottom - lastMaxY)
    }
}
