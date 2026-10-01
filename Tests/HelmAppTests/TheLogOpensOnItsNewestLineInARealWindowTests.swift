import AppKit
import SwiftUI
import XCTest
@testable import HelmRuntime
import HelmTestSupport
import HelmUI
@testable import HelmApp

/// The Log page with Follow on, opened in a window that is on screen over a
/// tail the size of a real one: it lands on the newest line.
///
/// **Why this file exists, and why the guards before it passed.** The page
/// opened in the middle of yesterday with Follow lit — three times, each time
/// with a guard written against the shape that had just failed. Every one of
/// those guards fed the page rows of one height (`LogPageUnderHand.log`: four
/// hundred lines of «line N», one card). The page's list is lazy: a row that has
/// not been drawn is the height the stack estimates, and a `scrollTo` lands where
/// the estimate puts the end. With every row the same height the estimate is the
/// truth and the landing is exact, so those guards could not see a landing that
/// is wrong when the rows differ.
///
/// **Measured, with the anchor in `LogView.lines` taken out**, on a copy of the
/// owner's tail (1000 lines) in a `MountedRender` 760 pt wide: the real tail
/// opens 7 643 pt above its newest line, at y = 7 684 of a 15 914 pt page — the
/// designer's reading of the settings window was 7 605 of 15 787 — and the same
/// 1000 lines with every message cut to one short line (same levels, same
/// categories) open 12 pt above it, which is the page's own bottom padding, in a
/// window ordered in with the run loop alone turning and in one never ordered in
/// with layout forced between turns alike. So the pump the earlier guards used
/// is not what hid it: the rows' heights are. Here the lines are every height a
/// real log has — one row to a dozen wrapped ones, a heading where a day turns,
/// a site line under a warning — in nine cards, in a window that is ordered in,
/// and nothing but the run loop turns.
///
/// `HELM_LOG_SAMPLE=<folder>` (a copy of `helm.previous.log` and `helm.log`, as
/// in `TheLogCardsHoldOnARealLogTests`) puts the same question to a real tail.
@MainActor
final class TheLogOpensOnItsNewestLineInARealWindowTests: XCTestCase {

    /// The width of the settings window's page at the window's default size,
    /// and a height a laptop gives it.
    private let width: CGFloat = 848
    private let height: CGFloat = 728

    private func scrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for sub in view.subviews { if let found = scrollView(in: sub) { return found } }
        return nil
    }

    /// A thousand lines in the shapes the owner's log holds, from a fixed seed:
    /// nine launches over four days (the first is the tail's head, with no
    /// start line; one is followed by a run after its «terminating»), a start-up
    /// burst after every start, memory samples a few seconds apart, a warning
    /// with a site now and then, a fold of the same line, and a message that
    /// wraps to a dozen rows one line in nine.
    static func ownerShapedTail() -> [LogEntry] {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
        let words = ["network", "state", "changed", "re-reading", "the", "permission", "grant", "for",
                     "accessibility", "was", "not", "found", "so", "this", "module", "is", "not",
                     "watching", "anything", "until", "it", "is", "given", "again", "memory", "sample"]
        func sentence(_ count: Int) -> String {
            (0..<count).map { _ in words[next(words.count)] }.joined(separator: " ")
        }
        let day0 = Date(timeIntervalSince1970: 1_789_000_000)
        var lines: [LogEntry] = []
        var at = day0
        func add(_ level: LogLevel, _ category: String, _ message: String, site: LogSite? = nil) {
            lines.append(LogEntry(date: at, level: level, category: category, message: message, site: site))
        }
        let modules = ["vpn", "memory", "host", "layout", "autopilot", "disk"]
        for launch in 0..<9 {
            if launch > 0 {
                at.addTimeInterval(Double(3_000 + next(40_000)))
                add(.info, "app", "Helm 0.11.1-dev.\(launch) started")
                for module in modules { at.addTimeInterval(0.02); add(.info, "host", "enable \(module)") }
            }
            let count = launch == 0 ? 160 : 100 + next(30)
            for index in 0..<count {
                at.addTimeInterval(Double(1 + next(900)))
                switch next(9) {
                case 0: add(.info, modules[next(modules.count)], sentence(60 + next(130)))
                case 1:
                    add(.warn, "layout", "no accessibility grant — " + sentence(4 + next(6)),
                        site: LogSite(file: "LayoutEngine.swift", line: 100 + next(300), function: "startTap()"))
                case 2 where index % 5 == 0:
                    for _ in 0..<(2 + next(5)) {
                        at.addTimeInterval(1)
                        add(.info, "vpn", "network state changed; re-reading")
                    }
                default: add(.info, modules[next(modules.count)], sentence(3 + next(14)))
                }
            }
            if launch == 5 {
                at.addTimeInterval(30)
                add(.info, "app", "terminating")
                for _ in 0..<12 { at.addTimeInterval(Double(2 + next(60))); add(.info, "memory", sentence(8)) }
            }
        }
        // The tail is a thousand lines at most, and ends at the newest.
        return Array(lines.suffix(HelmLog.tailLimit))
    }

    /// How far the bottom of what is visible is above the end of the list, after
    /// the page has been on screen for `seconds` and nothing but the run loop has
    /// turned.
    private func measure(_ lines: [LogEntry], width: CGFloat, seconds: Double = 6) throws
        -> (gap: CGFloat, document: CGFloat, visible: CGFloat, y: CGFloat, cards: Int) {
        let mount = MountedRender(LogView(source: { lines }, storedLog: { false }),
                                  width: width, height: height, appearance: .aqua)
        defer { mount.window?.orderOut(nil); mount.drop() }
        // On screen, as the settings window is. Nothing below lays out by hand:
        // the run loop is the only thing that turns, which is all a person's
        // window has.
        mount.window?.orderFrontRegardless()
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        let scroll = try XCTUnwrap(scrollView(in: mount.host), "the page drew no scroll view")
        let document = try XCTUnwrap(scroll.documentView, "the scroll view holds nothing")
        let visible = scroll.documentVisibleRect
        let cards = LogPresentation.build(lines, minimumLevel: .info, categories: [], query: "").cards.count
        return (document.frame.height - visible.maxY, document.frame.height, visible.height, visible.minY, cards)
    }

    /// **Every shape, every width: the page lands on the end, not near it.** The
    /// landing is timing-dependent while the page's rows are being measured, so
    /// one reading proves little — on the page as it was, the same fixture at
    /// two widths ended 19 pt and 718 pt short, and a second one 4 403 and 48 pt
    /// short — and the claim is that none of them is. Each is the tail the
    /// owner's log has: the one with days in it, and the same lines all on one
    /// day (no headings), at the widths a settings pane has.
    func testAnOwnerShapedTailOpensOnItsNewestLineInAWindowThatIsOnScreen() throws {
        let owner = Self.ownerShapedTail()
        let now = Date()
        let oneDay = owner.enumerated().map { index, line in
            LogEntry(date: now.addingTimeInterval(Double(index)), level: line.level,
                     category: line.category, message: line.message, site: line.site)
        }
        var short: [String] = []
        for (name, lines) in [("with days", owner), ("one day", oneDay)] {
            for width in [760, 848, 880, 1_000] as [CGFloat] {
                let got = try measure(lines, width: width)
                // The subject first: nine-odd cards, a list many windows tall.
                XCTAssertGreaterThanOrEqual(got.cards, 9, "the fixture is not nine launches")
                XCTAssertGreaterThan(got.document, got.visible * 6,
                                     "the log did not outgrow the window, so the position proves nothing")
                if got.gap > HelmSpace.s5 + 1 {
                    short.append("\(name) at \(Int(width)) pt: \(Int(got.gap)) pt above the newest line "
                                 + "(y = \(Int(got.y)) of \(Int(got.document)) pt, "
                                 + "\(Int(100 * got.y / max(got.document - got.visible, 1))) % of the way)")
                }
            }
        }
        XCTAssertTrue(short.isEmpty, "the page opened short of its newest line — " + short.joined(separator: "; "))
    }

    /// The same question of a real tail — the owner's.
    func testARealTailOpensOnItsNewestLineInAWindowThatIsOnScreen() throws {
        guard let folder = ProcessInfo.processInfo.environment["HELM_LOG_SAMPLE"] else {
            throw XCTSkip("HELM_LOG_SAMPLE names no copy of a real log")
        }
        var seeded: [LogEntry] = []
        for name in ["helm.previous.log", "helm.log"] {
            let url = URL(fileURLWithPath: folder).appendingPathComponent(name)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            seeded += LogSeed.entries(from: text, startedMidFile: false, dated: .distantPast,
                                      using: LogSeed.Stamps())
        }
        let lines = Array(seeded.suffix(HelmLog.tailLimit))
        XCTAssertEqual(lines.count, HelmLog.tailLimit, "the sample is shorter than a full tail")
        var short: [String] = []
        for width in [760, 848, 1_000] as [CGFloat] {
            let got = try measure(lines, width: width)
            XCTAssertGreaterThan(got.document, got.visible * 6,
                                 "the log did not outgrow the window, so the position proves nothing")
            if got.gap > HelmSpace.s5 + 1 {
                short.append("\(Int(width)) pt: \(Int(got.gap)) pt above the newest line "
                             + "(y = \(Int(got.y)) of \(Int(got.document)) pt)")
            }
        }
        XCTAssertTrue(short.isEmpty, "the page opened short of its newest line — " + short.joined(separator: "; "))
    }
}
