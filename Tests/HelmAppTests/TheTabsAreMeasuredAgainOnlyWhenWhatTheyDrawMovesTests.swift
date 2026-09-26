import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The centre tabs' width is measured again for each thing the switcher
/// draws that moved, once, and not for anything else** — every field of
/// `SettingsToolbar.TabsWidthKey` fed alone, on one bar, through a real
/// `SettingsToolbar`.
///
/// `AKeystrokeInHostsSettlesWithoutMeasuringTheTabsTests` proves the other
/// half: a keystroke that moves none of it measures nothing. That file's
/// control declares new *titles* and sees a measurement, so a key that
/// ignored the words goes red there; nothing proved the other fields
/// (tester, 2026-09-26). Here each field is changed with every other held,
/// and read as a count of `SwitcherMeasurementRig` mounts
/// (`SettingsToolbar.measurementsTaken`) across the settle that follows:
/// exactly one for the change, and zero for the same declaration again,
/// because a key that is never consulted also measures exactly once per
/// change — the second reading is what fails if the cache is gone.
///
/// Seen red with each of `style`, `language`, `selectedID`, `titles` and
/// `symbols` left out of the key's equality in turn — each time in the one
/// case here that moves that field and in no other here — with a rebuilt `PageBar`
/// handed the width of the bar it replaced, and, every case, with the
/// cached width never read. **`ids` is not among
/// them, and cannot be**: `ShapeSignature` carries the tab ids, so a
/// declaration whose ids moved gets a fresh `PageBar` with no width at all,
/// and a key without `ids` measures exactly as often — this file says so in
/// `testNewIdsUnderTheSameWordsAreMeasuredOnceOnAFreshBar` rather than
/// claiming a proof it does not have.
///
/// **Every settle here is started by a declaration and never by a
/// notification.** The count is the process's own — one rig for every
/// `SettingsToolbar` there is — and a language or label-style notification
/// reaches every toolbar still alive in the process, each of which would
/// measure its own bar under the new key and land in this count. A page's
/// declaration reaches only this bar; the label style is written to the
/// store without the notification for the same reason, and the style and the
/// language are read by `settle(_:)` itself, not carried by the message.
@MainActor
final class TheTabsAreMeasuredAgainOnlyWhenWhatTheyDrawMovesTests: XCTestCase {

    private struct Bare {
        let toolbar: SettingsToolbar
        let model: SettingsModel
        let channel: HelmWindowToolbarChannel
        let window: NSWindow
        let token: String
    }

    private var bars: [Bare] = []

    override func tearDown() {
        for bar in bars { bar.window.toolbar = nil }
        bars = []
        super.tearDown()
    }

    private func bare(_ token: String) -> Bare {
        let model = SettingsModel(host: ModuleHost.shared)
        let channel = HelmWindowToolbarChannel()
        let toolbar = SettingsToolbar(model: model, channel: channel)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        toolbar.window = window
        model.selection = .module(token)
        let made = Bare(toolbar: toolbar, model: model, channel: channel, window: window, token: token)
        bars.append(made)
        return made
    }

    /// Turns the run loop for `seconds` by the clock — the settle runs from a
    /// timer, and a turn that returns on the first source it serves buys no
    /// time.
    private func rest(_ seconds: TimeInterval) {
        let until = Date().addingTimeInterval(seconds)
        while Date() < until { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
    }

    /// The measurements taken by the settle `body` leads to — a rest four
    /// settle intervals long, so the one the declaration armed has fired.
    private func measured(_ body: () -> Void) -> Int {
        let before = SettingsToolbar.measurementsTaken
        body()
        rest(4 * SettingsToolbar.settleInterval)
        return SettingsToolbar.measurementsTaken - before
    }

    private func tabs(ids: [String] = ["first", "second"], titles: [String] = ["Alpha", "Beta"],
                      symbols: [String] = ["circle", "square"]) -> [HelmToolbarTab] {
        zip(ids, zip(titles, symbols)).map { HelmToolbarTab(id: $0, title: $1.0, symbol: $1.1) }
    }

    /// Tabs only: no `.segmented` action, whose reserve is measured through
    /// the same rig and would land in the same count.
    private func declare(_ bar: Bare, _ tabs: [HelmToolbarTab], selected: String = "first") {
        bar.channel.declare(HelmPageToolbarContent(tabs: tabs, selectedTab: .constant(selected)),
                            token: bar.token, generation: bar.channel.nextGeneration())
    }

    /// The first declaration measures — the subject: this bar's settle does
    /// reach the rig — and the same declaration again measures nothing.
    private func establish(_ bar: Bare, _ tabs: [HelmToolbarTab], selected: String = "first",
                           file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(measured { declare(bar, tabs, selected: selected) }, 1, """
            precondition: the first declaration of tabs onto a fresh bar did not take exactly one \
            measurement — nothing below can be read as a count of settles
            """, file: file, line: line)
        XCTAssertEqual(measured { declare(bar, tabs, selected: selected) }, 0, """
            the same tabs declared again onto the same bar were measured again — the width is not kept
            """, file: file, line: line)
    }

    // MARK: - One field at a time

    func testALabelStyleChangeAloneIsMeasuredOnce() {
        let store = AppSettings.store
        let saved = store.object(ToolbarSwitcherStyle.storageKey)
        addTeardownBlock { @MainActor in
            store.set(saved, for: ToolbarSwitcherStyle.storageKey)
            NotificationCenter.default.post(name: .helmToolbarSwitcherStyleChanged, object: nil)
        }
        store.set(ToolbarSwitcherStyle.text.rawValue, for: ToolbarSwitcherStyle.storageKey)
        let bar = bare("test.tabsWidth.style")
        establish(bar, tabs())
        for style in [ToolbarSwitcherStyle.icons, .iconsAndText, .text] {
            store.set(style.rawValue, for: ToolbarSwitcherStyle.storageKey)
            XCTAssertEqual(AppSettings.toolbarSwitcherStyle, style, "precondition: the store did not take \(style)")
            XCTAssertEqual(measured { declare(bar, tabs()) }, 1, """
                \(style): the tabs were not measured once for a label style they had not been measured in
                """)
            XCTAssertEqual(measured { declare(bar, tabs()) }, 0, """
                \(style): the tabs were measured again in a label style they had just been measured in
                """)
        }
    }

    func testALanguageChangeAloneIsMeasuredOnceInEveryLanguage() {
        // Portuguese first so that the loop's first language, English,
        // differs from it — on a Mac whose own language is English, starting
        // from the Mac's language would make that first step no change at all.
        AppLanguage.only(.pt) {
            let bar = bare("test.tabsWidth.language")
            // The same words in every language: only the language moves.
            establish(bar, tabs())
            AppLanguage.each { language in
                XCTAssertEqual(AppLanguage.current, language, "precondition: the language did not move")
                XCTAssertEqual(measured { declare(bar, tabs()) }, 1, """
                    \(language.rawValue): the tabs were not measured once in a language they had not been \
                    measured in
                    """)
                XCTAssertEqual(measured { declare(bar, tabs()) }, 0, """
                    \(language.rawValue): the tabs were measured again in the language they had just been \
                    measured in
                    """)
            }
        }
    }

    func testAMovedSelectionAloneIsMeasuredOnce() {
        let bar = bare("test.tabsWidth.selection")
        establish(bar, tabs(), selected: "first")
        for selected in ["second", "first", "nothing-by-this-id"] {
            XCTAssertEqual(measured { declare(bar, tabs(), selected: selected) }, 1, """
                selection \(selected): the tabs were not measured once for a selection they had not been \
                measured with
                """)
            XCTAssertEqual(measured { declare(bar, tabs(), selected: selected) }, 0, """
                selection \(selected): the tabs were measured again with the selection they had just been \
                measured with
                """)
        }
    }

    func testNewWordsUnderTheSameIdsAndGlyphsAreMeasuredOnce() {
        let bar = bare("test.tabsWidth.titles")
        establish(bar, tabs())
        let toolbar = bar.window.toolbar
        let longer = tabs(titles: ["Alpha and more", "Beta"])
        XCTAssertEqual(measured { declare(bar, longer) }, 1, "new words were not measured once")
        XCTAssertIdentical(bar.window.toolbar, toolbar, "precondition: new words rebuilt the bar")
        XCTAssertEqual(measured { declare(bar, longer) }, 0, "the same new words were measured again")
    }

    func testNewGlyphsUnderTheSameIdsAndWordsAreMeasuredOnce() {
        let bar = bare("test.tabsWidth.symbols")
        establish(bar, tabs())
        let toolbar = bar.window.toolbar
        let other = tabs(symbols: ["circle", "rectangle.split.3x1"])
        XCTAssertEqual(measured { declare(bar, other) }, 1, "new glyphs were not measured once")
        XCTAssertIdentical(bar.window.toolbar, toolbar, "precondition: new glyphs rebuilt the bar")
        XCTAssertEqual(measured { declare(bar, other) }, 0, "the same new glyphs were measured again")
    }

    /// Ids that moved under the same words, glyphs and selection are measured
    /// once — **by a fresh bar**, which is what the second assertion pins:
    /// `ShapeSignature.tabIDs` rebuilds the bar before `TabsWidthKey.ids` is
    /// ever compared, so this case cannot tell a key with ids from one
    /// without (see this file's header).
    func testNewIdsUnderTheSameWordsAreMeasuredOnceOnAFreshBar() {
        let bar = bare("test.tabsWidth.ids")
        establish(bar, tabs(), selected: "first")
        let toolbar = bar.window.toolbar
        let renamed = tabs(ids: ["one", "two"])
        XCTAssertEqual(measured { declare(bar, renamed, selected: "first") }, 1, "new ids were not measured once")
        XCTAssertNotIdentical(bar.window.toolbar, toolbar, """
            new tab ids kept the same bar — TabsWidthKey.ids is now the only thing that measures them, and \
            this file's header no longer holds
            """)
        XCTAssertEqual(measured { declare(bar, renamed, selected: "first") }, 0, "the same new ids were measured again")
    }

    // MARK: - A rebuilt bar

    /// **A bar rebuilt for its shape measures again, with nothing the tabs
    /// draw having moved** — the width is the bar's and goes with it.
    /// Rebuilt here by an action appearing beside the same tabs, a plain
    /// button, whose kind has no reserve to measure.
    func testARebuiltBarMeasuresTheSameTabsAgain() {
        let bar = bare("test.tabsWidth.rebuilt")
        establish(bar, tabs())
        let toolbar = bar.window.toolbar
        let withAction = HelmPageToolbarContent(
            tabs: tabs(), selectedTab: .constant("first"),
            actions: [HelmToolbarAction(id: "refresh", title: "Refresh", symbol: "arrow.clockwise") {}])
        let count = measured {
            bar.channel.declare(withAction, token: bar.token, generation: bar.channel.nextGeneration())
        }
        XCTAssertNotIdentical(bar.window.toolbar, toolbar, "precondition: a new action id did not rebuild the bar")
        XCTAssertEqual(count, 1, "a rebuilt bar took \(count) measurement(s) of the same tabs, not one")
        let again = measured {
            bar.channel.declare(withAction, token: bar.token, generation: bar.channel.nextGeneration())
        }
        XCTAssertEqual(again, 0, "the rebuilt bar measured the same tabs twice")
    }
}
