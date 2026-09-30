import AppKit
import HelmContract
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **The console's inset holds at every width, while lines stream, and for
/// exactly ten lines** — the inputs `TheConsoleTextSitsInsideItsBoxTests` was
/// not fed.
///
/// That file reads a fixed band 2 pt to `consoleInset - 1` pt in from each edge
/// at one width. On the right edge the text is a long line wrapped by
/// character, so where its last glyph ends depends on the width: the remainder
/// after the last whole glyph is anywhere from zero to one advance, and one
/// advance of SF Mono at the console's size is close to the inset itself. With
/// the inset gone, a width whose remainder is large leaves the band empty and
/// the band passes. So this file measures instead of banding: it finds the
/// text's own ink extents inside the well, from one bitmap, and bounds each
/// gap from **both** sides — at least the inset, and no more than the inset
/// plus whatever one glyph can leave — across a run of consecutive widths
/// that covers every remainder a glyph advance can leave, plus the narrowest
/// pane the window allows and a wide one.
///
/// The other states:
///
/// - **streaming**: lines arrive one at a time with only a couple of run-loop
///   turns between, so every `position.scrollTo(edge: .bottom)` interrupts the one before.
///   The newest line is the only wide one, so "the line at the bottom is the
///   newest" is read off its width rather than assumed, and its gap to the
///   box's bottom is bounded from both sides — not in the margin, and not a
///   line short of the end;
/// - **one line**: the smallest console there is, top and left;
/// - **ten lines**: the box is sized for ten, so ten at rest keep the bottom
///   margin clear, and with eleven at rest the same ten are drawn whole while
///   the eleventh is cut by the clip at the inset — never drawn into it;
/// - **scrolled part way**: the scroll view moved to offsets that are not a
///   multiple of the line pitch, so a line is cut at the top and one at the
///   bottom; all four gaps are read, at the narrowest pane, the default and a
///   wide one, because the clip is the only thing holding the inset there;
/// - **following**: the console's scroll offset is read against the end of its
///   content — a page mounted over lines opens at the last, a full console
///   follows an arrival that leaves the count where it was, and a person who
///   scrolled up is left where they are until they come back to the end.
@MainActor
final class TheConsoleTextSitsInsideItsBoxEverywhereTests: XCTestCase {

    private final class Cellar: EngineTransport, @unchecked Sendable {
        let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }

        func send(_ command: EngineCommand) async throws -> Data {
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(
                    BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            case .listInstalled: return try JSONEncoder().encode([BrewPackage]())
            case .outdated: return try JSONEncoder().encode([OutdatedPackage]())
            case .descriptions: return try JSONEncoder().encode([String: String]())
            case .doctor: return try JSONEncoder().encode([DoctorIssue]())
            default: return Data()
            }
        }

        func say(_ line: String) {
            stream.continuation.yield(
                EngineEvent(name: HomebrewEvent.opLog.rawValue, payload: Data(line.utf8)))
        }
    }

    private var renders: [MountedRender] = []

    override func tearDown() {
        renders.forEach { $0.drop() }
        renders = []
        super.tearDown()
    }

    private let inset = HomebrewSettingsPage.consoleInset

    /// One advance of the console's face: the most a character wrap can leave
    /// between the last glyph and the end of the text column.
    private var advance: CGFloat {
        let face = NSFont.monospacedSystemFont(
            ofSize: NSFont.preferredFont(forTextStyle: .subheadline).pointSize, weight: .regular)
        return ("=" as NSString).size(withAttributes: [.font: face]).width
    }

    private func page(_ lines: [String], width: CGFloat, appearance: NSAppearance.Name)
        async -> (Cellar, HomebrewViewModel, MountedRender) {
        let transport = Cellar()
        let mvm = ModuleViewModel(transport: transport)
        let hb = HomebrewViewModel.shared(vm: mvm)
        await hb.loadIfNeeded()
        hb.select(nil)
        hb.segment = .installed
        hb.clearConsole()
        for line in lines { transport.say(line) }
        await drain(hb, until: lines.count)
        let mount = MountedRender(HomebrewSettingsPage(vm: mvm),
                                  width: width, height: 700, appearance: appearance)
        renders.append(mount)
        mount.settle(60)
        return (transport, hb, mount)
    }

    /// Waits for the model to hold `count` lines — the subject, never an
    /// absence — and fails in its own words if it never does.
    private func drain(_ hb: HomebrewViewModel, until count: Int,
                       last marker: String? = nil) async {
        var yields = 0
        func done() -> Bool {
            hb.consoleLines.count == count && (marker == nil || hb.consoleLines.last == marker)
        }
        while !done() && yields < 200_000 {
            await Task.yield()
            yields += 1
        }
        XCTAssertTrue(done(), "the lines never all reached the model: \(hb.consoleLines.count)")
    }

    /// The console's well, in points from the top of the host.
    private func box(_ mount: MountedRender) throws -> CGRect {
        guard let root = mount.host.layer else { throw XCTSkip("no layer tree") }
        var found: [CGRect] = []
        func walk(_ layer: CALayer) {
            if layer.cornerRadius > 0.01, layer.bounds.height > 100 {
                found.append(layer.convert(layer.bounds, to: root))
            }
            layer.sublayers?.forEach(walk)
        }
        walk(root)
        XCTAssertEqual(found.count, 1, "\(found.count) block-sized wells drew, the console is one")
        let frame = try XCTUnwrap(found.first)
        let top = root.isGeometryFlipped ? frame.minY : mount.host.bounds.height - frame.maxY
        return CGRect(x: frame.minX, y: top, width: frame.width, height: frame.height)
    }

    /// Where the text's ink sits inside the well, as gaps in points from each
    /// edge of the box. Left and right are read on the rows clear of the
    /// rounded corners, top and bottom on the columns clear of them; the box's
    /// own antialiased edge (1.5 pt) is never read. `newest` is the rightmost
    /// ink of the lowest run of inked rows, as a gap from the right edge.
    private struct Gaps {
        let top: CGFloat, bottom: CGFloat, left: CGFloat, right: CGFloat, newest: CGFloat
        /// Each run of inked rows as top–bottom in points from the box's top,
        /// for a failure to say where the lines actually fell.
        let lines: String
        /// The same runs as heights in points, top to bottom.
        let heights: [CGFloat]
    }

    private func gaps(_ mount: MountedRender, box: CGRect) throws -> Gaps {
        let view = mount.host
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let data = try XCTUnwrap(rep.bitmapData)
        XCTAssertEqual(rep.samplesPerPixel, 4)
        let scale = CGFloat(max(1, rep.pixelsHigh / max(1, Int(view.bounds.height))))
        func px(_ v: CGFloat) -> Int { Int((v * scale).rounded()) }
        let edge: CGFloat = 1.5
        let corner = HelmRadius.card + 1
        let allRows = px(box.minY + edge)..<px(box.maxY - edge)
        let allColumns = px(box.minX + edge)..<px(box.maxX - edge)
        // The well's fill: the commonest pixel inside it.
        var counts: [UInt32: Int] = [:]
        for y in stride(from: allRows.lowerBound, to: allRows.upperBound, by: 3) {
            for x in stride(from: allColumns.lowerBound, to: allColumns.upperBound, by: 3) {
                let at = y * rep.bytesPerRow + x * 4
                var key: UInt32 = 0
                for c in 0..<4 { key = key << 8 | UInt32(data[at + c]) }
                counts[key, default: 0] += 1
            }
        }
        let modal = try XCTUnwrap(counts.max { ($0.value, $0.key) < ($1.value, $1.key) }?.key)
        let ground = (0..<4).reversed().map { Int(modal >> UInt32($0 * 8) & 255) }
        func inked(_ x: Int, _ y: Int) -> Bool {
            let at = y * rep.bytesPerRow + x * 4
            return (0..<4).contains { abs(Int(data[at + $0]) - ground[$0]) > 40 }
        }
        // Left and right, on the rows clear of the corners.
        var left = Int.max, right = Int.min
        for y in px(box.minY + corner)..<px(box.maxY - corner) {
            for x in allColumns where inked(x, y) {
                left = min(left, x)
                right = max(right, x)
            }
        }
        // Top, bottom and the lowest line, on the columns clear of the corners.
        let middle = px(box.minX + corner)..<px(box.maxX - corner)
        var rows: [Int: Int] = [:]
        for y in allRows {
            for x in middle where inked(x, y) { rows[y] = max(rows[y] ?? x, x) }
        }
        let inkedRows = rows.keys.sorted()
        guard let first = inkedRows.first, let last = inkedRows.last, left <= right else {
            XCTFail("no text drew inside the console's well, so no gap can be read")
            throw XCTSkip("nothing drew")
        }
        // The lowest line: its bottom 3 pt of ink, which no line above it
        // reaches however tightly the lines are set.
        let newestRight = inkedRows.filter { $0 > last - px(3) }.compactMap { rows[$0] }.max() ?? 0
        var runs: [String] = []
        var heights: [CGFloat] = []
        var start = first
        for (row, next) in zip(inkedRows, inkedRows.dropFirst() + [Int.max]) where next != row + 1 {
            runs.append(String(format: "%.1f–%.1f", CGFloat(start) / scale - box.minY,
                               CGFloat(row + 1) / scale - box.minY))
            heights.append(CGFloat(row + 1 - start) / scale)
            start = next
        }
        return Gaps(top: CGFloat(first) / scale - box.minY,
                    bottom: box.maxY - CGFloat(last + 1) / scale,
                    left: CGFloat(left) / scale - box.minX,
                    right: box.maxX - CGFloat(right + 1) / scale,
                    newest: box.maxX - CGFloat(newestRight + 1) / scale,
                    lines: "box \(box.height) pt, ink rows " + runs.joined(separator: ", "),
                    heights: heights)
    }

    /// A gap is the inset, give or take what a glyph leaves. Below the floor
    /// the text is in the margin; above the ceiling the text is not where the
    /// layout put it.
    private func assertGap(_ gap: CGFloat, _ edge: String, ceiling: CGFloat,
                           _ context: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(gap, inset - 0.5, """
            \(context): the text reaches into the console's \(inset) pt \(edge) margin — \
            its ink is \(gap) pt from the box
            """, file: file, line: line)
        XCTAssertLessThanOrEqual(gap, ceiling, """
            \(context): the text sits \(gap) pt from the box's \(edge) edge, more than the \
            \(inset) pt inset plus what a glyph leaves (\(ceiling) pt)
            """, file: file, line: line)
    }

    /// Consecutive widths covering every remainder one advance can leave, the
    /// narrowest pane (860 window, 320 sidebar) and a wide one.
    private var widths: [CGFloat] {
        let steps = Int(advance.rounded(.up)) + 1
        return (0..<steps).map { 540 + CGFloat($0) } + [984, 1600]
    }

    func testTheRightMarginHoldsAtEveryWidthTheWrapCanLeave() async throws {
        let wide = String(repeating: "=", count: 600)
        for appearance in RenderedInk.bothAppearances {
            for width in widths {
                let (_, _, mount) = await page(["==> Pouring gwlpy", wide, "==> Done"],
                                               width: width, appearance: appearance)
                let box = try box(mount)
                let gaps = try gaps(mount, box: box)
                let context = "\(RenderedInk.label(of: appearance)), \(Int(width)) pt"
                assertGap(gaps.right, "right", ceiling: inset + advance + 1, context)
                assertGap(gaps.left, "left", ceiling: inset + advance + 1, context)
                renders.removeLast().drop()
            }
        }
    }

    func testOneLineSitsAtTheInsetFromTheTopAndTheLeft() async throws {
        for appearance in RenderedInk.bothAppearances {
            let (_, _, mount) = await page([String(repeating: "|", count: 60)],
                                           width: 984, appearance: appearance)
            let box = try box(mount)
            let gaps = try gaps(mount, box: box)
            let context = "\(RenderedInk.label(of: appearance)), one line"
            assertGap(gaps.top, "top", ceiling: inset + 3, context)
            assertGap(gaps.left, "left", ceiling: inset + advance + 1, context)
        }
    }

    /// The newest line is the only wide one; it must be the lowest line drawn,
    /// and sit at the inset from the bottom — not in the margin, not a line
    /// short of the end.
    func testTheNewestLineSitsAtTheInsetFromTheBottomWhileLinesStream() async throws {
        let short = "|"
        let newest = String(repeating: "|", count: 120)
        for appearance in RenderedInk.bothAppearances {
            let (transport, hb, mount) = await page([short], width: 984, appearance: appearance)
            for index in 1..<30 {
                let line = index == 29 ? newest : short
                transport.say(line)
                await drain(hb, until: index + 1, last: line)
                mount.settle(2)
            }
            mount.settle(80)
            let box = try box(mount)
            let gaps = try gaps(mount, box: box)
            let context = "\(RenderedInk.label(of: appearance)), streamed"
            XCTAssertLessThan(gaps.newest, box.width / 2, """
                \(context): the lowest line drawn is not the newest — the console \
                stopped short of the end of what it was given
                """)
            assertGap(gaps.bottom, "bottom", ceiling: inset + 5, context)
            // Scrolled to the end, the oldest visible line is cut by the top
            // of the clip: at the inset, never in it.
            assertGap(gaps.top, "top", ceiling: inset + lineHeight(gaps) + HelmSpace.s1 + 1,
                      "\(context) (\(gaps.lines))")
            assertGap(gaps.left, "left", ceiling: inset + advance + 1, context)
        }
    }

    /// **At its bound the count stops changing, and the count is what
    /// scrolls.** `consoleLimit` keeps the newest lines by dropping the oldest,
    /// so from the thousandth line on every arrival leaves
    /// `consoleLines.count` where it was. A page mounted over a full console —
    /// coming back to it during a long `brew upgrade`, or the window idling
    /// off screen and back — opens at the top and nothing ever moves it again:
    /// the newest line is never the one on screen.
    func testTheNewestLineReachesTheBottomOnceTheConsoleIsFull() async throws {
        let limit = HomebrewViewModel.consoleLimit
        let newest = String(repeating: "|", count: 120)
        // The control: one line short of the bound the arrival changes the
        // count, and the same reading finds the newest line at the bottom.
        let (shortOfIt, below, control) = await page(Array(repeating: "|", count: limit - 1),
                                                     width: 984, appearance: .aqua)
        shortOfIt.say(newest)
        await drain(below, until: limit, last: newest)
        control.settle(80)
        let controlGaps = try gaps(control, box: try box(control))
        XCTAssertLessThan(controlGaps.newest, try box(control).width / 2,
                          "control: a count that changes did not scroll to the newest line")
        renders.removeLast().drop()

        let (transport, hb, mount) = await page(Array(repeating: "|", count: limit),
                                                width: 984, appearance: .aqua)
        transport.say(newest)
        await drain(hb, until: limit, last: newest)
        mount.settle(80)
        let box = try box(mount)
        let gaps = try gaps(mount, box: box)
        XCTAssertLessThan(gaps.newest, box.width / 2, """
            light, full console: the lowest line drawn is not the newest — at \(limit) \
            lines the count no longer changes, so nothing scrolls to the end
            """)
        assertGap(gaps.bottom, "bottom", ceiling: inset + 5, "light, full console")
    }

    /// A whole line's ink: the tallest run drawn. A line cut by the clip is
    /// shorter, never taller.
    private func lineHeight(_ gaps: Gaps) -> CGFloat { gaps.heights.max() ?? 0 }

    /// The box is sized for ten lines: ten at rest leave the bottom margin
    /// clear. With eleven at rest nothing has scrolled (the count did not
    /// change after the page mounted), so the same ten are drawn whole and the
    /// eleventh is below the clip — which sits at the inset, so no ink reaches
    /// within the inset of the bottom edge.
    func testTenLinesFitInsideTheMarginAndAnEleventhDoesNot() async throws {
        let line = String(repeating: "|", count: 60)
        for appearance in RenderedInk.bothAppearances {
            let label = RenderedInk.label(of: appearance)
            let shown = HomebrewSettingsPage.consoleLinesShown
            let (_, _, ten) = await page(Array(repeating: line, count: shown),
                                         width: 984, appearance: appearance)
            let tenGaps = try gaps(ten, box: try box(ten))
            assertGap(tenGaps.bottom, "bottom", ceiling: inset + 5,
                      "\(label), \(shown) lines (\(tenGaps.lines))")
            assertGap(tenGaps.top, "top", ceiling: inset + 3, "\(label), \(shown) lines")
            XCTAssertEqual(tenGaps.heights.count, shown,
                           "\(label): \(shown) lines drew as \(tenGaps.lines)")

            let (_, _, eleven) = await page(Array(repeating: line, count: shown + 1),
                                            width: 984, appearance: appearance)
            let elevenGaps = try gaps(eleven, box: try box(eleven))
            let context = "\(label), \(shown + 1) lines at rest (\(elevenGaps.lines))"
            XCTAssertEqual(elevenGaps.heights.count, shown, """
                \(context): \(shown) lines are what the box shows, and the eleventh \
                must be wholly below the clip
                """)
            let whole = lineHeight(tenGaps)
            for (index, height) in elevenGaps.heights.enumerated() {
                XCTAssertEqual(height, whole, accuracy: 0.51, """
                    \(context): line \(index + 1) drew \(height) pt of ink where a whole \
                    line draws \(whole) — it is cut
                    """)
            }
            assertGap(elevenGaps.bottom, "bottom", ceiling: inset + 5, context)
        }
    }

    /// **Scrolled part way, all four edges.** The console's scroll view is
    /// moved to offsets that step through one line pitch, so at each a line
    /// is cut at the top and another at the bottom — by the clip, which has
    /// to sit at the inset. Every line wraps across the full width, so left
    /// and right are read on the same drawing. Before the gaps, each offset
    /// is read back off the clip view and at least one offset must have cut a
    /// line, so a scroll that never happened cannot pass as a clear margin.
    func testEveryEdgeKeepsTheInsetWithTheConsoleScrolledPartWay() async throws {
        let line = String(repeating: "|", count: 400)
        for appearance in RenderedInk.bothAppearances {
            for width: CGFloat in [540, 860, 984, 1600] {
                let (_, _, mount) = await page(Array(repeating: line, count: 12),
                                               width: width, appearance: appearance)
                let box = try box(mount)
                let scrolls = mount.host.everyView(ofType: NSScrollView.self).filter {
                    let frame = $0.convert($0.bounds, to: mount.host)
                    let documentHeight = $0.documentView?.frame.height ?? 0
                    return frame.height < box.height + 1 && frame.width < box.width + 1
                        && documentHeight > frame.height + 100
                }
                let label = "\(RenderedInk.label(of: appearance)), \(Int(width)) pt"
                XCTAssertEqual(scrolls.count, 1, "\(label): \(scrolls.count) console scroll views")
                let scroll = try XCTUnwrap(scrolls.first)
                let pitch = lineHeight(try gaps(mount, box: box)) + HelmSpace.s1
                var cut = false
                for step in 0..<4 {
                    let offset = 60 + CGFloat(step) * 4.25
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: offset))
                    scroll.reflectScrolledClipView(scroll.contentView)
                    mount.settle(10)
                    XCTAssertEqual(scroll.contentView.bounds.origin.y, offset, accuracy: 0.5,
                                   "\(label): the console did not stay scrolled to \(offset)")
                    let gaps = try gaps(mount, box: box)
                    let context = "\(label), scrolled \(offset) pt (\(gaps.lines))"
                    if gaps.heights.contains(where: { $0 < lineHeight(gaps) - 1 }) { cut = true }
                    assertGap(gaps.top, "top", ceiling: inset + pitch + 1, context)
                    assertGap(gaps.bottom, "bottom", ceiling: inset + pitch + 1, context)
                    assertGap(gaps.left, "left", ceiling: inset + advance + 1, context)
                    // A bar's ink sits mid-advance, so the right edge carries the
                    // side bearing the left gap shows on top of the wrap's
                    // remainder.
                    assertGap(gaps.right, "right", ceiling: gaps.left + advance + 1, context)
                }
                XCTAssertTrue(cut, "\(label): no offset cut a line, so no clip was read")
                renders.removeLast().drop()
            }
        }
    }

    // MARK: - Following the newest line

    /// The console's own scroll view — the one whose content is taller than
    /// its box — and where its offset stands against the end of the content.
    private func consoleScroll(_ mount: MountedRender, box: CGRect) throws -> NSScrollView {
        let scrolls = mount.host.everyView(ofType: NSScrollView.self).filter {
            let frame = $0.convert($0.bounds, to: mount.host)
            let documentHeight = $0.documentView?.frame.height ?? 0
            return frame.height < box.height + 1 && frame.width < box.width + 1
                && documentHeight > frame.height + 100
        }
        XCTAssertEqual(scrolls.count, 1, "\(scrolls.count) console scroll views")
        return try XCTUnwrap(scrolls.first)
    }

    /// Points of content below the visible bottom edge: zero at the end.
    private func hidden(below scroll: NSScrollView) -> CGFloat {
        let content = scroll.documentView?.frame.height ?? 0
        return content - scroll.contentView.bounds.height - scroll.contentView.bounds.origin.y
    }

    /// The person's own scroll: a wheel event handed to the scroll view, the
    /// way the window would, so SwiftUI's own record of the offset moves with
    /// it. Moving the clip view directly leaves that record behind, and the
    /// next update puts the offset back.
    private func wheel(_ scroll: NSScrollView, up points: Int32, _ mount: MountedRender) throws {
        let source = CGEventSource(stateID: .privateState)
        let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 1,
                                       wheel1: points, wheel2: 0, wheel3: 0))
        scroll.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: cg)))
        mount.settle(20)
    }

    /// **A page mounted over lines opens at the last of them**, whatever the
    /// count is — the mount is what a return to the page, or the window coming
    /// back from hidden, is.
    func testAPageMountedOverManyLinesOpensAtTheLastOfThem() async throws {
        let (_, _, mount) = await page(Array(repeating: "|", count: 60),
                                       width: 984, appearance: .aqua)
        let box = try box(mount)
        let scroll = try consoleScroll(mount, box: box)
        XCTAssertEqual(hidden(below: scroll), 0, accuracy: 1.5,
                       "a console mounted over 60 lines opened with lines below the box")
        XCTAssertGreaterThan(scroll.contentView.bounds.origin.y, 100, "the console never scrolled")
    }

    /// **A full console keeps following, with no remount.** Every arrival at
    /// the bound drops the oldest line, so `consoleLines.count` stays at
    /// `consoleLimit`; the arrival here is several rows tall, so the content
    /// grows under a scroll view that is already at the end and only a follow
    /// keyed to the newest line's identity moves it down.
    func testAFullConsoleFollowsTheNewestLineWithoutARemount() async throws {
        let limit = HomebrewViewModel.consoleLimit
        let (transport, hb, mount) = await page(Array(repeating: "|", count: limit),
                                                width: 984, appearance: .aqua)
        let box = try box(mount)
        let scroll = try consoleScroll(mount, box: box)
        XCTAssertEqual(hidden(below: scroll), 0, accuracy: 1.5, "precondition: opened at the end")
        var newest = ""
        for index in 0..<5 {
            newest = String(repeating: "=", count: 600 + index)
            transport.say(newest)
            await drain(hb, until: limit, last: newest)
            mount.settle(60)
            XCTAssertEqual(hb.consoleLines.count, limit, "the count moved, so this is not the bound")
            XCTAssertEqual(hidden(below: scroll), 0, accuracy: 1.5, """
                arrival \(index + 1) at the bound: \(hidden(below: scroll)) pt of the newest \
                line is below the box
                """)
        }
    }

    /// **Scrolled up is not yanked down.** A person reading earlier output
    /// keeps their place while lines arrive, and a console that follows the
    /// newest line again once they come back to the end.
    func testAConsoleScrolledUpIsNotYankedDownUntilItIsScrolledBack() async throws {
        let (transport, hb, mount) = await page(Array(repeating: "|", count: 60),
                                                width: 984, appearance: .aqua)
        let box = try box(mount)
        let scroll = try consoleScroll(mount, box: box)
        let end = scroll.contentView.bounds.origin.y
        XCTAssertGreaterThan(end, 200, "precondition: 60 lines are taller than the box")

        try wheel(scroll, up: 600, mount)
        let held = scroll.contentView.bounds.origin.y
        XCTAssertLessThan(held, end - 300, "precondition: the wheel did not scroll the console up")
        for index in 60..<66 {
            transport.say("|")
            await drain(hb, until: index + 1)
            mount.settle(40)
        }
        XCTAssertEqual(scroll.contentView.bounds.origin.y, held, accuracy: 0.5, """
            six lines arrived while the console was scrolled up, and it moved from \
            \(held) to \(scroll.contentView.bounds.origin.y)
            """)

        // Back at the end by the person's own scroll: following resumes.
        try wheel(scroll, up: -5000, mount)
        XCTAssertEqual(hidden(below: scroll), 0, accuracy: 1.5, "precondition: scrolled back to the end")
        let newest = String(repeating: "=", count: 600)
        transport.say(newest)
        await drain(hb, until: 67, last: newest)
        mount.settle(60)
        XCTAssertEqual(hidden(below: scroll), 0, accuracy: 1.5,
                       "back at the end the console stopped following the newest line")
    }

    // MARK: - The place held at the bound, and the follow at speed

    /// One row's pitch in a console of single-line rows: the document over the
    /// count. The inset sits outside the scroll view and the document is only
    /// the rows' stack, so the quotient is a hair under the pitch (the spacing
    /// is counted between rows, one fewer than the rows) and a test of half a
    /// pitch does not feel it.
    private func pitch(_ scroll: NSScrollView, rows: Int) -> CGFloat {
        (scroll.documentView?.frame.height ?? 0) / CGFloat(rows)
    }

    /// Says `lines` at the bound, one at a time, each read into the model
    /// before the next and the page given `turns` turns to move.
    private func arrive(_ lines: [String], _ transport: Cellar, _ hb: HomebrewViewModel,
                        _ mount: MountedRender, turns: Int) async {
        for line in lines {
            transport.say(line)
            await drain(hb, until: HomebrewViewModel.consoleLimit, last: line)
            mount.settle(turns)
        }
    }

    /// **What a person is reading stays where it is, at the bound.** At
    /// `consoleLimit` every arrival drops the oldest line from the top, so
    /// holding the *offset* slides the text down the box one row per arrival
    /// (`Removing…ffmpeg` went from 104 pt to 8 pt in six lines). What holds is
    /// the line: the content above it shrank by the six rows dropped, so the
    /// offset has to shrink by the same, which is read here as an offset that
    /// moved up by six pitches.
    func testTheLineBeingReadStaysPutWhileTheBoundTrimsAboveIt() async throws {
        let limit = HomebrewViewModel.consoleLimit
        let (transport, hb, mount) = await page(Array(repeating: "|", count: limit),
                                                width: 984, appearance: .aqua)
        let scroll = try consoleScroll(mount, box: try box(mount))
        let pitch = pitch(scroll, rows: limit)
        try wheel(scroll, up: 4000, mount)
        let held = scroll.contentView.bounds.origin.y
        XCTAssertGreaterThan(held, 8 * pitch, "precondition: the wheel left no room above")
        XCTAssertGreaterThan(hidden(below: scroll), 100 * pitch, "precondition: not near the end")
        await arrive((1...6).map { "arrival \($0)" }, transport, hb, mount, turns: 30)
        let now = scroll.contentView.bounds.origin.y
        XCTAssertEqual(held - now, 6 * pitch, accuracy: pitch / 2, """
            six lines were trimmed above the line being read; the offset moved from \(held) \
            to \(now), so the text slid \((6 * pitch - (held - now)) / pitch) rows
            """)
    }

    /// **When the line being read is itself trimmed away**, the console shows
    /// the oldest lines that are left: the top of what remains, and nothing
    /// else — neither the end (the person had not asked for it) nor an offset
    /// past the top.
    func testWhenTheLineBeingReadIsTrimmedTheTopOfWhatRemainsShows() async throws {
        let limit = HomebrewViewModel.consoleLimit
        let (transport, hb, mount) = await page(Array(repeating: "|", count: limit),
                                                width: 984, appearance: .aqua)
        let scroll = try consoleScroll(mount, box: try box(mount))
        let pitch = pitch(scroll, rows: limit)
        try wheel(scroll, up: 200_000, mount)
        XCTAssertEqual(scroll.contentView.bounds.origin.y, 0, accuracy: 1, "precondition: at the top")
        try wheel(scroll, up: -Int32(2 * pitch), mount)
        let held = scroll.contentView.bounds.origin.y
        XCTAssertTrue(held > 0.5 * pitch && held < 4 * pitch,
                      "precondition: two rows or so from the top, at \(held)")
        await arrive((1...6).map { "arrival \($0)" }, transport, hb, mount, turns: 30)
        XCTAssertEqual(scroll.contentView.bounds.origin.y, 0, accuracy: 1, """
            the line being read was trimmed away and the console is at \
            \(scroll.contentView.bounds.origin.y), not at the top of what is left
            """)
        XCTAssertGreaterThan(hidden(below: scroll), 100 * pitch, "the console jumped to the end")
    }

    /// **Following lands on the newest line while lines arrive at a stream's
    /// pace**, and does not animate through the backlog. About a hundred lines
    /// a second at the bound, the box's bottom is read after every arrival: an
    /// animated scroll per line restarts each time and leaves the view thousands
    /// of points behind before it catches up.
    func testFollowingAFastStreamNeverFallsFarBehindTheNewestLine() async throws {
        let limit = HomebrewViewModel.consoleLimit
        let (transport, hb, mount) = await page(Array(repeating: "|", count: limit),
                                                width: 984, appearance: .aqua)
        let scroll = try consoleScroll(mount, box: try box(mount))
        let pitch = pitch(scroll, rows: limit)
        XCTAssertEqual(hidden(below: scroll), 0, accuracy: 1.5, "precondition: opened at the end")
        var worst: CGFloat = 0
        for index in 0..<150 {
            let line = String(repeating: "=", count: 200 + index)
            transport.say(line)
            await drain(hb, until: limit, last: line)
            mount.settle(1)
            worst = max(worst, hidden(below: scroll))
        }
        XCTAssertGreaterThan(hb.consoleSequence, limit + 149, "the stream never arrived")
        XCTAssertLessThan(worst, 12 * pitch, """
            following fell \(worst) pt (\(worst / pitch) rows) behind the newest line \
            during a fast stream
            """)
        mount.settle(80)
        XCTAssertEqual(hidden(below: scroll), 0, accuracy: 1.5, "the stream ended short of the end")
    }
}
