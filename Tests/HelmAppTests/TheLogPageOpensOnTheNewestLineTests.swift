import AppKit
import SwiftUI
import XCTest
@testable import HelmRuntime
import HelmTestSupport
import HelmUI
@testable import HelmApp

/// The Log page with Follow on (its state at every open) is drawn scrolled to
/// the newest line. The scroll view is mounted only once there are lines, a
/// turn after the first read arrived, so a scroll driven by a *change* of the
/// newest line never fires for the lines that were already there.
final class TheLogPageOpensOnTheNewestLineTests: XCTestCase {

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? [] + view.subviews.flatMap(scrollViews(in:))
    }

    @MainActor
    func testAPageOpenedOnALongLogSitsAtItsEnd() throws {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let lines = (0..<400).map { index in
            LogEntry(date: start.addingTimeInterval(Double(index)), level: .info,
                     category: "app", message: "line \(index)")
        }
        let mount = MountedRender(LogView(source: { lines }, storedLog: { false }),
                                  width: 810, height: 700, appearance: .aqua)
        let end = Date().addingTimeInterval(1.5)
        while Date() < end {
            mount.host.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        let scroll = try XCTUnwrap(scrollViews(in: mount.host).first, "the page drew no scroll view")
        let document = try XCTUnwrap(scroll.documentView, "the scroll view holds nothing")
        let visible = scroll.documentVisibleRect
        // The subject first: the list is far taller than the window, so there
        // is somewhere else to be than the end.
        XCTAssertGreaterThan(document.frame.height, visible.height * 3,
                             "the log did not outgrow the window, so the position proves nothing")
        let gap = document.frame.height - visible.maxY
        XCTAssertLessThan(gap, 24, "the page opened \(gap) pt above its newest line")
    }
}
