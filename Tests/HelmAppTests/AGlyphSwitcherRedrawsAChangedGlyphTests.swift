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
/// the reserve measured the new pair at 85.0 (`ShellBarActions.segmentedReserveWidth(_:appearance:)` is this
/// file's page bar's measurer, `SettingsToolbar.segmentedReserveWidth(_:look:)` the window's toolbar's) — the
/// switcher stale and the reserve 12 pt past it. The capsule's
/// switcher is always `.icons`, so it is always in the one style where a
/// glyph is all that is drawn. No page changes an option's glyph today
/// (Hosts' and Homebrew's are literals); the same cheap path carried this for
/// the centre tabs in `.icons` and `.iconsAndText`. Seen red again (tester,
/// 2026-09-26) with `symbolsChanged` taken out of the refill condition in the
/// tree it guards: the segments' images still 14.0 × 4.0 and 14.0 × 5.0
/// against a fresh switcher's 21.0 × 14.0 and 19.0 × 13.0, and 73.0 pt wide
/// against 85.0.
///
/// Compared against a bar built fresh with the second pair rather than
/// against a number, so the check follows whatever this Mac draws.
@MainActor
final class AGlyphSwitcherRedrawsAChangedGlyphTests: XCTestCase {

    private struct Mounted {
        let pageBar: MountedPageBar
        let channel: HelmWindowToolbarChannel
        let window: NSWindow
    }

    private var savedCollapse: Any?
    private var savedPageBar: Any?
    private var savedBarAppearance: Any?
    private var mounted: [Mounted] = []

    /// The bar reads these when it is built, so they are pinned before one is and put back after.
    override func setUp() {
        super.setUp()
        savedCollapse = AppSettings.store.object("alwaysCollapseSearch")
        savedPageBar = AppSettings.store.object(PageBarStyle.storageKey)
        savedBarAppearance = AppSettings.store.object(HelmBarAppearance.storageKey)
        AppSettings.pageBarStyle = .windowTitle
        AppSettings.barAppearance = .flat
        AppSettings.alwaysCollapseSearch = false
    }

    override func tearDown() {
        mounted.forEach { $0.pageBar.remove() }
        mounted = []
        AppSettings.store.set(savedCollapse, for: "alwaysCollapseSearch")
        AppSettings.store.set(savedPageBar, for: PageBarStyle.storageKey)
        AppSettings.store.set(savedBarAppearance, for: HelmBarAppearance.storageKey)
        super.tearDown()
    }

    private func mount() -> Mounted {
        let model = SettingsModel(host: ModuleHost.shared)
        let channel = HelmWindowToolbarChannel()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        model.selection = .module("test.changedGlyph")
        let made = Mounted(pageBar: MountedPageBar(model: model, channel: channel, in: window),
                           channel: channel, window: window)
        mounted.append(made)
        return made
    }

    private func declare(_ glyphs: [String], on mounted: Mounted) {
        mounted.channel.declare(HelmPageToolbarContent(actions: [
            HelmToolbarAction(id: "viewMode", title: "View", options: [
                HelmToolbarTab(id: "first", title: "First", symbol: glyphs[0]),
                HelmToolbarTab(id: "second", title: "Second", symbol: glyphs[1]),
            ], selection: .constant("first")),
        ]), token: "test.changedGlyph", generation: mounted.channel.nextGeneration())
        mounted.pageBar.layout()
    }

    /// The switcher the bar in the window holds in its actions zone, found by a walk down from the
    /// window's frame view and held to be the mounted bar's own zone.
    private func switcher(_ mounted: Mounted) throws -> NSSegmentedControl {
        let found = mounted.window.contentView?.superview?.everyView(ofType: ShellPageBarView.self).first
        let zone = try XCTUnwrap(found?.view(for: .actions), "the bar in the window holds no actions zone")
        XCTAssertTrue(found === mounted.pageBar.bar.view, "the bar in the window is not the mounted bar")
        return try XCTUnwrap(zone.everyView(ofType: NSSegmentedControl.self).first, "no switcher drawn")
    }

    func testReDeclaredGlyphsUnderTheSameNamesAreDrawn() throws {
        let before = ["minus", "ellipsis"]
        let after = ["rectangle.3.group", "keyboard"]

        let fresh = mount()
        declare(after, on: fresh)
        let expected = try switcher(fresh)
        let expectedSizes = (0..<expected.segmentCount).map { expected.image(forSegment: $0)?.size }
        let expectedWidth = expected.frame.width

        let changed = mount()
        declare(before, on: changed)
        let control = try switcher(changed)
        let beforeWidth = control.frame.width
        let beforeSizes = (0..<control.segmentCount).map { control.image(forSegment: $0)?.size }
        XCTAssertNotEqual(beforeSizes, expectedSizes, "precondition: the two pairs draw the same images")
        XCTAssertGreaterThan(abs(expectedWidth - beforeWidth), 0.5, """
            precondition: the two pairs draw \(beforeWidth) and \(expectedWidth) pt — closer than the \
            0.5 pt the width check below reads to, so it could not tell a stale switcher from a fresh one
            """)

        declare(after, on: changed)
        let redrawn = try switcher(changed)
        XCTAssertTrue(redrawn === control, "precondition: the capsule rebuilt the switcher, so the cheap path never ran")
        let sizes = (0..<redrawn.segmentCount).map { redrawn.image(forSegment: $0)?.size }
        XCTAssertEqual(sizes, expectedSizes, """
            the switcher still draws the glyphs it was first given — re-declared as \(after) under the \
            same names, its segments' images are \(sizes), a fresh switcher's are \(expectedSizes)
            """)
        XCTAssertEqual(redrawn.frame.width, expectedWidth, accuracy: 0.5, """
            the re-declared switcher is \(redrawn.frame.width) pt wide, a fresh one with \(after) is \
            \(expectedWidth) pt
            """)
    }
}
