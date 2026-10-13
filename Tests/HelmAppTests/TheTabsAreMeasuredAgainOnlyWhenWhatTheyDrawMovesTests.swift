import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The centre tabs' width is measured again for each thing the switcher
/// draws that moved, once, and not for anything else** — five fields of
/// `SettingsToolbar.TabsWidthKey` (`style`, `language`, `selectedID`,
/// `titles`, `symbols`) fed alone, one case each, on one bar, through a real
/// `SettingsToolbar`.
///
/// `AKeystrokeInHostsSettlesWithoutMeasuringTheTabsTests` proves the other
/// half: a keystroke that moves none of it measures nothing. That file's
/// control declares new *titles* and sees a measurement, so a key that
/// ignored the words goes red there. Here each of the five fields is changed
/// with the fields named in the cases held, and read as a count of
/// `SwitcherMeasurementRig` mounts (`SettingsToolbar.measurementsTaken`)
/// across the settle that follows: exactly one for the change, and zero for
/// the same declaration again, because a key that is never consulted also
/// measures exactly once per change — the second reading is what fails if the
/// cache is gone.
///
/// **What the rows hold.** The line of `wholeTabsWidth(_:_:)` that returns the
/// kept width when its key matches. With that line taken out every row of this
/// file goes red under both looks, each at a count of measurements above what
/// it expects. `style`, `language`, `selectedID`, `titles` and `symbols` are
/// each moved by the one case here named for it and by no other here.
/// **`attention` is moved by no case here.** **`ids` is moved by
/// `testNewIdsUnderTheSameWordsAreMeasuredOnceOnAFreshBar`, but that case
/// cannot tell a key with `ids` from one without**: `ShapeSignature` carries
/// the tab ids, so a declaration whose ids moved gets a fresh `PageBar` with no
/// width at all, and a key without `ids` measures exactly as often — the case
/// says so rather than claiming a proof it does not have.
///
/// **Every settle here is started by a declaration and never by a
/// notification.** The count is the process's own — one rig for every
/// `SettingsToolbar` there is — and a language or label-style notification
/// reaches every toolbar still alive in the process, each of which would
/// measure its own bar under the new key and land in this count. A page's
/// declaration reaches only this bar; the label style is written to the
/// store without the notification for the same reason, and the style and the
/// language are read by `settle(_:)` itself, not carried by the message.
///
/// **The bar.** A `SettingsToolbar` built with the default lead
/// `.sidebarSeparator` on a bare `NSWindow`, not the `lead: .spacer` bar the
/// app's window builds: it has no `helm.tabsLead` and no capped search field.
/// The count is the toolbar's own (`SettingsToolbar.measurementsTaken`), not
/// the page bar's `ShellBarTabs.measureCount`.
///
/// **The look.** It is read when a bar is built (`AppSettings.barAppearance`)
/// and sits on the bar's shape (`ShapeSignature.look`), not on `TabsWidthKey`:
/// a width measured wearing one look's cell lives on a bar that is not given
/// back under the other. The tabs are measured in the look's own cell, so
/// every row builds its bars under Flat and again under Liquid Glass
/// (`underEachLook`; each row is one short loop) and asserts, from the tabs
/// item's cell, that the look reached it. The other settings the bar reads
/// are pinned in `setUp` (`PinnedBarSettings`); the label-style row moves the
/// label style itself.
@MainActor
final class TheTabsAreMeasuredAgainOnlyWhenWhatTheyDrawMovesTests: XCTestCase {

    private struct Bare {
        let toolbar: SettingsToolbar
        let model: SettingsModel
        let channel: HelmWindowToolbarChannel
        let window: NSWindow
        let token: String
        let look: HelmBarAppearance
    }

    private var bars: [Bare] = []

    override func setUp() async throws {
        try await super.setUp()
        PinnedBarSettings.pin(in: self)
        // A teardown override is nonisolated and warns on every main-actor property it touches.
        addTeardownBlock { @MainActor [self] in
            for bar in bars { bar.window.toolbar = nil }
            bars = []
        }
    }

    /// Runs `body` once under each look; the bars it builds wear that look. The bars of one look are dropped
    /// before the next look is written: a look written reaches every toolbar still alive
    /// (`.helmBarAppearanceChanged`), and each would rebuild under it and land its measurement in the count.
    private func underEachLook(_ body: (HelmBarAppearance) -> Void) {
        for look in HelmBarAppearance.allCases {
            body(look)
            for bar in bars { bar.window.toolbar = nil }
            bars = []
        }
    }

    private func bare(_ token: String, look: HelmBarAppearance) -> Bare {
        AppSettings.barAppearance = look
        let model = SettingsModel(host: ModuleHost.shared)
        let channel = HelmWindowToolbarChannel()
        let toolbar = SettingsToolbar(model: model, channel: channel)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        toolbar.window = window
        model.selection = .module(token)
        let made = Bare(toolbar: toolbar, model: model, channel: channel, window: window, token: token, look: look)
        bars.append(made)
        return made
    }

    /// The measurements taken by the settle `body` leads to — a rest four
    /// settle intervals long, so the one the declaration armed has fired.
    private func measured(_ body: () -> Void) -> Int {
        let before = SettingsToolbar.measurementsTaken
        body()
        PinnedBarSettings.rest(4 * SettingsToolbar.settleInterval)
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

    /// The look the tabs item's switcher is drawn in, read off its cell: Helm's own cell under Flat,
    /// AppKit's under Liquid Glass; nil when the bar has no tabs control.
    private func lookDrawn(by bar: Bare) -> HelmBarAppearance? {
        let item = bar.window.toolbar?.items.first { $0.itemIdentifier.rawValue == "helm.tabs" }
        guard let control = item?.view?.everyView(ofType: NSSegmentedControl.self).first else { return nil }
        return control.cell is HelmFlatSegmentedCell ? .flat : .liquidGlass
    }

    /// The first declaration measures — the subject: this bar's settle does
    /// reach the rig — and the same declaration again measures nothing.
    private func establish(_ bar: Bare, _ tabs: [HelmToolbarTab], selected: String = "first",
                           file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(measured { declare(bar, tabs, selected: selected) }, 1, """
            \(bar.look): precondition: the first declaration of tabs onto a fresh bar did not take exactly \
            one measurement — nothing below can be read as a count of settles
            """, file: file, line: line)
        XCTAssertEqual(lookDrawn(by: bar), bar.look, """
            \(bar.look): precondition: the tabs item's switcher is drawn in \
            \(lookDrawn(by: bar).map { String(describing: $0) } ?? "no control at all"), not the look the \
            bar was built under — the counts below would be read under the wrong cell
            """, file: file, line: line)
        XCTAssertEqual(measured { declare(bar, tabs, selected: selected) }, 0, """
            \(bar.look): the same tabs declared again onto the same bar were measured again — the width is \
            not kept
            """, file: file, line: line)
    }

    // MARK: - One field at a time

    func testALabelStyleChangeAloneIsMeasuredOnce() {
        let store = AppSettings.store
        underEachLook { look in
            store.set(ToolbarSwitcherStyle.text.rawValue, for: ToolbarSwitcherStyle.storageKey)
            let bar = bare("test.tabsWidth.style.\(look.rawValue)", look: look)
            establish(bar, tabs())
            for style in [ToolbarSwitcherStyle.icons, .iconsAndText, .text] {
                store.set(style.rawValue, for: ToolbarSwitcherStyle.storageKey)
                XCTAssertEqual(AppSettings.toolbarSwitcherStyle, style, "precondition: the store did not take \(style)")
                XCTAssertEqual(measured { declare(bar, tabs()) }, 1, """
                    \(look), \(style): the tabs were not measured once for a label style they had not been \
                    measured in
                    """)
                XCTAssertEqual(measured { declare(bar, tabs()) }, 0, """
                    \(look), \(style): the tabs were measured again in a label style they had just been \
                    measured in
                    """)
            }
        }
    }

    func testALanguageChangeAloneIsMeasuredOnceInEveryLanguage() {
        // Portuguese first so that the loop's first language, English,
        // differs from it — on a Mac whose own language is English, starting
        // from the Mac's language would make that first step no change at all.
        AppLanguage.only(.pt) {
            underEachLook { look in
                let bar = bare("test.tabsWidth.language.\(look.rawValue)", look: look)
                // The same words in every language: only the language moves.
                establish(bar, tabs())
                AppLanguage.each { language in
                    XCTAssertEqual(AppLanguage.current, language, "precondition: the language did not move")
                    XCTAssertEqual(measured { declare(bar, tabs()) }, 1, """
                        \(look), \(language.rawValue): the tabs were not measured once in a language they had \
                        not been measured in
                        """)
                    XCTAssertEqual(measured { declare(bar, tabs()) }, 0, """
                        \(look), \(language.rawValue): the tabs were measured again in the language they had \
                        just been measured in
                        """)
                }
            }
        }
    }

    func testAMovedSelectionAloneIsMeasuredOnce() {
        underEachLook { look in
            let bar = bare("test.tabsWidth.selection.\(look.rawValue)", look: look)
            establish(bar, tabs(), selected: "first")
            for selected in ["second", "first", "nothing-by-this-id"] {
                XCTAssertEqual(measured { declare(bar, tabs(), selected: selected) }, 1, """
                    \(look), selection \(selected): the tabs were not measured once for a selection they had \
                    not been measured with
                    """)
                XCTAssertEqual(measured { declare(bar, tabs(), selected: selected) }, 0, """
                    \(look), selection \(selected): the tabs were measured again with the selection they had \
                    just been measured with
                    """)
            }
        }
    }

    func testNewWordsUnderTheSameIdsAndGlyphsAreMeasuredOnce() {
        underEachLook { look in
            let bar = bare("test.tabsWidth.titles.\(look.rawValue)", look: look)
            establish(bar, tabs())
            let toolbar = bar.window.toolbar
            let longer = tabs(titles: ["Alpha and more", "Beta"])
            XCTAssertEqual(measured { declare(bar, longer) }, 1, "\(look): new words were not measured once")
            XCTAssertIdentical(bar.window.toolbar, toolbar, "\(look): precondition: new words rebuilt the bar")
            XCTAssertEqual(measured { declare(bar, longer) }, 0, "\(look): the same new words were measured again")
        }
    }

    func testNewGlyphsUnderTheSameIdsAndWordsAreMeasuredOnce() {
        underEachLook { look in
            let bar = bare("test.tabsWidth.symbols.\(look.rawValue)", look: look)
            establish(bar, tabs())
            let toolbar = bar.window.toolbar
            let other = tabs(symbols: ["circle", "rectangle.split.3x1"])
            XCTAssertEqual(measured { declare(bar, other) }, 1, "\(look): new glyphs were not measured once")
            XCTAssertIdentical(bar.window.toolbar, toolbar, "\(look): precondition: new glyphs rebuilt the bar")
            XCTAssertEqual(measured { declare(bar, other) }, 0, "\(look): the same new glyphs were measured again")
        }
    }

    /// Ids that moved under the same words, glyphs and selection are measured
    /// once — **by a fresh bar**, which is what the second assertion pins:
    /// `ShapeSignature.tabIDs` rebuilds the bar before `TabsWidthKey.ids` is
    /// ever compared, so this case cannot tell a key with ids from one
    /// without (see this file's header).
    func testNewIdsUnderTheSameWordsAreMeasuredOnceOnAFreshBar() {
        underEachLook { look in
            let bar = bare("test.tabsWidth.ids.\(look.rawValue)", look: look)
            establish(bar, tabs(), selected: "first")
            let toolbar = bar.window.toolbar
            let renamed = tabs(ids: ["one", "two"])
            XCTAssertEqual(measured { declare(bar, renamed, selected: "first") }, 1, "\(look): new ids were not measured once")
            XCTAssertNotIdentical(bar.window.toolbar, toolbar, """
                \(look): new tab ids kept the same bar — TabsWidthKey.ids is now the only thing that measures \
                them, and this file's header no longer holds
                """)
            XCTAssertEqual(measured { declare(bar, renamed, selected: "first") }, 0, "\(look): the same new ids were measured again")
        }
    }

    // MARK: - A rebuilt bar

    /// **A bar rebuilt for its shape measures again, with nothing the tabs
    /// draw having moved** — the width is the bar's and goes with it.
    /// Rebuilt here by an action appearing beside the same tabs, a plain
    /// button, whose kind has no reserve to measure.
    func testARebuiltBarMeasuresTheSameTabsAgain() {
        underEachLook { look in
            let bar = bare("test.tabsWidth.rebuilt.\(look.rawValue)", look: look)
            establish(bar, tabs())
            let toolbar = bar.window.toolbar
            let withAction = HelmPageToolbarContent(
                tabs: tabs(), selectedTab: .constant("first"),
                actions: [HelmToolbarAction(id: "refresh", title: "Refresh", symbol: "arrow.clockwise") {}])
            let count = measured {
                bar.channel.declare(withAction, token: bar.token, generation: bar.channel.nextGeneration())
            }
            XCTAssertNotIdentical(bar.window.toolbar, toolbar, "\(look): precondition: a new action id did not rebuild the bar")
            XCTAssertEqual(count, 1, "\(look): a rebuilt bar took \(count) measurement(s) of the same tabs, not one")
            let again = measured {
                bar.channel.declare(withAction, token: bar.token, generation: bar.channel.nextGeneration())
            }
            XCTAssertEqual(again, 0, "\(look): the rebuilt bar measured the same tabs twice")
        }
    }
}
