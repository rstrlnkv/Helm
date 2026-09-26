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
/// `SettingsToolbar.segmentedReserveWidth(_:)` measured the new pair at
/// 85.0 — the switcher stale and the reserve 12 pt past it. The capsule's
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
        let toolbar: SettingsToolbar
        let channel: HelmWindowToolbarChannel
        let window: NSWindow
    }

    private func mount() -> Mounted {
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

    private func declare(_ glyphs: [String], on mounted: Mounted) {
        mounted.channel.declare(HelmPageToolbarContent(actions: [
            HelmToolbarAction(id: "viewMode", title: "View", options: [
                HelmToolbarTab(id: "first", title: "First", symbol: glyphs[0]),
                HelmToolbarTab(id: "second", title: "Second", symbol: glyphs[1]),
            ], selection: .constant("first")),
        ]), token: "test.changedGlyph", generation: mounted.channel.nextGeneration())
        mounted.window.layoutIfNeeded()
    }

    private func switcher(_ mounted: Mounted) throws -> NSSegmentedControl {
        let hosting = try XCTUnwrap(mounted.window.toolbar?.items
            .first { $0.itemIdentifier.rawValue == "helm.actions" }?
            .view as? NSHostingView<HelmToolbarActionsCapsule>, "no hosted capsule")
        return try XCTUnwrap(hosting.everyView(ofType: NSSegmentedControl.self).first, "no switcher drawn")
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
        XCTAssertGreaterThan(abs(expectedWidth - beforeWidth), 4, """
            precondition: the two pairs draw \(beforeWidth) and \(expectedWidth) pt — too close to tell \
            a stale switcher from a fresh one
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
        fresh.window.toolbar = nil
        changed.window.toolbar = nil
        _ = (fresh.toolbar, changed.toolbar)
    }
}
