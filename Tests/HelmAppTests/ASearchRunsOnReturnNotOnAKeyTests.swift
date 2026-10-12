import AppKit
import SwiftUI
import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **Typing is not asking.**
///
/// **Moved here from `Tests/HelmUITests` with the control it watches.** This
/// file used to mount `.helmSearchable`, SwiftUI's toolbar bridge, which is
/// gone from the tree together with `HelmSearchable.swift` now that
/// `SettingsToolbar` builds the search item itself. `HelmToolbarSearch.onSubmit` is the same
/// contract stated as data rather than as a modifier: the binding, which
/// moves on every keystroke because the results on screen are filtered from
/// it, and `onSubmit`, which is the press. The one caller that passes an
/// `onSubmit` sends two `brew search` runs over the network per call — about
/// nine seconds by this app's own measurement — so a closure that ran per
/// keystroke would put four of them out to spell «wget», and the fourth
/// answer would land on top of the third.
///
/// **Return is a key event and nothing else.** `SettingsToolbar.makeSearchItem`
/// wires `field.target`/`field.action` to `searchSubmitted(_:)` and turns off
/// `sendsActionOnEndEditing`, so the routes there are a Return in the field
/// editor and the field's clear button, which no row here presses —
/// `MountedRender.pressReturn` drives the Return, spelled once and
/// shared with the bridge-era tests this one is a twin of.
///
/// **The field is the toolbar's.** Every row reads the field of the
/// `NSSearchToolbarItem` on the window's own `NSToolbar`
/// (`LivePageInTheToolbarFixture.searchField`) and types into it and presses
/// Return in it through `MountedRender.type` and `.pressReturn`, which act on
/// the field the frame-view walk behind `MountedRender.searchField` meets
/// first. On this fixture that walk answers the toolbar's field: measured
/// 2026-10-13, Flat, once, `fixture.mount.searchField === fixture.searchField`
/// read true. Each row asserts that identity before it counts anything, so a
/// window that came to wear another search field the walk meets first fails
/// the row in its own words and does not pass it for the wrong control. The
/// rows also assert that the field's delegate is the `SettingsToolbar` the
/// fixture built, which `makeSearchItem` sets on the field it assigns to its
/// item.
///
/// **What these rows hold, and what they do not.** They hold the delegate's
/// route: typing writes the binding and asks nothing (`controlTextDidChange`
/// calls no `onSubmit`; a mutant that calls it there turns the first row red
/// at its typing count and at its Return count), Return asks once, and
/// ending editing asks nothing. They do not hold
/// `sendsWholeSearchString`, the flag that governs AppKit's own per-keystroke
/// action: the rows type by setting the field's value and posting the
/// notification a keystroke posts, no field editor edits, so AppKit never
/// has a keystroke to send an action for, and with the flag set to false in
/// `makeSearchItem` both rows stay green. No row here holds that flag.
///
/// **The bar.** A `SettingsToolbar` built with the default lead
/// `.sidebarSeparator` on a bare `NSWindow` (`LivePageInTheToolbarFixture`),
/// not the `lead: .spacer` bar the app's window builds. **The look.** The
/// field is AppKit's under both looks and nothing here reads a width or a
/// cell, so the settings are pinned in `setUp` (`PinnedBarSettings`, Flat, a
/// search that does not always collapse) and the rows are not run under
/// Liquid Glass.
@MainActor
final class ASearchRunsOnReturnNotOnAKeyTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        PinnedBarSettings.pin(in: self)
    }

    /// The counters, on a class so the page can write to them without being
    /// rebuilt into a new copy of itself between keystrokes.
    private final class Tally {
        var text = ""
        /// Writes that actually changed the value. SwiftUI calls a binding's
        /// setter more than once per change, so counting calls would count the
        /// framework's bookkeeping rather than the keystrokes.
        var moves = 0
        var submits = 0
    }

    private struct Page: View {
        let tally: Tally
        var body: some View {
            Text("the list")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .helmWindowToolbar(HelmPageToolbarContent(search: HelmToolbarSearch(
                    prompt: "Search packages",
                    text: Binding(get: { tally.text }, set: {
                        guard $0 != tally.text else { return }
                        tally.text = $0
                        tally.moves += 1
                    }),
                    onSubmit: { tally.submits += 1 })), token: "test.searchReturn")
        }
    }

    func testFourKeystrokesMoveTheBindingAndAskNothing() throws {
        let tally = Tally()
        let fixture = LivePageInTheToolbarFixture(Page(tally: tally), selection: .module("test.searchReturn"),
                                                  width: 1060, height: 400)
        defer { fixture.drop() }
        fixture.settle(20)
        let field = try XCTUnwrap(fixture.searchField, """
            nothing reached the window's toolbar, so neither count below is about a control
            """)
        XCTAssertTrue(field.delegate === fixture.toolbar, """
            the field is not the one the window's SettingsToolbar built for its search item — \
            neither count below is about the control this app wears
            """)
        XCTAssertTrue(fixture.mount.searchField === field, """
            the frame-view walk behind `MountedRender.type` and `.pressReturn` does not meet the \
            toolbar's field — they would type into another control and neither count below is \
            about the toolbar's
            """)

        for word in ["w", "wg", "wge", "wget"] {
            XCTAssertTrue(fixture.mount.type(word), "the field went away mid-word at «\(word)»")
        }
        XCTAssertEqual(tally.text, "wget", "the keystrokes did not reach the binding at all")
        XCTAssertEqual(tally.moves, 4, """
            four keystrokes moved the binding \(tally.moves) times — a list filtered from this \
            binding redraws on every letter, so anything but four is a page that lags behind \
            what is typed or redraws over nothing
            """)
        XCTAssertEqual(tally.submits, 0, """
            typing asked \(tally.submits) searches. Each one is two `brew search` runs over the \
            network, so a search per letter is four of them out at once for one word
            """)

        XCTAssertTrue(fixture.mount.pressReturn(), "Return never reached the field")
        XCTAssertEqual(tally.submits, 1, """
            Return fired `onSubmit` \(tally.submits) times where it is the one press that asks \
            — nothing at all means the network search can no longer be started
            """)
        XCTAssertEqual(tally.moves, 4, "Return moved the binding, which is the typing's job")
    }

    /// **Ending editing must not submit.** The field editor genuinely has to
    /// be attached first — `field.currentEditor() != nil` — or every path
    /// below submits nothing regardless of `sendsActionOnEndEditing`, which
    /// is the harness gap that once read this as a check that cannot fail: a
    /// mount that only types (`mount.type`) never focuses the field, so
    /// ending an editing session that never began proves nothing about the
    /// flag `makeSearchItem` sets.
    ///
    /// The `[search]` line each path prints is `window.isKeyWindow` after the
    /// field took focus, the row's evidence that the window did not turn key
    /// (false on all three paths, 2026-10-13): the editing these paths end
    /// took place in a window that was not key.
    ///
    /// Measured directly, this Mac: a bare `NSSearchField()` — what
    /// `makeSearchItem` builds — already answers `sendsActionOnEndEditing ==
    /// false`, so this guards the field `SettingsToolbar` actually assigns
    /// rather than AppKit's own default, which is `true` for
    /// `NSSearchToolbarItem`'s own field before ours replaces it. Mutation,
    /// confirmed by running it against a copy of the fixed tree and restoring
    /// from that copy afterward, never with `git checkout`: set
    /// `field.cell?.sendsActionOnEndEditing = true` in `makeSearchItem`
    /// (`NSSearchToolbarItem`'s own default for the field it starts with),
    /// and every path below submits once instead of zero times.
    func testEndingEditingSubmitsNothing() throws {
        for path in EndPath.allCases {
            let tally = Tally()
            let fixture = LivePageInTheToolbarFixture(Page(tally: tally), selection: .module("test.searchReturn"),
                                                      width: 1060, height: 400)
            defer { fixture.drop() }
            fixture.settle(20)
            guard let field = fixture.searchField, let window = fixture.mount.window else {
                XCTFail("\(path): nothing reached the window's toolbar")
                continue
            }
            XCTAssertTrue(field.delegate === fixture.toolbar, """
                \(path) precondition: the field is not the one the window's SettingsToolbar built \
                for its search item
                """)
            XCTAssertTrue(fixture.mount.searchField === field, """
                \(path) precondition: the frame-view walk behind `MountedRender.type` does not meet \
                the toolbar's field — it would type into another control
                """)
            XCTAssertTrue(fixture.mount.type("wget"), "\(path): the field went away mid-word")
            XCTAssertTrue(window.makeFirstResponder(field), "\(path): could not focus the field")
            print("[search] \(path): window key after focusing the field: \(window.isKeyWindow)")
            XCTAssertNotNil(field.currentEditor(), """
                \(path) precondition: the field never actually took editing — ending it below \
                would prove nothing
                """)

            switch path {
            case .resigningFirstResponder:
                _ = window.makeFirstResponder(nil)
            case .endingTheSearchInteraction:
                guard let item = window.toolbar?.items
                    .compactMap({ $0 as? NSSearchToolbarItem }).first
                else {
                    XCTFail("\(path): no search item to end an interaction on")
                    continue
                }
                item.endSearchInteraction()
            case .windowEndEditing:
                window.endEditing(for: field)
            }
            fixture.settle(10)

            XCTAssertEqual(tally.submits, 0, """
                \(path): ending editing fired `onSubmit` \(tally.submits) time(s) — a focus \
                change or a fold must not be read as the person asking
                """)
        }
    }

    private enum EndPath: String, CaseIterable {
        case resigningFirstResponder, endingTheSearchInteraction, windowEndEditing
    }
}
