import AppKit
import HelmUI
import SwiftUI
import XCTest
@testable import HelmApp

/// **`SettingsToolbar.identifiers` leads with what its `lead` says: the sidebar's
/// tracking separator for `.sidebarSeparator`, nothing or the leading spacer for
/// `.spacer`; the `.sidebarSeparator` bar stays exactly what it was.** In the
/// tree only `.sidebarSeparator` is constructed; `.spacer` and `hasSpacer: true`
/// are reached by these tests alone.
///
/// No window, no `NSWindow`, no screen: `SettingsToolbar.identifiers` and
/// `SettingsToolbar.spacerWidth` are pure, and the content shapes are plain
/// values.
///
/// The `.sidebarSeparator` lists below are pinned LITERALLY, read from
/// `SettingsToolbar.identifiers(content:style:)` as it stood at c753c864
/// (that commit's `Sources/HelmApp/SettingsToolbar.swift`): the tracking separator
/// first; the name item only under `.moduleName`; then, with nothing declared,
/// `flexibleSpace, status` (`.moduleName` only); otherwise `flexibleSpace`,
/// `tabs, flexibleSpace` when there are tabs, `actions`, `search`. They are not
/// computed through the function under test, so a lead that is ignored or a
/// list that moved goes red here (a moved tail also in
/// `TheStatusBadgeMovesToTheWindowsTrailingEdgeTests`, which compares the tail
/// of `toolbar.itemIdentifiers`).
///
/// The numbers: 92.5 is where the toolbar can start its items (`itemsStart`),
/// an input these tests feed, taken from one measurement on macOS 27.2 with a
/// 200 pt sidebar, not a fact they establish; 123.5 = 200 + 16 - 92.5 is the
/// expectation derived from it, not a second measurement. For a pane whose
/// leading edge is at 56 the items already start past 56 + 16, so the answer is
/// nil; the reason `spacerWidth`'s doc comment gives (a too-narrow spacer is
/// centred in an item wider than itself and moves the name further than its
/// width) was seen once on macOS 27.2 and is not reproducible by a command in
/// the tree.
@MainActor
final class TheToolbarLeadsWithWhatItsShellGivesTests: XCTestCase {

    private typealias ID = NSToolbarItem.Identifier
    private static let sep = ID.sidebarTrackingSeparator
    private static let flex = ID.flexibleSpace
    private static let name = ID("helm.name")
    private static let status = ID("helm.status")
    private static let tabs = ID("helm.tabs")
    private static let actions = ID("helm.actions")
    private static let search = ID("helm.search")
    /// The spacer item's identifier, as `SettingsToolbar.spacerID` spells it.
    private static let spacer = ID("helm.leadingSpacer")

    // MARK: - content shapes

    private static func content(tabs: Bool, actions: Bool, search: Bool) -> HelmPageToolbarContent? {
        if !tabs && !actions && !search { return nil }
        return HelmPageToolbarContent(
            tabs: tabs ? [HelmToolbarTab(id: "a", title: "Alpha", symbol: "circle"),
                          HelmToolbarTab(id: "b", title: "Beta", symbol: "square")] : [],
            selectedTab: tabs ? .constant("a") : nil,
            actions: actions ? [HelmToolbarAction(id: "go", title: "Go", symbol: "arrow.clockwise") {}] : [],
            search: search ? HelmToolbarSearch(prompt: "Search", text: .constant("")) : nil)
    }

    private struct Shape {
        let label: String
        let content: HelmPageToolbarContent?
        let moduleName: [ID]
        let windowTitle: [ID]
    }

    /// Pinned from the c753c864 source, one row per reachable content shape.
    private static let shapes: [Shape] = [
        Shape(label: "nothing declared (nil)", content: nil,
              moduleName: [sep, name, flex, status], windowTitle: [sep]),
        Shape(label: "declared but empty", content: HelmPageToolbarContent(),
              moduleName: [sep, name, flex, status], windowTitle: [sep]),
        Shape(label: "tabs", content: content(tabs: true, actions: false, search: false),
              moduleName: [sep, name, flex, tabs, flex], windowTitle: [sep, flex, tabs, flex]),
        Shape(label: "actions", content: content(tabs: false, actions: true, search: false),
              moduleName: [sep, name, flex, actions], windowTitle: [sep, flex, actions]),
        Shape(label: "search", content: content(tabs: false, actions: false, search: true),
              moduleName: [sep, name, flex, search], windowTitle: [sep, flex, search]),
        Shape(label: "tabs + actions", content: content(tabs: true, actions: true, search: false),
              moduleName: [sep, name, flex, tabs, flex, actions], windowTitle: [sep, flex, tabs, flex, actions]),
        Shape(label: "tabs + search", content: content(tabs: true, actions: false, search: true),
              moduleName: [sep, name, flex, tabs, flex, search], windowTitle: [sep, flex, tabs, flex, search]),
        Shape(label: "actions + search", content: content(tabs: false, actions: true, search: true),
              moduleName: [sep, name, flex, actions, search], windowTitle: [sep, flex, actions, search]),
        Shape(label: "tabs + actions + search", content: content(tabs: true, actions: true, search: true),
              moduleName: [sep, name, flex, tabs, flex, actions, search],
              windowTitle: [sep, flex, tabs, flex, actions, search]),
    ]

    private func raw(_ list: [ID]) -> [String] { list.map(\.rawValue) }

    // MARK: - the bar led by `.spacer`

    /// Total failure prints: "a pane whose leading edge is at 56 gets a spacer: a too-narrow spacer is
    /// centred in an item wider than itself, so it moves the name further than its width" (`spacerWidth`
    /// answers a number there) / "a bar led by `.spacer` still leads with the tracking separator, which
    /// tracks nothing without a split view; got <list>" (the list starts with the separator, or with
    /// anything but the name).
    func testWhereTheItemsStartPastThePaneTheBarCarriesNoSpacer() {
        XCTAssertNil(SettingsToolbar.spacerWidth(paneLeading: 56, itemsStart: 92.5),
                     "a pane whose leading edge is at 56 gets a spacer: a too-narrow spacer is centred in an item wider than itself, so it moves the name further than its width")
        let list = SettingsToolbar.identifiers(content: nil, style: .moduleName, lead: .spacer, hasSpacer: false)
        XCTAssertEqual(raw(list), raw([Self.name, Self.flex, Self.status]),
                       "a bar led by `.spacer` still leads with the tracking separator, which tracks nothing without a split view; got \(raw(list))")
    }

    /// Total failure prints: "at sidebar 200 the bar carries no spacer: …" / "at sidebar 200 the spacer is <x>, not 123.5: …".
    func testAtSidebar200TheSpacerIs123Point5() throws {
        let w = try XCTUnwrap(SettingsToolbar.spacerWidth(paneLeading: 200, itemsStart: 92.5),
                              "at sidebar 200 the bar carries no spacer: the name sits at the item floor, under the sidebar's edge")
        XCTAssertEqual(w, 123.5, accuracy: 0.0001, "at sidebar 200 the spacer is \(w), not 123.5: the name does not land 16 pt past the pane's edge")
    }

    /// With `hasSpacer` the `.spacer` lead lists `[spacer, name, …]`; the `.sidebarSeparator` lead never shows it.
    /// Total failure prints: "the spacer is missing from the list or not first: got <list>".
    func testWithASpacerTheBarOpensWithTheSpacerThenTheName() {
        let list = SettingsToolbar.identifiers(content: nil, style: .moduleName, lead: .spacer, hasSpacer: true)
        XCTAssertEqual(raw(list), raw([Self.spacer, Self.name, Self.flex, Self.status]),
                       "the spacer is missing from the list or not first: got \(raw(list))")
    }

    // MARK: - the separator-led bar is byte-for-byte today's

    /// Total failure prints: "the separator-led bar moved under <shape> / moduleName: want […] got […]"
    /// and "the separator-led bar no longer starts with the tracking separator under <shape>".
    func testTheSeparatorLeadEqualsTodaysPinnedListForEveryShape() {
        for shape in Self.shapes {
            let m = SettingsToolbar.identifiers(content: shape.content, style: .moduleName, lead: .sidebarSeparator, hasSpacer: false)
            XCTAssertEqual(raw(m), raw(shape.moduleName),
                           "the separator-led bar moved under \(shape.label) / moduleName: want \(raw(shape.moduleName)) got \(raw(m))")
            XCTAssertEqual(m.first, Self.sep, "the separator-led bar no longer starts with the tracking separator under \(shape.label)")
            let t = SettingsToolbar.identifiers(content: shape.content, style: .windowTitle, lead: .sidebarSeparator, hasSpacer: false)
            XCTAssertEqual(raw(t), raw(shape.windowTitle),
                           "the separator-led bar moved under \(shape.label) / windowTitle: want \(raw(shape.windowTitle)) got \(raw(t))")
            XCTAssertEqual(t.first, Self.sep, "the separator-led bar no longer starts with the tracking separator under \(shape.label) / windowTitle")
        }
    }

    /// The `.spacer` lead without a spacer is today's list with its first item gone — nothing else moves.
    /// Total failure prints: "the `.spacer` lead changed more than the first item under <shape> / moduleName: got […]".
    func testTheSpacerLeadWithoutASpacerIsTodaysListMinusItsSeparator() {
        for shape in Self.shapes {
            let m = SettingsToolbar.identifiers(content: shape.content, style: .moduleName, lead: .spacer, hasSpacer: false)
            XCTAssertEqual(raw(m), raw(Array(shape.moduleName.dropFirst())),
                           "the `.spacer` lead changed more than the first item under \(shape.label) / moduleName: got \(raw(m))")
            let t = SettingsToolbar.identifiers(content: shape.content, style: .windowTitle, lead: .spacer, hasSpacer: false)
            XCTAssertEqual(raw(t), raw(Array(shape.windowTitle.dropFirst())),
                           "the `.spacer` lead changed more than the first item under \(shape.label) / windowTitle: got \(raw(t))")
            XCTAssertFalse(t.contains(Self.sep) || m.contains(Self.sep),
                           "a bar led by `.spacer` carries the sidebar tracking separator under \(shape.label)")
        }
    }

    /// Total failure prints: "the `.spacer` lead with a spacer changed more than the first item under <shape>: got […]".
    func testTheSpacerLeadWithASpacerIsTodaysListWithTheSpacerInPlaceOfTheSeparator() {
        for shape in Self.shapes {
            let m = SettingsToolbar.identifiers(content: shape.content, style: .moduleName, lead: .spacer, hasSpacer: true)
            XCTAssertEqual(raw(m), raw([Self.spacer] + shape.moduleName.dropFirst()),
                           "the `.spacer` lead with a spacer changed more than the first item under \(shape.label): got \(raw(m))")
        }
    }

    // MARK: - boundaries and hostile inputs

    /// `paneLeading + 16 <= itemsStart` is nil: the boundary itself is nil, a hair over is a number.
    /// Total failure prints: "at paneLeading + 16 == itemsStart the bar carries a zero-width spacer item instead of none" /
    /// "a quarter point past the boundary the spacer vanished: …".
    func testTheBoundaryPaneLeadingPlus16EqualsItemsStart() throws {
        XCTAssertNil(SettingsToolbar.spacerWidth(paneLeading: 76.5, itemsStart: 92.5),
                     "at paneLeading + 16 == itemsStart the bar carries a zero-width spacer item instead of none")
        let over = try XCTUnwrap(SettingsToolbar.spacerWidth(paneLeading: 76.75, itemsStart: 92.5),
                                 "a quarter point past the boundary the spacer vanished: the name overlaps the buttons")
        XCTAssertEqual(over, 0.25, accuracy: 0.0001, "a quarter point past the boundary the spacer is \(over), not 0.25")
        XCTAssertNil(SettingsToolbar.spacerWidth(paneLeading: 76.25, itemsStart: 92.5),
                     "a quarter point before the boundary the bar carries a negative spacer")
    }

    /// A spacer width is nil or a finite positive number — never zero, negative, infinite or not-a-number,
    /// whatever arrives, finite pairs whose difference overflows included.
    /// Total failure prints: "spacerWidth(paneLeading: <p>, itemsStart: <i>) answered <x>: a zero, negative, infinite or not-a-number spacer reaches the toolbar".
    func testNoInputMakesAnUnusableSpacer() {
        let hostile: [(CGFloat, CGFloat)] = [
            (-10, 92.5), (-.greatestFiniteMagnitude, 92.5), (0, 92.5),
            (.nan, 92.5), (200, .nan), (.nan, .nan),
            (.infinity, 92.5), (-.infinity, 92.5), (200, .infinity), (200, -.infinity),
            (200, -5), (200, 0), (0, 0), (-1, -1),
            // Both finite, the difference is not: 1e308 + 16 - (-1e308) overflows to +infinity.
            (.greatestFiniteMagnitude, -.greatestFiniteMagnitude), (1e308, -1e308),
        ]
        for (p, i) in hostile {
            if let w = SettingsToolbar.spacerWidth(paneLeading: p, itemsStart: i) {
                XCTAssertTrue(w.isFinite && w > 0,
                              "spacerWidth(paneLeading: \(p), itemsStart: \(i)) answered \(w): a zero, negative, infinite or not-a-number spacer reaches the toolbar")
            }
        }
        for p: CGFloat in [-10, 0, .nan, -.infinity] {
            XCTAssertNil(SettingsToolbar.spacerWidth(paneLeading: p, itemsStart: 92.5),
                         "a pane leading of \(p) left of the buttons gets a spacer instead of none")
        }
        XCTAssertNil(SettingsToolbar.spacerWidth(paneLeading: 200, itemsStart: .nan),
                     "a not-a-number items start gets a number: the spacer's width is a guess")
    }

    /// The sidebar's maximum (`SettingsWindow.sidebarMaximum`, 320) is the sidebar's business, not this function's: 320 → 243.5, wider keeps growing, finite.
    /// Total failure prints: "a pane at the 320 maximum carries no spacer" / "a pane at 320 gets <x>, not 243.5" /
    /// "a pane wider than 320 (<p>) shrank or went non-finite: …".
    func testAPaneWiderThanTheMaximumStaysArithmetic() throws {
        let max = try XCTUnwrap(SettingsToolbar.spacerWidth(paneLeading: 320, itemsStart: 92.5), "a pane at the 320 maximum carries no spacer")
        XCTAssertEqual(max, 243.5, accuracy: 0.0001, "a pane at 320 gets \(max), not 243.5")
        var last = max
        for p: CGFloat in [321, 400, 5000] {
            let w = SettingsToolbar.spacerWidth(paneLeading: p, itemsStart: 92.5)
            XCTAssertNotNil(w, "a pane at \(p) lost its spacer")
            if let w {
                XCTAssertTrue(w.isFinite && w > last, "a pane wider than 320 (\(p)) shrank or went non-finite: \(w) after \(last)")
                last = w
            }
        }
    }

    /// 200 → 123.5 holds on both sides of it: the spacer is the pane leading plus 16 less the items' start, linear.
    /// Total failure prints: "the spacer is not linear in the pane's leading edge: at <p> got <x>, want <y>".
    func testTheSpacerFollowsThePaneOneForOne() throws {
        for (p, want) in [(150.0, 73.5), (200.0, 123.5), (250.0, 173.5)] as [(CGFloat, CGFloat)] {
            let w = try XCTUnwrap(SettingsToolbar.spacerWidth(paneLeading: p, itemsStart: 92.5), "no spacer at pane \(p)")
            XCTAssertEqual(w, want, accuracy: 0.0001, "the spacer is not linear in the pane's leading edge: at \(p) got \(w), want \(want)")
        }
    }

    /// The `.sidebarSeparator` lead ignores `hasSpacer`: a spacer asked of a bar led by the separator changes nothing.
    /// Total failure prints: "the separator-led bar changed when a spacer was asked of it under <shape> / <style>: got […]".
    func testTheSeparatorLeadIgnoresAskedForSpacer() {
        for shape in Self.shapes {
            for (style, want) in [(PageBarStyle.moduleName, shape.moduleName), (.windowTitle, shape.windowTitle)] {
                let list = SettingsToolbar.identifiers(content: shape.content, style: style, lead: .sidebarSeparator, hasSpacer: true)
                XCTAssertEqual(raw(list), raw(want),
                               "the separator-led bar changed when a spacer was asked of it under \(shape.label) / \(style): got \(raw(list))")
                XCTAssertFalse(list.contains(Self.spacer), "the separator-led bar carries the leading spacer under \(shape.label) / \(style)")
            }
        }
    }

    /// A pane leading below zero is no position, however far left the items start: the arithmetic alone
    /// (-10 + 16 - (-200) = 206) would answer a width. Total failure prints:
    /// "a pane leading of <p> with items at <i> got a <w> pt spacer".
    func testANegativePaneLeadingGetsNoSpacerWhateverTheItemsStart() {
        for (p, i) in [(-10, -200), (-1, -1), (-0.5, -100), (-.greatestFiniteMagnitude, -.greatestFiniteMagnitude)] as [(CGFloat, CGFloat)] {
            let w = SettingsToolbar.spacerWidth(paneLeading: p, itemsStart: i)
            XCTAssertNil(w, "a pane leading of \(p) with items at \(i) got a \(w ?? 0) pt spacer")
        }
    }
}
