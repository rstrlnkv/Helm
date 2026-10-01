import AppKit
import XCTest
@testable import HelmRuntime
import HelmTestSupport
@testable import HelmApp

/// `LogReaderPlace` alone, with no page: what the scroll it asks for does to the
/// line it holds.
///
/// The page scrolls by identity — `scrollTo(id, anchor: UnitPoint(0, f))` brings
/// the point `f` of the row's height and the point `f` of the view's height
/// together — so a row `h` tall in a view `V` tall lands with its top at
/// `f · (V − h)` from the view's top. The place remembers the line's distance `d`
/// and asks for `f = d / (V − h)`, clamped to `0...1`. Inside the clamp the line
/// lands back at `d`; outside it — a row whose bottom was below the view when it
/// was remembered, which is what `capture` picks when the top line is tall — it
/// lands at `V − h`, and the hold that was meant to keep the line still moves it.
///
/// What the page does with the fraction is SwiftUI's arithmetic; this file
/// computes the landing from the fraction the place asked for, so it reads the
/// place's own decision. The tall case is a known gap, skipped unless
/// `HELM_KNOWN_GAPS=1`.
@MainActor
final class TheReadersLineLandsWhereItWasTests: XCTestCase {

    private func pump(_ seconds: Double) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
    }

    /// The ordinary case, inside the clamp: the line lands where it was.
    func testAWholeLineInViewLandsBackWhereItWas() {
        let place = LogReaderPlace()
        var asked: [(LogEntry.ID, CGFloat)] = []
        place.following = { false }
        place.scrollToLine = { asked.append(($0, $1)) }
        let visible: CGFloat = 700
        place.scrolled(.init(top: 1_000, visibleHeight: visible, contentHeight: 20_000))
        let above = LogEntry(date: Date(), level: .info, category: "vpn", message: "above")
        let read = LogEntry(date: Date(), level: .info, category: "vpn", message: "read")
        place.rowMoved(above.id, frame: CGRect(x: 0, y: 980, width: 600, height: 40))
        place.rowMoved(read.id, frame: CGRect(x: 0, y: 1_020, width: 600, height: 20))
        pump(0.3)
        // Something above grew by 50 pt; the view stayed.
        place.rowMoved(read.id, frame: CGRect(x: 0, y: 1_070, width: 600, height: 20))
        XCTAssertEqual(asked.count, 1, "precondition: the place asked for the line")
        guard let (id, fraction) = asked.first else { return }
        XCTAssertEqual(id, read.id, "precondition: the held line is the first whole one")
        XCTAssertEqual(fraction * (visible - 20), 20, accuracy: 0.5, "the line does not land where it was")
    }

    /// **The line at the top is tall, and the first line whose top is in view
    /// runs past the bottom.** `capture` picks it, remembers its distance `d`,
    /// and asks for `d / (V − h)` — more than one — which the clamp turns into
    /// one: the line lands with its bottom on the view's bottom, `d − (V − h)`
    /// higher than where the person left it, on the first arrival above it.
    func testATallLineRememberedPastTheBottomLandsWhereItWas() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_KNOWN_GAPS"] == "1",
                          "Known gap log-tall-line: a held line remembered past the view's bottom lands at V − h")
        let place = LogReaderPlace()
        var asked: [(LogEntry.ID, CGFloat)] = []
        place.following = { false }
        place.scrollToLine = { asked.append(($0, $1)) }
        let visible: CGFloat = 700
        place.scrolled(.init(top: 1_000, visibleHeight: visible, contentHeight: 20_000))
        // A line whose top is above the view, then one 500 pt tall that starts
        // 300 pt down the view and so runs 100 pt past its bottom.
        let cut = LogEntry(date: Date(), level: .info, category: "vpn", message: "cut")
        let tall = LogEntry(date: Date(), level: .info, category: "vpn", message: "tall")
        place.rowMoved(cut.id, frame: CGRect(x: 0, y: 900, width: 600, height: 400))
        place.rowMoved(tall.id, frame: CGRect(x: 0, y: 1_300, width: 600, height: 500))
        pump(0.3)
        place.rowMoved(tall.id, frame: CGRect(x: 0, y: 1_350, width: 600, height: 500))
        XCTAssertEqual(asked.count, 1, "precondition: the place asked for the line")
        guard let (id, fraction) = asked.first else { return }
        XCTAssertEqual(id, tall.id, "precondition: the held line is the tall one")
        XCTAssertEqual(fraction * (visible - 500), 300, accuracy: 0.5,
                       "the held line lands \(Int(fraction * (visible - 500))) pt from the view's top, "
                       + "not the 300 pt it was at — the hold moved it")
    }
}
