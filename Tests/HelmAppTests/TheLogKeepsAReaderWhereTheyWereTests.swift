import AppKit
import SwiftUI
import XCTest
@testable import HelmRuntime
import HelmTestSupport
import HelmUI
@testable import HelmApp

/// The Log page in a window on screen, with a reader who scrolled up to read a
/// line: what moves them, and what must not.
///
/// The page holds its end with `defaultScrollAnchor(_:for: .sizeChanges)` while
/// Follow is lit, and holds a reader who is *not* at the end by the line they
/// read (`LogReaderPlace`), with Follow lit or off. The guards beside this one
/// prove the end is reached; this file asks the other question — where a reader
/// who is not at the end ends up when the page changes under them: a line
/// arriving below as the oldest leaves a full tail, a start-up fold opened under
/// the line they read, the window narrowed so every row above them wraps taller.
/// The cards in these tails are drawn plain (`LogView.lazyAbove`), which is what
/// makes a line's place a reading; a card above that size is lazy and is not
/// covered here.
///
/// **The reader's place is a line they can see**, found by its pixels: one
/// error row (`xmark.octagon.fill`, the only red ink on a page whose other rows
/// are info and warnings) placed as the last line of a launch, with the next
/// launch's header and fold right below it. Its top in the window, before and
/// after, is the reading; nothing here reads a scroll offset and calls it the
/// reader's place, because an offset held while the rows above grow is exactly
/// the page that moved.
@MainActor
final class TheLogKeepsAReaderWhereTheyWereTests: XCTestCase {

    // MARK: - The fixture

    /// The owner-shaped tail with one error line — the landmark — as the last
    /// line of the launch before the seventh start, so the card below it opens
    /// with a start-up fold.
    static func tailWithLandmark(_ base: [LogEntry]) -> [LogEntry] {
        var lines = base
        let starts = lines.indices.filter { lines[$0].category == "app" && lines[$0].message.hasSuffix(" started") }
        let at = starts[min(starts.count - 3, max(1, starts.count * 2 / 3))]
        let landmark = LogEntry(date: lines[at].date.addingTimeInterval(-1), level: .error, category: "disk",
                                message: "LANDMARK — the line the reader is reading")
        lines.insert(landmark, at: at)
        return Array(lines.suffix(HelmLog.tailLimit))
    }

    /// The owner's own tail, with the same landmark, when `HELM_LOG_SAMPLE` names
    /// a copy of it.
    static func realTailWithLandmark() -> [LogEntry]? {
        guard let folder = ProcessInfo.processInfo.environment["HELM_LOG_SAMPLE"] else { return nil }
        var seeded: [LogEntry] = []
        for name in ["helm.previous.log", "helm.log"] {
            let url = URL(fileURLWithPath: folder).appendingPathComponent(name)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            seeded += LogSeed.entries(from: text, startedMidFile: false, dated: .distantPast,
                                      using: LogSeed.Stamps())
        }
        // The owner's errors are red too; the landmark must be the only red.
        let quiet = seeded.suffix(HelmLog.tailLimit).map { line in
            LogEntry(date: line.date, level: line.level == .error ? .warn : line.level,
                     category: line.category, message: line.message, site: line.site)
        }
        return tailWithLandmark(quiet)
    }

    /// The page in a resizable window that is on screen, its toolbar declared
    /// into a channel the test presses, and nothing but the run loop turning.
    @MainActor final class Window {
        let window: NSWindow
        let host: NSHostingView<AnyView>
        let channel = HelmWindowToolbarChannel()
        let source = LogPageUnderHandSource()

        init(_ lines: [LogEntry], width: CGFloat, height: CGFloat = 700) {
            source.lines = lines
            let source = source
            host = NSHostingView(rootView: AnyView(
                LogView(source: { source.lines }, storedLog: { false })
                    .helmMeasuringBench()
                    .environment(\.helmWindowToolbarChannel, channel)))
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .aqua)
            host.appearance = NSAppearance(named: .aqua)
            // The window is the size a person made it; the page does not get
            // to grow it to its own ideal height.
            host.sizingOptions = []
            window.contentView = host
            window.setContentSize(NSSize(width: width, height: height))
            window.orderFrontRegardless()
        }

        func close() { window.orderOut(nil) }

        func pump(_ seconds: Double) {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            }
        }

        var scroll: NSScrollView? { host.everyView(ofType: NSScrollView.self).first }

        /// The view's top and the list's height, for a failure to say what moved.
        func reading() -> String {
            guard let scroll, let document = scroll.documentView else { return "no list" }
            return "top \(Int(scroll.documentVisibleRect.minY)) of \(Int(document.frame.height)) pt"
        }

        func gap() throws -> CGFloat {
            let scroll = try XCTUnwrap(scroll, "the page drew no list")
            let document = try XCTUnwrap(scroll.documentView)
            return document.frame.height - scroll.documentVisibleRect.maxY
        }

        func scroll(toY y: CGFloat) throws {
            let scroll = try XCTUnwrap(scroll)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, y)))
            scroll.reflectScrolledClipView(scroll.contentView)
            pump(0.35)
        }

        func pressFollow() throws {
            let action = try XCTUnwrap(channel.content(for: "log")?.actions.first { $0.id == "follow" },
                                       "the toolbar has no Follow")
            guard case .toggle(_, let perform) = action.kind else {
                return XCTFail("Follow is not a toggle")
            }
            perform()
            pump(0.4)
        }

        func level(_ segment: Int) throws {
            let content = try XCTUnwrap(channel.content(for: "log"))
            let binding = try XCTUnwrap(content.selectedTab)
            binding.wrappedValue = content.tabs[segment].id
            pump(1.5)
        }

        /// The top of the red glyph in the window's content, in points from the
        /// top of the visible list; nil when it is not in view.
        func landmark() -> CGFloat? {
            guard let scroll, let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
            host.cacheDisplay(in: host.bounds, to: rep)
            guard let data = rep.bitmapData, rep.samplesPerPixel == 4, rep.bitsPerSample == 8 else { return nil }
            let scale = CGFloat(rep.pixelsHigh) / host.bounds.height
            let clip = scroll.convert(scroll.contentView.frame, to: host)
            // Host bitmaps are top-down; the host is flipped or not, so take the
            // clip's top in top-down points.
            let top = host.isFlipped ? clip.minY : host.bounds.height - clip.maxY
            let rows = Int(top * scale)..<min(rep.pixelsHigh, Int((top + clip.height) * scale))
            let columns = 0..<min(rep.pixelsWide, Int(160 * scale))
            for y in rows {
                var red = 0
                for x in columns {
                    let at = y * rep.bytesPerRow + x * 4
                    let r = Int(data[at]), g = Int(data[at + 1]), b = Int(data[at + 2]), a = Int(data[at + 3])
                    if a > 200, r > 170, g < 110, b < 110 { red += 1 }
                }
                if red >= 2 { return CGFloat(y) / scale - top }
            }
            return nil
        }

        /// Steps through the list until the landmark is in view, then puts it a
        /// third of the way down.
        func scrollToLandmark() throws -> CGFloat {
            let scroll = try XCTUnwrap(scroll)
            let visible = scroll.documentVisibleRect.height
            var y: CGFloat = 0
            while y < (scroll.documentView?.frame.height ?? 0) {
                try self.scroll(toY: y)
                if let at = landmark() {
                    try self.scroll(toY: scroll.documentVisibleRect.minY + at - visible / 3)
                    pump(0.6)
                    return try XCTUnwrap(landmark(), "the landmark left the view when it was centred")
                }
                y += visible * 0.8
            }
            throw XCTSkip("the landmark was never drawn")
        }

        /// Clicks down the column the fold's words sit in, below `from`, until a
        /// click changes the list's height — the start-up fold opening.
        func openFoldBelow(_ from: CGFloat, through: CGFloat = 260) throws -> Bool {
            let scroll = try XCTUnwrap(scroll)
            let clip = scroll.convert(scroll.contentView.frame, to: nil)
            window.makeKey()
            var y = from + 8
            while y < min(from + through, clip.height - 2) {
                let before = scroll.documentView?.frame.height ?? 0
                let point = NSPoint(x: clip.minX + 70, y: clip.maxY - y)
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                                      timestamp: ProcessInfo.processInfo.systemUptime,
                                                      windowNumber: window.windowNumber, context: nil,
                                                      eventNumber: 0, clickCount: 1, pressure: 1) {
                        window.sendEvent(event)
                    }
                }
                pump(0.25)
                if abs((scroll.documentView?.frame.height ?? 0) - before) > 40 { pump(1.2); return true }
                y += 5
            }
            return false
        }
    }

    // MARK: - What is read

    /// The tails a reader is put into: the owner-shaped one always, the owner's
    /// own when `HELM_LOG_SAMPLE` names a copy.
    private var tails: [(name: String, lines: [LogEntry])] {
        [("owner-shaped", Self.tailWithLandmark(TheLogOpensOnItsNewestLineInARealWindowTests.ownerShapedTail()))]
            + (Self.realTailWithLandmark().map { [("real", $0)] } ?? [])
    }

    /// How far a line the reader can see may drift and still be where they
    /// left it: under a point of rounding, with room for a pixel.
    private let still: CGFloat = 2

    /// The end, as `TheLogOpensOnItsNewestLineInARealWindowTests` reads it: the
    /// page's own bottom padding and a point.
    private let atTheEnd: CGFloat = HelmSpace.s5 + 1

    // MARK: - Follow off

    /// Follow off, scrolled up to a line: a line arriving at the bottom does
    /// not move it — an ordinary one and one that wraps to a dozen rows. The
    /// tail is full, as it is on any Mac that has run the app for a day, so
    /// the oldest line goes as the new one comes, the way `LogTail` rotates.
    func testALineArrivingBelowLeavesTheReaderWhereTheyWere() throws {
        var moved: [String] = []
        for tail in tails {
            for (kind, message) in [("an ordinary line", "network state changed; re-reading"),
                                    ("a long line", String(repeating: "a long line arriving ", count: 120))] {
                for width in [760, 1_000] as [CGFloat] {
                    let page = Window(tail.lines, width: width)
                    defer { page.close() }
                    page.pump(3)
                    try page.pressFollow()
                    let before = try page.scrollToLandmark()
                    let was = page.reading()
                    // The control: the same wait with nothing arriving leaves
                    // the line where it is, so a move below is the arrival's.
                    page.pump(2.5)
                    XCTAssertEqual(page.landmark() ?? -1, before, accuracy: still,
                                   "\(tail.name) at \(Int(width)) pt: the line moved with nothing arriving")
                    page.source.lines = Array((page.source.lines + [LogEntry(
                        date: tail.lines[tail.lines.count - 1].date.addingTimeInterval(5), level: .info,
                        category: "vpn", message: message)]).suffix(HelmLog.tailLimit))
                    page.pump(2.5)
                    let after = page.landmark()
                    if after.map({ abs($0 - before) > still }) ?? true {
                        moved.append("\(tail.name), \(kind), \(Int(width)) pt: line at \(Int(before)) → "
                                     + (after.map { "\(Int($0))" } ?? "out of view")
                                     + " (\(was) → \(page.reading()))")
                    }
                }
            }
        }
        XCTAssertTrue(moved.isEmpty, "with Follow off a line arriving below moved the line being read — "
                      + moved.joined(separator: "; "))
    }

    /// Follow off, a start-up fold opened just below the line being read: the
    /// fold opens downward and the line stays.
    func testAFoldOpenedBelowTheReaderLeavesThemWhereTheyWere() throws {
        try foldOpened(following: false)
    }

    /// The same with Follow still lit — Follow does not go out when a person
    /// scrolls, so this is the ordinary state of a reader who scrolled up.
    func testAFoldOpenedBelowAReaderWhileFollowIsLitLeavesThemWhereTheyWere() throws {
        try foldOpened(following: true)
    }

    private func foldOpened(following: Bool) throws {
        var moved: [String] = []
        var opened = 0
        for tail in tails {
            for width in [760, 1_000] as [CGFloat] {
                let page = Window(tail.lines, width: width)
                defer { page.close() }
                page.pump(3)
                if !following { try page.pressFollow() }
                let before = try page.scrollToLandmark()
                let was = page.reading()
                guard try page.openFoldBelow(before) else { continue }
                opened += 1
                let after = page.landmark()
                if after.map({ abs($0 - before) > still }) ?? true {
                    moved.append("\(tail.name) at \(Int(width)) pt: line at \(Int(before)) → "
                                 + (after.map { "\(Int($0))" } ?? "out of view")
                                 + " (\(was) → \(page.reading()))")
                }
            }
        }
        // The subject: a fold really opened under the reader somewhere.
        XCTAssertGreaterThan(opened, 0, "no click opened a fold, so nothing was asked")
        XCTAssertTrue(moved.isEmpty, "opening a fold below the line being read moved it — "
                      + moved.joined(separator: "; "))
    }

    /// **Follow off, the window narrowed: every row above the reader wraps
    /// taller.** Held at the same offset, the list puts whatever is now at that
    /// offset in front of them — lines from far above the one they were
    /// reading. The narrowings are the ones the settings window gives: the
    /// window from 1000 pt of pane to 760, and the sidebar dragged out to its
    /// widest (180 → 320 pt) on a pane at its default 810. The reader's line
    /// must still be in view, and near where it was.
    func testNarrowingTheWindowKeepsTheLineBeingReadInView() throws {
        var lost: [String] = []
        for tail in tails {
            for (from, to) in [(1_000, 760), (810, 670)] as [(CGFloat, CGFloat)] {
                let page = Window(tail.lines, width: from)
                defer { page.close() }
                page.pump(3)
                try page.pressFollow()
                let before = try page.scrollToLandmark()
                let was = page.reading()
                let visible = try XCTUnwrap(page.scroll).documentVisibleRect.height
                var frame = page.window.frame
                frame.size.width -= from - to
                page.window.setFrame(frame, display: true)
                page.pump(2.5)
                XCTAssertEqual(page.host.bounds.width, to, accuracy: 1, "the window did not narrow")
                let after = page.landmark()
                if after.map({ abs($0 - before) > visible / 4 }) ?? true {
                    lost.append("\(tail.name) \(Int(from)) → \(Int(to)) pt: line at \(Int(before)) pt → "
                                + (after.map { "\(Int($0)) pt" } ?? "out of view")
                                + " (\(was) → \(page.reading()))")
                }
            }
        }
        XCTAssertTrue(lost.isEmpty, "with Follow off a narrower window took the reader away from their line — "
                      + lost.joined(separator: "; "))
    }

    // MARK: - Follow lit

    /// Follow lit, Warnings and back to All: the list comes back several times
    /// taller than it went, and Follow's promise is the newest line in view.
    func testFollowLitThroughWarningsAndBackEndsOnTheNewestLine() throws {
        var short: [String] = []
        for tail in tails {
            for width in [760, 1_000] as [CGFloat] {
                let page = Window(tail.lines, width: width)
                defer { page.close() }
                page.pump(3)
                XCTAssertLessThanOrEqual(try page.gap(), atTheEnd, "\(tail.name) did not open at the end")
                try page.level(1)
                try page.level(0)
                page.pump(2)
                let gap = try page.gap()
                if gap > atTheEnd { short.append("\(tail.name) at \(Int(width)) pt: \(Int(gap)) pt short") }
            }
        }
        XCTAssertTrue(short.isEmpty, "Follow is lit and the newest line is out of view after Warnings → All — "
                      + short.joined(separator: "; "))
    }

    /// Follow off, scrolled to the top, Follow lit again: the press is the
    /// person asking for the newest line.
    func testFollowLitAgainFromTheTopEndsOnTheNewestLine() throws {
        var short: [String] = []
        for tail in tails {
            for width in [760, 1_000] as [CGFloat] {
                let page = Window(tail.lines, width: width)
                defer { page.close() }
                page.pump(3)
                try page.pressFollow()
                try page.scroll(toY: 0)
                try page.pressFollow()
                page.pump(2)
                let gap = try page.gap()
                if gap > atTheEnd { short.append("\(tail.name) at \(Int(width)) pt: \(Int(gap)) pt short") }
            }
        }
        XCTAssertTrue(short.isEmpty, "Follow was pressed back on and the newest line is out of view — "
                      + short.joined(separator: "; "))
    }

    /// Follow lit at the end of a launch that has just begun — its header, its
    /// fold and two lines all in view — and the fold opened: the end stays.
    func testOpeningTheNewestLaunchsFoldWhileFollowingKeepsTheEnd() throws {
        var short: [String] = []
        var opened = 0
        for tail in tails {
            var lines = tail.lines
            var at = lines[lines.count - 1].date.addingTimeInterval(600)
            lines.append(LogEntry(date: at, level: .info, category: "app", message: "Helm 0.11.1-dev.99 started"))
            for module in ["vpn", "memory", "host", "layout", "autopilot", "disk", "hosts", "dock"] {
                at.addTimeInterval(0.02)
                lines.append(LogEntry(date: at, level: .info, category: "host", message: "enable \(module)"))
            }
            for index in 0..<2 {
                at.addTimeInterval(5)
                lines.append(LogEntry(date: at, level: .info, category: "vpn", message: "after the start \(index)"))
            }
            for width in [760, 1_000] as [CGFloat] {
                let page = Window(Array(lines.suffix(HelmLog.tailLimit)), width: width)
                defer { page.close() }
                page.pump(3)
                XCTAssertLessThanOrEqual(try page.gap(), atTheEnd, "\(tail.name) did not open at the end")
                let clip = try XCTUnwrap(page.scroll).documentVisibleRect.height
                guard try page.openFoldBelow(clip - 260, through: 250) else { continue }
                opened += 1
                let gap = try page.gap()
                if gap > atTheEnd { short.append("\(tail.name) at \(Int(width)) pt: \(Int(gap)) pt short") }
            }
        }
        XCTAssertGreaterThan(opened, 0, "no click opened the newest fold, so nothing was asked")
        XCTAssertTrue(short.isEmpty, "opening the newest fold with Follow lit left the end — "
                      + short.joined(separator: "; "))
    }
}
