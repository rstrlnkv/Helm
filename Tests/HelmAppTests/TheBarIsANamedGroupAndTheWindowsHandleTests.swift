import AppKit
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The page bar is one named accessibility group of the zones it shows, and its hit test answers the
/// bar itself on the name, on the status and where no zone stands.**
///
/// No window is ordered anywhere; the bar and the views in it belong to no window. What these rows
/// prove, and no more:
/// - the bar's accessibility role is `.toolbar` and it is an accessibility element;
/// - for plain views that are themselves accessibility elements, its accessibility children are the views
///   of the zones it shows, in zone order, whatever order the views were given in; a hidden zone and a
///   zone with no view are not among them. What the real name and status hosts answer as children is asked
///   by no row;
/// - the labels are properties read back: the bar's is the page's name, the name's is the same, the
///   status's is the status word, and each follows a new page and survives an equal snapshot;
/// - on the real name and status hosts a point inside either view, and a point in no zone, answer the bar;
///   a point inside the tabs' view, a plain view in this row, answers that view; this row passes with an
///   empty handle set, because those hosts claim no point here. The handle set is held only by the row on plain views, where
///   a view that claims the point still answers the bar in the name and the status and answers itself in
///   the tabs; the bar says a press on it may move the window;
/// - the double-click table is a pure function of the stored string.
///
/// What waits for a hand and is NOT proved by any row here: that a press in the bar actually moves the
/// window, that a double click zooms it, what VoiceOver speaks for the group and its children, where Tab goes
/// with Full Keyboard Access, and the stored spellings "Minimize" and "None" of the system's double-click
/// setting (only the absent key was read, on this Mac; the rows below take the two spellings as given).
///
/// Hit-test points: `NSView.hitTest(_:)` takes a point in its superview's coordinates. In the two rows that
/// hit-test, the bar stands in a plain container at an origin that is not (0, 0), and every point is
/// converted from the bar's own coordinates to the container's.
@MainActor
final class TheBarIsANamedGroupAndTheWindowsHandleTests: XCTestCase {

    private typealias Bar = ShellPageBarView

    // MARK: - The fake

    /// One zone of the port's states only: a view, a width, and nothing else.
    @MainActor
    private final class FakeZone: ShellBarZone {
        enum Field { case tabs, actions, search }
        let field: Field
        let view: NSView? = NSView()
        let width: CGFloat
        var measuresMoved: (() -> Void)?

        init(_ field: Field, width: CGFloat) {
            self.field = field
            self.width = width
        }

        func show(_ state: ShellBarZoneState) {}

        func measure(into measures: inout Bar.Measures) {
            switch field {
            case .tabs: measures.tabs = width; measures.tabsFolded = 136
            case .actions: measures.actions = width
            case .search: measures.hasSearch = width > 0
            }
        }

        func apply(_ verdicts: Bar.Verdicts) {}
    }

    private func makeBar() -> (bar: ShellPageBar, tabs: FakeZone) {
        let tabs = FakeZone(.tabs, width: 310)
        let bar = ShellPageBar(model: SettingsModel(host: ModuleHost.shared),
                               channel: HelmWindowToolbarChannel(),
                               tabs: tabs, actions: FakeZone(.actions, width: 72),
                               search: FakeZone(.search, width: 283), titlebarIsTransparent: true)
        return (bar, tabs)
    }

    private func identity(_ title: String, status: (word: String, active: Bool)?) -> ShellPageBar.Identity {
        ShellPageBar.Identity(symbol: "gearshape", tint: .gray, title: title, status: status)
    }

    // MARK: - The group and its children

    func testTheBarIsAToolbarWhoseChildrenAreTheZonesItShowsInOrder() {
        let bar = Bar()
        var given: [Bar.Zone: NSView] = [:]
        for zone in [Bar.Zone.status, .search, .name, .actions, .tabs] {
            let view = NSView()
            view.setAccessibilityElement(true)
            given[zone] = view
            bar.setView(view, for: zone)
        }
        // The status's width is 0, so the layout hides its view; the other four stand.
        bar.measures = Bar.Measures(name: 130, tabs: 310, tabsFolded: 136, actions: 72, status: 0, hasSearch: true)
        bar.place = Bar.Place(cardMinX: 200, windowWidth: 1060, buttons: .null)
        bar.frame = NSRect(x: 0, y: 0, width: 856, height: 52)
        bar.layoutSubtreeIfNeeded()

        XCTAssertFalse(bar.reachableZones.isEmpty, """
            the bar holds no zone view that is shown: an empty list is in order with everything, so every \
            comparison below would pass of itself
            """)
        XCTAssertTrue(given[.status]?.isHidden == true, "the layout did not hide the status view this row relies on")
        XCTAssertTrue(bar.isAccessibilityElement(), "the bar is not an accessibility element")
        XCTAssertEqual(bar.accessibilityRole(), .toolbar)
        XCTAssertEqual(bar.reachableZones, [.name, .tabs, .actions, .search])

        let children = bar.accessibilityChildren() ?? []
        let expected = [given[.name]!, given[.tabs]!, given[.actions]!, given[.search]!]
        XCTAssertEqual(children.count, 4, "the bar's children are not the four shown zones")
        XCTAssertTrue(zip(children, expected).allSatisfy { ($0 as AnyObject) === $1 },
                      "the bar's children are not the shown zones' views in zone order")

        bar.setView(nil, for: .actions)
        XCTAssertEqual(bar.reachableZones, [.name, .tabs, .search], "a zone with no view is still reachable")
        XCTAssertEqual((bar.accessibilityChildren() ?? []).count, 3)
    }

    // MARK: - The names

    func testTheBarAndItsTwoWordsAreNamed() {
        let (controller, _) = makeBar()
        let bar = controller.view

        controller.draw(identity("Alpha", status: ("Active", true)))
        let name = bar.view(for: .name)
        let status = bar.view(for: .status)
        XCTAssertNotNil(bar.accessibilityLabel(), "the bar's label is nil")
        XCTAssertNotNil(name, "the name's host was never built, so its label cannot be read")
        XCTAssertNotNil(status, "the status's host was never built, so its label cannot be read")
        XCTAssertEqual(bar.accessibilityLabel(), "Alpha")
        XCTAssertEqual(name?.accessibilityLabel(), "Alpha")
        XCTAssertEqual(status?.accessibilityLabel(), "Active")

        controller.draw(identity("Beta", status: ("Idle", false)))
        XCTAssertEqual(bar.accessibilityLabel(), "Beta", "the bar's label did not follow the page")
        XCTAssertEqual(name?.accessibilityLabel(), "Beta")
        XCTAssertEqual(status?.accessibilityLabel(), "Idle")

        // An equal snapshot is refused for the hosts, but the labels are written before that guard.
        bar.setAccessibilityLabel("tampered")
        name?.setAccessibilityLabel("tampered")
        status?.setAccessibilityLabel("tampered")
        controller.draw(identity("Beta", status: ("Idle", false)))
        XCTAssertEqual(bar.accessibilityLabel(), "Beta", "an equal snapshot left the bar's label unwritten")
        XCTAssertEqual(name?.accessibilityLabel(), "Beta")
        XCTAssertEqual(status?.accessibilityLabel(), "Idle")
    }

    // MARK: - The handle

    func testAPressOnTheNameOrOnNothingIsThePressOnTheBar() {
        let (controller, tabs) = makeBar()
        controller.draw(identity("Alpha", status: ("Active", true)))
        let bar = controller.view
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 200))
        container.addSubview(bar)
        bar.place = Bar.Place(cardMinX: 200, windowWidth: 1060, buttons: .null)
        bar.frame = NSRect(x: 10, y: 30, width: 856, height: 52)
        bar.layoutSubtreeIfNeeded()

        let name = bar.view(for: .name)
        let status = bar.view(for: .status)
        let tabsView = tabs.view
        XCTAssertNotNil(bar.frames, "the bar was never laid out: every point hits nothing")
        XCTAssertTrue(name != nil && name?.isHidden == false && name?.frame.width ?? 0 > 0, "the name is not placed")
        XCTAssertTrue(status != nil && status?.isHidden == false && status?.frame.width ?? 0 > 0, "the status is not placed")
        XCTAssertTrue(tabsView != nil && tabsView?.isHidden == false && tabsView?.frame.width ?? 0 > 0, "the tabs are not placed")
        guard let name, let status, let tabsView else { return }

        func inContainer(_ point: CGPoint) -> CGPoint { bar.convert(point, to: container) }
        func centre(_ view: NSView) -> CGPoint { CGPoint(x: view.frame.midX, y: view.frame.midY) }
        let gap = CGPoint(x: (name.frame.maxX + tabsView.frame.minX) / 2, y: name.frame.midY)
        XCTAssertGreaterThan(tabsView.frame.minX, name.frame.maxX, "no gap between the name and the tabs to press in")

        XCTAssertTrue(bar.hitTest(inContainer(centre(name))) === bar, "a press on the name did not answer the bar")
        XCTAssertTrue(bar.hitTest(inContainer(centre(status))) === bar, "a press on the status did not answer the bar")
        XCTAssertTrue(bar.hitTest(inContainer(gap)) === bar, "a press on no zone did not answer the bar")
        XCTAssertTrue(bar.hitTest(inContainer(centre(tabsView))) === tabsView, "a press on the tabs did not answer the tabs' view")
        XCTAssertTrue(bar.mouseDownCanMoveWindow)
    }

    /// The row above stands on the real hosting views, which may answer no hit of their own, in which case
    /// the bar answers by default and the handle set decides nothing. Plain views claim every point inside them,
    /// so here a press on a handle zone's view, or on a subview inside it, answers the bar only because the
    /// bar's handle set says so, and a press on the tabs' view answers that view.
    func testAViewThatClaimsThePressStillHandsItToTheBarOnlyInTheHandleZones() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 200))
        let bar = Bar()
        container.addSubview(bar)
        var given: [Bar.Zone: NSView] = [:]
        for zone in [Bar.Zone.name, .status, .tabs] {
            given[zone] = NSView()
            bar.setView(given[zone], for: zone)
        }
        let inner = NSView(frame: NSRect(x: 0, y: 0, width: 2, height: 2))
        given[.name]!.addSubview(inner)
        bar.measures = Bar.Measures(name: 130, tabs: 310, tabsFolded: 136, actions: 72, status: 60, hasSearch: true)
        bar.place = Bar.Place(cardMinX: 200, windowWidth: 1060, buttons: .null)
        bar.frame = NSRect(x: 10, y: 30, width: 856, height: 52)
        bar.layoutSubtreeIfNeeded()

        for zone in [Bar.Zone.name, .status, .tabs] {
            let view = given[zone]!
            XCTAssertFalse(view.isHidden || view.frame.width <= 0, "the \(zone) view is not placed")
            XCTAssertTrue(bar.convert(CGPoint(x: view.frame.midX, y: view.frame.midY), to: container) != .zero)
        }
        func hit(_ view: NSView, _ point: CGPoint) -> NSView? {
            bar.hitTest(bar.convert(view.convert(point, to: bar), to: container))
        }
        let mid = { (v: NSView) in CGPoint(x: v.bounds.midX, y: v.bounds.midY) }
        // The subview sits at the view's origin; its parent's claim must be checked at a point outside it.
        XCTAssertTrue(hit(given[.name]!, mid(given[.name]!)) === bar, "a press on a plain name view did not answer the bar")
        XCTAssertTrue(hit(given[.name]!, CGPoint(x: 1, y: 1)) === bar, "a press on a subview of the name did not answer the bar")
        XCTAssertTrue(hit(given[.status]!, mid(given[.status]!)) === bar, "a press on a plain status view did not answer the bar")
        XCTAssertTrue(hit(given[.tabs]!, mid(given[.tabs]!)) === given[.tabs], "a press on the tabs' view did not answer that view")
    }

    // MARK: - The double click

    func testADoubleClickDoesWhatTheTitleBarWouldDo() {
        XCTAssertEqual(Bar.doubleClick(stored: nil), .zoom)
        XCTAssertEqual(Bar.doubleClick(stored: "Maximize"), .zoom)
        XCTAssertEqual(Bar.doubleClick(stored: "Minimize"), .minimize)
        XCTAssertEqual(Bar.doubleClick(stored: "None"), .nothing)
        XCTAssertEqual(Bar.doubleClick(stored: "x"), .zoom)
        XCTAssertEqual(Bar.doubleClick(stored: ""), .zoom)
    }
}
