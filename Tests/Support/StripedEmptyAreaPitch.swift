import AppKit

/// The pitch the empty area below a striped list's last row is actually
/// **painted** at, read off pixels — not `NSTableView.rowHeight`, which is the
/// input to that painting and not its outcome.
///
/// A check that reads `rowHeight` answers "is the number set", which is a
/// claim about a property; what a person sees is the stripe, and the two part
/// company whenever the property is written after the last draw or the
/// painting adds spacing of its own. So the
/// column is photographed from the bottom of the last row down to the bottom
/// of the scroll view, cut into runs of one colour, and the modal length of the
/// runs bounded on both sides is the answer.
///
/// The column sits 30 pt inside the scroll view's leading edge: past the 10 pt
/// inset the stripe is drawn with and past its ~6 pt corner, and left of any
/// row's trailing content.
public enum StripedEmptyAreaPitch {

    public struct Reading: CustomStringConvertible {
        /// Every complete run below the last row, in points.
        public let runs: [CGFloat]
        /// The most frequent complete run, or nil when fewer than two complete
        /// runs fit — too short an empty area to have a pitch at all.
        public let pitch: CGFloat?

        public var description: String {
            "pitch=\(pitch.map { "\($0)" } ?? "nil") runs=\(runs.map { "\($0)" }.joined(separator: ","))"
        }
    }

    @MainActor
    public static func read(_ host: NSView, _ table: NSTableView) -> Reading? {
        guard let scroll = table.enclosingScrollView,
              let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.bitmapData, host.bounds.height > 0 else { return nil }
        let scale = CGFloat(rep.pixelsHigh) / host.bounds.height

        func fromTop(_ rect: NSRect) -> (top: CGFloat, bottom: CGFloat) {
            host.isFlipped ? (rect.minY, rect.maxY)
                           : (host.bounds.height - rect.maxY, host.bounds.height - rect.minY)
        }
        let scrollRect = scroll.convert(scroll.bounds, to: host)
        let scrollSpan = fromTop(scrollRect)
        var start = scrollSpan.top
        if table.numberOfRows > 0 {
            let last = table.convert(table.rect(ofRow: table.numberOfRows - 1), to: host)
            start = fromTop(last).bottom
        }
        let end = scrollSpan.bottom
        let px = Int((scrollRect.minX + 30) * scale)
        guard px >= 0, px < rep.pixelsWide, end > start else { return Reading(runs: [], pitch: nil) }

        var runs: [(key: UInt32, length: Int)] = []
        for y in Int(start * scale)..<min(rep.pixelsHigh, Int(end * scale)) {
            let at = y * rep.bytesPerRow + px * (rep.bitsPerPixel / 8)
            let key = UInt32(data[at]) << 16 | UInt32(data[at + 1]) << 8 | UInt32(data[at + 2])
            if let lastRun = runs.last, lastRun.key == key {
                runs[runs.count - 1].length += 1
            } else {
                runs.append((key, 1))
            }
        }
        // First and last runs are cut by the reading's own bounds.
        let complete = runs.count > 2 ? Array(runs.dropFirst().dropLast()) : []
        let lengths = complete.map { CGFloat($0.length) / scale }
        var counts: [CGFloat: Int] = [:]
        for length in lengths { counts[length, default: 0] += 1 }
        let modal = counts.filter { $0.value >= 2 }
            .max { ($0.value, $0.key) < ($1.value, $1.key) }?.key
        return Reading(runs: lengths, pitch: modal)
    }
}
