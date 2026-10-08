import AppKit
import SwiftUI
import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **Typing is not asking.**
///
/// **Moved here from `Tests/HelmUITests` with the control it watches.** This
/// file used to mount `.helmSearchable`, SwiftUI's toolbar bridge, deleted
/// once the bar built the search field itself. `HelmToolbarSearch.onSubmit` is the same
/// contract stated as data rather than as a modifier: the binding, which
/// moves on every keystroke because the results on screen are filtered from
/// it, and `onSubmit`, which is the press. The one caller that passes an
/// `onSubmit` sends two `brew search` runs over the network per call — about
/// nine seconds by this app's own measurement — so a closure that ran per
/// keystroke would put four of them out to spell «wget», and the fourth
/// answer would land on top of the third.
///
/// **No keystroke and no end of editing asks.** `ShellBarSearch.init`
/// wires `field.target`/`field.action` to `submitted(_:)` and turns off
/// `sendsActionOnEndEditing`, so Return and the field's clear button are the
/// two routes there, and the zone calls `onSubmit` only when the field is not
/// empty — `MountedRender.pressReturn` drives the first, spelled once and
/// shared with the families `command grep -rl pressReturn Tests` lists. The
/// field is read from the page bar `LivePageToolbarFixture` puts in the window.
@MainActor
final class ASearchRunsOnReturnNotOnAKeyTests: XCTestCase {

    private var savedCollapse: Any?
    private var savedPageBar: Any?
    private var savedBarAppearance: Any?

    /// The bar reads these when it is built, so they are pinned before a fixture is and put back after.
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
        AppSettings.store.set(savedCollapse, for: "alwaysCollapseSearch")
        AppSettings.store.set(savedPageBar, for: PageBarStyle.storageKey)
        AppSettings.store.set(savedBarAppearance, for: HelmBarAppearance.storageKey)
        super.tearDown()
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
        let fixture = LivePageToolbarFixture(Page(tally: tally), selection: .module("test.searchReturn"),
                                             width: 1060, height: 400)
        defer { fixture.drop() }
        fixture.settle(20)
        XCTAssertNotNil(fixture.mount.searchField, """
            the window holds no search field, so neither count below is about a control
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
    /// flag `ShellBarSearch.init` sets.
    ///
    /// Measured directly, this Mac: a bare `NSSearchField()` already answers
    /// `sendsActionOnEndEditing == false`, so this guards what the zone
    /// assigns rather than AppKit's own default. The third path is the bar's
    /// own: a press outside the bar ends the session the field holds
    /// (`ShellBarSearch.pressed(at:in:)`), the decision its event monitor takes.
    func testEndingEditingSubmitsNothing() throws {
        for path in EndPath.allCases {
            let tally = Tally()
            let fixture = LivePageToolbarFixture(Page(tally: tally), selection: .module("test.searchReturn"),
                                                 width: 1060, height: 400)
            defer { fixture.drop() }
            fixture.settle(20)
            guard let field = fixture.mount.searchField, let window = fixture.mount.window else {
                XCTFail("\(path): the window holds no search field")
                continue
            }
            XCTAssertTrue(fixture.mount.type("wget"), "\(path): the field went away mid-word")
            XCTAssertTrue(window.makeFirstResponder(field), "\(path): could not focus the field")
            XCTAssertNotNil(field.currentEditor(), """
                \(path) precondition: the field never actually took editing — ending it below \
                would prove nothing
                """)

            switch path {
            case .resigningFirstResponder:
                _ = window.makeFirstResponder(nil)
            case .aPressOutsideTheBar:
                // The window's bottom-left corner: the bar is at the top of the content.
                fixture.pageBar.search.pressed(at: NSPoint(x: 1, y: 1), in: window)
            case .windowEndEditing:
                window.endEditing(for: field)
            }
            fixture.settle(10)

            XCTAssertEqual(tally.submits, 0, """
                \(path): ending editing fired `onSubmit` \(tally.submits) time(s) — a focus \
                change or a press outside the bar must not be read as the person asking
                """)
        }
    }

    private enum EndPath: String, CaseIterable {
        case resigningFirstResponder, aPressOutsideTheBar, windowEndEditing
    }
}
