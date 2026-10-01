import AppKit
import SwiftUI
import XCTest
@testable import HelmRuntime
import HelmTestSupport
import HelmUI
@testable import HelmApp

/// The Log page's Follow and its day headings, driven through the page's own
/// controls — the window's toolbar — rather than through a function beside it.
///
/// The page opened on its oldest line with Follow lit, and was repaired by
/// scrolling when the list's scroll view appears. Follow is one promise — the
/// newest line is in view while the control is lit — and the page reaches that
/// scroll view by more than one road. The roads through the page's own controls
/// are here; the two that leave no new line to trigger a move are in
/// `TheLogFollowsWithoutANewLineTests`.
final class TheLogPageFollowsThroughItsFiltersTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    // MARK: - Follow

    /// Off means off: a line arriving leaves the reader where they scrolled to.
    /// Then the other half, in the same page, so the press and the arrival are
    /// both proved to reach it — back on, the next line brings the view down.
    @MainActor
    func testFollowOffKeepsThePositionAndFollowOnFollowsTheNextLine() throws {
        let source = LogPageUnderHand.log()
        let page = LogPageUnderHand(source)
        defer { page.close() }
        page.pump(1.5)
        XCTAssertLessThan(try page.gap(), 24, "the page did not open on its newest line")

        try page.pressFollow()
        try page.scrollNearTop()
        let held = try XCTUnwrap(page.scroll).documentVisibleRect.minY
        source.lines.append(LogEntry(date: start.addingTimeInterval(500), level: .info,
                                     category: "app", message: "arrived while off"))
        page.pump(1.5)
        XCTAssertEqual(try XCTUnwrap(page.scroll).documentVisibleRect.minY, held, accuracy: 1,
                       "with Follow off a new line moved the reader")

        try page.pressFollow()
        source.lines.append(LogEntry(date: start.addingTimeInterval(501), level: .info,
                                     category: "app", message: "arrived while on"))
        page.pump(1.5)
        XCTAssertLessThan(try page.gap(), 24, "with Follow back on a new line was not followed")
    }

    // MARK: - Follow through a filter

    /// A filter that hid every line unmounts the list; letting the lines back
    /// mounts it again with them already there — the road the repair's
    /// `onAppear` exists for, taken a second time inside one open page.
    @MainActor
    func testAFilterThatEmptiedTheListAndLetItBackOpensOnTheNewestLine() throws {
        let page = LogPageUnderHand(LogPageUnderHand.log())
        defer { page.close() }
        page.pump(1.5)
        try page.level(2)   // Errors: none in this log.
        XCTAssertNil(page.scroll, "the Errors filter left a list on the page")
        try page.level(0)
        let gap = try page.gap()
        XCTAssertLessThan(gap, 24, "the list came back \(gap) pt above its newest line")
    }

    // MARK: - The heading reads what is shown

    /// What a filter hides above the first line shown is not drawn, and takes
    /// nothing else with it. Two logs read under Warnings: one where an info line
    /// of the same day sits above the warning, one with the warning alone. They
    /// show the same thing and must draw the same lines of type — the launch's
    /// card, the warning — whatever the hidden line would have cost.
    @MainActor
    func testALineHiddenAboveTheFirstShownOneLeavesNothingBehind() throws {
        func drawn(_ lines: [LogEntry], warningsOnly: Bool) throws -> Int {
            let source = LogPageUnderHandSource()
            source.lines = lines
            let page = LogPageUnderHand(source)
            defer { page.close() }
            page.pump(1.2)
            if warningsOnly { try page.level(1) }
            return try XCTUnwrap(RenderedLines.read(page.mount.host), "no reading of the page").count
        }
        let hidden = LogEntry(date: start, level: .info, category: "app", message: "hidden")
        let shown = LogEntry(date: start.addingTimeInterval(60), level: .warn, category: "app",
                             message: "shown")
        // The subject: under All the extra line is really drawn, so the two logs
        // differ and the filter has something to hide.
        XCTAssertEqual(try drawn([hidden, shown], warningsOnly: false),
                       try drawn([shown], warningsOnly: false) + 1,
                       "the info line did not draw as one more line")
        let behind = try drawn([hidden, shown], warningsOnly: true)
        let alone = try drawn([shown], warningsOnly: true)
        XCTAssertEqual(behind, alone, """
            the same one warning drew \(behind) lines with an info line hidden above it and \
            \(alone) without — a line nobody can see left something on the page
            """)
    }
}

/// Read afresh on every tick of the page, so a line can arrive mid-test.
final class LogPageUnderHandSource: @unchecked Sendable {
    var lines: [LogEntry] = []
    /// How many times the page has read it — so a test that must act between
    /// two reads can tell whether one landed in the way.
    var reads = 0
}

/// The Log page rendered offscreen in a named appearance, with its own controls
/// in reach. The controls are the window's: the page declares its level tabs,
/// its capsule and its search into a `HelmWindowToolbarChannel`, and this reads
/// them back from it and presses them the way the toolbar does — the tab's
/// binding is set, the action's `perform` is called — so a press here goes down
/// the same wire a click in the window does.
@MainActor
final class LogPageUnderHand {
    nonisolated static let start = Date(timeIntervalSince1970: 1_790_000_000)

    /// Four hundred lines, alternating info and warn, the newest a warning — so
    /// the Warnings filter keeps the newest line and changes nothing a rule
    /// keyed on the newest line's identity alone could see.
    static func log(_ count: Int = 400) -> LogPageUnderHandSource {
        let source = LogPageUnderHandSource()
        source.lines = (0..<count).map { index in
            LogEntry(date: start.addingTimeInterval(Double(index)),
                     level: index % 2 == 1 ? .warn : .info, category: "app",
                     message: "line \(index)")
        }
        return source
    }

    let mount: MountedRender
    let channel = HelmWindowToolbarChannel()

    init(_ source: LogPageUnderHandSource) {
        mount = MountedRender(LogView(source: { source.reads += 1; return source.lines },
                                       storedLog: { false }),
                              width: 810, height: 700, appearance: .aqua, channel: channel)
    }

    /// What the page last declared to the window's toolbar.
    var toolbar: HelmPageToolbarContent? { channel.content(for: "log") }

    /// Wall-clock time: the page reads its source on a one-second tick.
    func pump(_ seconds: Double) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            mount.host.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }

    var scroll: NSScrollView? { mount.host.everyView(ofType: NSScrollView.self).first }

    /// How far the bottom of the view is above the bottom of the list, on a
    /// list that must be at least three windows tall for a position to mean
    /// anything.
    func gap() throws -> CGFloat {
        let scroll = try XCTUnwrap(scroll, "the page drew no list")
        let document = try XCTUnwrap(scroll.documentView)
        XCTAssertGreaterThan(document.frame.height, scroll.documentVisibleRect.height * 3,
                             "the list did not outgrow the window, so a position proves nothing")
        return document.frame.height - scroll.documentVisibleRect.maxY
    }

    /// 0 All, 1 Warnings, 2 Errors — the toolbar's tabs, in their order.
    func level(_ segment: Int) throws {
        let content = try XCTUnwrap(toolbar, "the page declared no toolbar")
        let binding = try XCTUnwrap(content.selectedTab, "the page declared no level tabs")
        binding.wrappedValue = try XCTUnwrap(content.tabs[safe: segment], "no such tab").id
        pump(1.2)
    }

    /// The capsule's action of that id, as the page declared it just now.
    func action(_ id: String) throws -> HelmToolbarAction {
        try XCTUnwrap(toolbar?.actions.first { $0.id == id }, "the toolbar has no \(id) action")
    }

    /// Typed into the toolbar's search field.
    func search(_ text: String) throws {
        let search = try XCTUnwrap(toolbar?.search, "the toolbar has no search")
        search.text.wrappedValue = text
        pump(0.6)
    }

    func scrollNearTop() throws {
        let scroll = try XCTUnwrap(scroll)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 1000))
        scroll.reflectScrolledClipView(scroll.contentView)
        pump(0.3)
    }

    /// Follow is a toggle in the toolbar's capsule: pressing it is calling the
    /// action the page declared, which flips the page's own state.
    func pressFollow() throws {
        guard case .toggle(_, let perform) = try action("follow").kind else {
            return XCTFail("Follow is not a toggle in the capsule")
        }
        perform()
        pump(0.3)
    }

    func close() {
        mount.window?.orderOut(nil)
        mount.drop()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
