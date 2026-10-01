import AppKit
import SwiftUI
import XCTest
@testable import HelmRuntime
import HelmTestSupport
import HelmUI
@testable import HelmApp

/// A warning or an error row says what it is by a wash behind the row, a glyph
/// and an accessibility value — and not by a bar at its left edge. The owner
/// picked the direction without the bar (the orange band down the left of every
/// warning card read as a second, louder signal over the one the fill already
/// gave), so a row's left edge is the same wash as the rest of the row.
@MainActor
final class TheLogRowCarriesItsLevelWithoutAStripTests: XCTestCase {

    private func row(_ level: LogLevel) -> LogPresentation.Row {
        let entry = LogEntry(date: Date(timeIntervalSince1970: 1_790_000_000), level: level,
                             category: "layout", message: "no accessibility grant — not watching")
        return LogPresentation.Row(lines: [entry], heading: nil)
    }

    /// The pixel at a point of the row, as four bytes (premultiplied).
    private func pixel(_ level: LogLevel, atX x: Int, appearance: NSAppearance.Name) throws -> [UInt8] {
        let mount = MountedRender(LogRowView(row: row(level)), width: 600, height: 24, appearance: appearance)
        defer { mount.drop() }
        mount.settle(10)
        let host = mount.host
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let data = try XCTUnwrap(rep.bitmapData)
        let scale = max(1, rep.pixelsWide / max(1, Int(host.bounds.width)))
        // A frame as tall as the row is: its middle is inside it.
        let y = rep.pixelsHigh / 2
        let at = y * rep.bytesPerRow + x * scale * 4
        return (0..<4).map { data[at + $0] }
    }

    func testAWarningAndAnErrorRowHaveNoBarAtTheirLeftEdge() throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for level in [LogLevel.warn, .error] {
                let edge = try pixel(level, atX: 1, appearance: appearance)
                let inside = try pixel(level, atX: 8, appearance: appearance)
                let plain = try pixel(.info, atX: 8, appearance: appearance)
                // The subject first: the wash is there, or an empty render would
                // read as «no bar» for free.
                XCTAssertNotEqual(inside, plain, "\(level) in \(appearance.rawValue): the row draws no wash at all")
                let far = zip(edge, inside).map { abs(Int($0) - Int($1)) }.max() ?? 0
                XCTAssertLessThanOrEqual(far, 2, """
                    \(level) in \(appearance.rawValue): the row's left edge is \(edge) and the wash \
                    inside it is \(inside) — a bar stands at the edge
                    """)
            }
        }
    }
}
