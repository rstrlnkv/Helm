import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **A glyph-only switcher draws the glyphs a page re-declares its options
/// with, under the same names.** Guards `symbolsChanged` in
/// `HelmToolbarSwitcher.updateNSView` and the `Coordinator.lastSymbols` it
/// reads: a changed glyph forces a fill on the cheap path the way a changed
/// word or name does.
///
/// Written as a repro (tester, 2026-09-25) against the tree before it. The
/// cheap path refilled on a changed drawn word (`labelsMatch`), a moved
/// selection, or a changed name (`namesChanged`, `Coordinator.lastNames`). A
/// glyph is none of the three: with the count, the style, the names and the
/// selection all unchanged, a new `symbol` never reached `fill`. Measured then
/// through the actions capsule on this Mac: `minus` / `ellipsis` re-declared
/// as `rectangle.3.group` / `keyboard` under the same two names left the
/// control drawing `minus` / `ellipsis` at 73.0 pt while
/// `SettingsToolbar.segmentedReserveWidth(_:look:)` measured the new pair at
/// 85.0 — the switcher stale and the reserve 12 pt past it. The capsule's
/// switcher is always `.icons`, so it is always in the one style where a
/// glyph is all that is drawn. No page changes an option's glyph today
/// (Hosts' are literals and no other page declares options); the same cheap path carried this for
/// the centre tabs in `.icons` and `.iconsAndText`. Seen red again (tester,
/// 2026-09-26) with `symbolsChanged` taken out of the refill condition in the
/// tree it guards: the segments' images still 14.0 × 4.0 and 14.0 × 5.0
/// against a fresh switcher's 21.0 × 14.0 and 19.0 × 13.0, and 73.0 pt wide
/// against 85.0.
///
/// Compared against a bar built fresh with the second pair rather than
/// against a number, so the check follows whatever this Mac draws.
///
/// **The bar.** A `SettingsToolbar` built with the default lead
/// `.sidebarSeparator` on a bare `NSWindow`, not the `lead: .spacer` bar the
/// app's window builds. The capsule is read through `ActionsCapsuleReading`:
/// the item hosts it under the look's environment writes, so the item's view
/// is no `NSHostingView<HelmToolbarActionsCapsule>`.
///
/// **The look.** The bar's look is read when it is built
/// (`AppSettings.barAppearance`), and both rows run under each of Flat and
/// Liquid Glass, asserting from the switcher's cell that the look reached the
/// bar (`HelmFlatSegmentedCell` under Flat, AppKit's `NSSegmentedCell` under
/// Liquid Glass). The two pairs differ by 4 pt under Flat's cell (90.0 and
/// 94.0) and by 12 under AppKit's (73.0 drawn and 85.0 asked for), so the
/// precondition of the first row is the one that holds under both: the two
/// pairs' images differ and the widths differ by more than the half point the
/// comparison allows.
///
/// **What the width of the first row is compared with.** Under Flat, the frame
/// of a fresh switcher with the second pair: 94.0 pt against 90.0 for the first
/// pair. Under Liquid Glass, the width that fresh switcher's cell asks for
/// (`intrinsicContentSize`), not its frame.
///
/// Measured (2026-10-13, Liquid Glass, a window never ordered front, run
/// alone): a fresh switcher with `rectangle.3.group` / `keyboard` under
/// AppKit's cell is 74.0 pt wide, the width of its first layout, while its
/// own intrinsic size reads 85.0 pt; the `[glyph redraw]` line the first row
/// prints carries the frame, fitting size, intrinsic size and cell size of that
/// fresh control; that a second layout and a 0.3 s run-loop turn leave the 74.0
/// as it is was a scratch reading that no row repeats. The switcher that drew `minus` / `ellipsis` at 73.0 pt and
/// is then re-declared with the second pair is refilled, which invalidates its
/// intrinsic size, and draws at the width its cell asks for (asserted, the
/// 85.0 the line prints). So the frame of a fresh switcher is not what a
/// re-declared one is compared with in that window, and the cell's size is.
///
/// Read by hand on 2026-10-12, in the real window, shown and not key, under
/// Liquid Glass, on Hosts' second tab at its first show, before any page had
/// re-declared its glyphs: the `helm.actions` item 113.0 pt wide, its segmented
/// control 77.5 pt with an intrinsic width of 77.5, the cell's own size. That
/// reading says nothing about a shown window after a re-declaration, nor
/// about the capsule's reserve for the entry in a shown window.
///
/// A switcher that was not redrawn is the one the `[glyph redraw]` line's
/// `before` figure prints: under Liquid Glass 73.0 pt against the 85.0 the cell
/// asks for (90.0 against 94.0 under Flat), with the images still the first
/// pair's.
///
/// **The second row holds `namesChanged` alone.** The switcher is always
/// `.icons`, so `labelsMatch` reads an empty word before and after; a row that
/// moves the selection, changes a glyph or the count refills for that reason
/// and would pass with `namesChanged` taken out of the refill condition. This
/// one re-declares the same two glyphs under new titles, with the same count,
/// the same selection and nothing needing attention, and asserts the tooltips
/// and the glyphs' accessibility descriptions move to the new titles on the
/// control that was already there.
@MainActor
final class AGlyphSwitcherRedrawsAChangedGlyphTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        PinnedBarSettings.pin(in: self)
    }

    private let looks: [HelmBarAppearance] = [.flat, .liquidGlass]

    private struct Mounted {
        let toolbar: SettingsToolbar
        let channel: HelmWindowToolbarChannel
        let window: NSWindow
    }

    private func mount(_ look: HelmBarAppearance) -> Mounted {
        AppSettings.barAppearance = look
        let model = SettingsModel(host: ModuleHost.shared)
        let channel = HelmWindowToolbarChannel()
        let toolbar = SettingsToolbar(model: model, channel: channel)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        toolbar.window = window
        model.selection = .module("test.changedGlyph")
        return Mounted(toolbar: toolbar, channel: channel, window: window)
    }

    private func declare(_ glyphs: [String], titles: [String] = ["First", "Second"], on mounted: Mounted) {
        mounted.channel.declare(HelmPageToolbarContent(actions: [
            HelmToolbarAction(id: "viewMode", title: "View", options: [
                HelmToolbarTab(id: "first", title: titles[0], symbol: glyphs[0]),
                HelmToolbarTab(id: "second", title: titles[1], symbol: glyphs[1]),
            ], selection: .constant("first")),
        ]), token: "test.changedGlyph", generation: mounted.channel.nextGeneration())
        mounted.window.layoutIfNeeded()
    }

    private func switcher(_ mounted: Mounted, look: HelmBarAppearance) throws -> NSSegmentedControl {
        let context = "\(look) switcher"
        let read = try ActionsCapsuleReading.read(try XCTUnwrap(mounted.window.toolbar,
                                                                "\(context): the window wears no toolbar"),
                                                  context: context)
        let control = try XCTUnwrap(read.host.everyView(ofType: NSSegmentedControl.self).first,
                                    "\(look): no switcher drawn")
        switch look {
        case .flat:
            XCTAssertTrue(control.cell is HelmFlatSegmentedCell, "\(look): the look did not reach the bar — the cell is \(String(describing: control.cell.map { type(of: $0) }))")
        case .liquidGlass:
            XCTAssertTrue(control.cell.map { type(of: $0) == NSSegmentedCell.self } == true, "\(look): the look did not reach the bar — the cell is \(String(describing: control.cell.map { type(of: $0) }))")
        }
        return control
    }

    func testReDeclaredGlyphsUnderTheSameNamesAreDrawn() throws {
        for look in looks { try assertGlyphsRedrawn(under: look) }
    }

    private func assertGlyphsRedrawn(under look: HelmBarAppearance) throws {
        let before = ["minus", "ellipsis"]
        let after = ["rectangle.3.group", "keyboard"]

        let fresh = mount(look)
        declare(after, on: fresh)
        let expected = try switcher(fresh, look: look)
        let expectedSizes = (0..<expected.segmentCount).map { expected.image(forSegment: $0)?.size }
        // Flat: the fresh switcher's frame. Liquid Glass: the width its cell asks for — the frame of a
        // fresh AppKit control is its first layout's width, which a refilled control does not keep.
        let expectedWidth = look == .flat ? expected.frame.width : expected.intrinsicContentSize.width

        let changed = mount(look)
        declare(before, on: changed)
        let control = try switcher(changed, look: look)
        let beforeSizes = (0..<control.segmentCount).map { control.image(forSegment: $0)?.size }
        let beforeWidth = control.frame.width
        XCTAssertNotEqual(beforeSizes, expectedSizes, "\(look) precondition: the two pairs' images are the same size — a stale switcher cannot be told from a fresh one")
        XCTAssertGreaterThan(abs(expectedWidth - beforeWidth), 0.5, """
            \(look) precondition: the two pairs draw \(beforeWidth) and \(expectedWidth) pt — too close to tell \
            a stale switcher from a fresh one
            """)
        print("[glyph redraw] \(look): cell \(String(describing: control.cell.map { type(of: $0) })), before \(beforeWidth) pt, "
              + "fresh frame \(expected.frame.width) pt, fresh fitting \(expected.fittingSize.width) pt, "
              + "fresh intrinsic \(expected.intrinsicContentSize.width) pt, "
              + "fresh cell size \(expected.cell?.cellSize.width ?? .nan) pt")

        declare(after, on: changed)
        let redrawn = try switcher(changed, look: look)
        XCTAssertTrue(redrawn === control, "\(look) precondition: the capsule rebuilt the switcher, so the cheap path never ran")
        let sizes = (0..<redrawn.segmentCount).map { redrawn.image(forSegment: $0)?.size }
        XCTAssertEqual(sizes, expectedSizes, """
            \(look): the switcher still draws the glyphs it was first given — re-declared as \(after) under the \
            same names, its segments' images are \(sizes), a fresh switcher's are \(expectedSizes)
            """)
        XCTAssertEqual(redrawn.frame.width, expectedWidth, accuracy: 0.5, """
            \(look): the re-declared switcher is \(redrawn.frame.width) pt wide, a fresh one with \(after) \
            \(look == .flat ? "is" : "asks its cell for") \(expectedWidth) pt
            """)
        fresh.window.toolbar = nil
        changed.window.toolbar = nil
        _ = (fresh.toolbar, changed.toolbar)
    }

    func testRenamedOptionsWithTheSameGlyphsAndSelectionAreNamedAnew() throws {
        for look in looks { try assertNamesRedrawn(under: look) }
    }

    private func assertNamesRedrawn(under look: HelmBarAppearance) throws {
        let glyphs = ["minus", "ellipsis"]
        let first = ["First", "Second"]
        let second = ["Premier", "Deuxième"]

        let mounted = mount(look)
        declare(glyphs, titles: first, on: mounted)
        let control = try switcher(mounted, look: look)
        let selected = control.selectedSegment
        XCTAssertEqual((0..<control.segmentCount).map { control.toolTip(forSegment: $0) }, first.map(Optional.some),
                       "\(look) precondition: the tooltips are not the first titles")
        XCTAssertEqual((0..<control.segmentCount).map { control.label(forSegment: $0) ?? "" }, ["", ""],
                       "\(look) precondition: the switcher draws a word, so a refill on a changed word would hide the names")

        declare(glyphs, titles: second, on: mounted)
        let renamed = try switcher(mounted, look: look)
        XCTAssertTrue(renamed === control, "\(look) precondition: the capsule rebuilt the switcher, so the cheap path never ran")
        XCTAssertEqual(renamed.selectedSegment, selected, "\(look) precondition: the selection moved, which alone forces the refill")
        XCTAssertEqual((0..<renamed.segmentCount).map { renamed.toolTip(forSegment: $0) }, second.map(Optional.some), """
            \(look): the switcher still carries its first titles as tooltips — re-declared under new titles \
            with the same glyphs, count and selection, nothing else asks it to refill
            """)
        XCTAssertEqual((0..<renamed.segmentCount).map { renamed.image(forSegment: $0)?.accessibilityDescription },
                       second.map(Optional.some), """
            \(look): the glyphs' accessibility descriptions are not the new titles — VoiceOver would still \
            read the old ones
            """)
        mounted.window.toolbar = nil
        _ = mounted.toolbar
    }
}
