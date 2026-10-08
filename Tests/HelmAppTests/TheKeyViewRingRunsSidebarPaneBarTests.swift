import AppKit
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **In the real Settings window, never shown, `selectKeyView(following:)` from the sidebar's host lands in
/// the page bar's search field, and the raw `nextKeyView` ring runs sidebar, pane, bar, with the bar's zones
/// in `Zone` order.**
///
/// The real `SettingsWindow`, built through `SettingsWindowRig` and never shown. The rows never ask for the
/// key-view loop themselves: whatever ring there is, is the one the window made. No row presses a key: a Tab
/// here is the window's `selectKeyView(following:)`, and that a pressed Tab arrives at that call is assumed,
/// not measured. No row reads Full Keyboard Access either: the rows were written with it off, and the first
/// row's landing place is the place found with it off. What the rows therefore do not show: how the ring
/// behaves in a window that is key or on screen, with Full Keyboard Access on, or after a Shift-Tab; and
/// whether Tab stops at the tabs, the actions or the sidebar's rows.
///
/// The ring is walked raw, through `nextKeyView`, valid or not, so the order does not depend on which views
/// take Tab. Each view on the walk gets a region by `isDescendant(of:)`: sidebar, bar, pane, other. The ring
/// row asserts the walk met at least two views and two regions before it asserts any order, the later-host
/// row asserts two views, and both print the walk when they fail; the landing row walks nothing. The order
/// of the three regions round the ring is asserted as it was found, sidebar, pane, bar. Why AppKit puts the
/// pane before the bar is not measured (the two are siblings in the clip and share its top-left corner), so
/// a change of that order may be AppKit's and not a defect, and the row's message says so.
@MainActor
final class TheKeyViewRingRunsSidebarPaneBarTests: XCTestCase {

    private enum Region: String { case sidebar, bar, pane, other }

    private struct Opened {
        let rig: SettingsWindowRig
        let sidebar: NSView
        let bar: ShellPageBarView
    }

    private func sidebarHost(_ rig: SettingsWindowRig) -> NSView? {
        Mirror(reflecting: rig.shell.shell).children.first { $0.label == "sidebar" }?.value as? NSView
    }

    private func open() -> Opened? {
        guard let rig = SettingsWindowRig.build(
            in: self, failure: "the window has no content view controller of the shell's type: no ring was read")
        else { return nil }
        guard let sidebar = sidebarHost(rig), let bar = rig.pageBar?.view else {
            XCTFail("the window holds no sidebar host or no page bar: no ring was read")
            return nil
        }
        rig.window.contentView?.layoutSubtreeIfNeeded()
        rig.open("homebrew", search: true)
        SettingsWindowRig.pump()
        rig.window.contentView?.layoutSubtreeIfNeeded()
        addTeardownBlock { await MainActor.run { _ = rig.window.makeFirstResponder(nil) } }
        return Opened(rig: rig, sidebar: sidebar, bar: bar)
    }

    private func search(in bar: ShellPageBarView) -> NSSearchField? {
        func find(_ view: NSView) -> NSSearchField? {
            if let field = view as? NSSearchField { return field }
            for sub in view.subviews { if let found = find(sub) { return found } }
            return nil
        }
        return bar.view(for: .search).flatMap(find)
    }

    private func region(_ view: NSView, _ o: Opened) -> Region {
        if view.isDescendant(of: o.sidebar) { return .sidebar }
        if view.isDescendant(of: o.bar) { return .bar }
        if let clip = o.bar.superview, view.isDescendant(of: clip) { return .pane }
        return .other
    }

    private func zone(_ view: NSView, _ bar: ShellPageBarView) -> ShellPageBarView.Zone? {
        ShellPageBarView.Zone.allCases.first { z in bar.view(for: z).map { view.isDescendant(of: $0) } ?? false }
    }

    /// The raw ring from `start`: until nil, the first repeat, or the ceiling.
    private func walk(from start: NSView) -> (views: [NSView], end: String) {
        var seen: [NSView] = [start]
        var at = start
        for _ in 0..<200 {
            guard let next = at.nextKeyView else { return (seen, "nil") }
            if let again = seen.firstIndex(where: { $0 === next }) {
                return (seen, "repeat of step \(again) (\(type(of: next)))")
            }
            seen.append(next)
            at = next
        }
        return (seen, "the ceiling")
    }

    private func printed(_ w: (views: [NSView], end: String), _ o: Opened) -> String {
        let steps = w.views.enumerated().map { "\($0.offset): \(type(of: $0.element)) [\(region($0.element, o).rawValue)]" }
        return "walk from the sidebar's host: \(w.views.count) views, ended at \(w.end); " + steps.joined(separator: "; ")
    }

    private func collapsed(_ w: (views: [NSView], end: String), _ o: Opened) -> [Region] {
        var out: [Region] = []
        for view in w.views {
            let r = region(view, o)
            if r != .other, out.last != r { out.append(r) }
        }
        return out
    }

    // MARK: - Rows

    func testTabFromTheSidebarLandsInTheBarsSearch() {
        guard let o = open() else { return }
        guard let field = search(in: o.bar) else { return XCTFail("the bar holds no search field") }
        o.rig.window.selectKeyView(following: o.sidebar)
        let responder = o.rig.window.firstResponder
        let editor = responder as? NSText
        XCTAssertTrue(editor != nil && (editor?.delegate as AnyObject?) === field, """
            Tab from the sidebar's host left the first responder at \(responder.map { String(describing: type(of: $0)) } ?? "nil") \
            (editor's delegate: \(String(describing: (editor?.delegate as AnyObject?).map { type(of: $0) }))), \
            not the bar's search field's editor
            """)
    }

    func testTheRingClosesThroughTheSidebarThePaneAndTheBar() {
        guard let o = open() else { return }
        o.rig.window.selectKeyView(following: o.sidebar)
        let w = walk(from: o.sidebar)
        let sentence = printed(w, o)
        let order = collapsed(w, o)
        XCTAssertGreaterThanOrEqual(w.views.count, 2, sentence)
        XCTAssertGreaterThanOrEqual(Set(order).count, 2, sentence + "; regions \(order.map(\.rawValue))")
        XCTAssertEqual(Set(order), [.sidebar, .bar, .pane], sentence + "; regions \(order.map(\.rawValue))")
        XCTAssertTrue(w.end.hasPrefix("repeat of step 0"), "the ring does not close on the sidebar's host; " + sentence)
        XCTAssertEqual(order, [.sidebar, .pane, .bar],
            "the regions round the ring are \(order.map(\.rawValue)), not sidebar, pane, bar; the window's own "
            + "recalculation chose the order of the pane and the bar and why it puts the pane first was never "
            + "measured, so a different order may be AppKit's and not a defect; " + sentence)
        let zones = w.views.filter { region($0, o) == .bar }.compactMap { zone($0, o.bar)?.rawValue }
        XCTAssertEqual(zones, zones.sorted(), "the bar's zones come out of Zone order: \(zones); " + sentence)
        XCTAssertTrue(w.views.contains { zone($0, o.bar) == .search }, "the search zone is not on the walk; " + sentence)
    }

    func testAnActionsHostBuiltLaterIsOnTheWalkAndTheOldOneIsNot() {
        guard let o = open() else { return }
        o.rig.window.selectKeyView(following: o.sidebar)
        let old = o.bar.view(for: .actions)
        var content = SettingsWindowRig.content(search: true)
        content.actions = [HelmToolbarAction(id: "reload", title: "Reload list", symbol: "arrow.triangle.2.circlepath") {}]
        // Another page's actions arrive: the same page's change is animated and keeps the host.
        o.rig.model.selection = .module("log")
        o.rig.channel.declare(content, token: "log", generation: o.rig.channel.nextGeneration())
        SettingsWindowRig.pump()
        o.rig.window.contentView?.layoutSubtreeIfNeeded()
        guard let new = o.bar.view(for: .actions), let old else {
            return XCTFail("the bar holds no actions host before or after the change")
        }
        XCTAssertFalse(new === old, "the actions host was not rebuilt: the condition of this row did not happen")
        o.rig.window.selectKeyView(following: o.sidebar)
        let w = walk(from: o.sidebar)
        let sentence = printed(w, o)
        XCTAssertGreaterThanOrEqual(w.views.count, 2, sentence)
        XCTAssertTrue(w.views.contains { $0.isDescendant(of: new) }, "the new actions host is not on the walk; " + sentence)
        XCTAssertFalse(w.views.contains { $0.isDescendant(of: old) }, "the old actions host is still on the walk; " + sentence)
    }
}
