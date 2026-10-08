import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The centre tabs' width is measured again for each thing the switcher draws that moved, once, and not
/// for anything else** — the label style, the bar's look, the selected tab, the titles and the glyphs of the
/// shape `ShellBarTabs` compares, each fed alone, on one page bar, through a page's declarations and the
/// settings the bar hears; a dot is fed only in `TheBarsTabsFoldByTheLayoutsVerdictTests`.
///
/// The zone reads both of its natural widths when a show carries a shape (titles, glyphs, dots, label style,
/// selected tab, the bar's look) other than the one it drew, and counts it in `measureCount`; it re-roots its
/// hosts when anything it draws moved, and counts that in `redrawCount`. Each case moves one field with every
/// other held and reads both counts across the settle that follows: one measurement and one redraw for the
/// change, none of either for the same state again — the second reading is what fails if the comparison is
/// gone. The tab ids, the words' language and an action beside the tabs are not in the shape: a declaration
/// that moves only those redraws or draws nothing, and measures nothing. `TheBarsTabsFoldByTheLayoutsVerdictTests`
/// holds the same counts on the zone alone, against an oracle's widths; here the change arrives the way a
/// page's and the settings' do.
///
/// `AKeystrokeInHostsSettlesWithoutMeasuringTheTabsTests` is the other half: a keystroke that moves none of
/// it measures nothing.
///
/// **Every "again" reading first proves the zone was shown the state.** The page's `selectedTab` binding
/// counts its reads, and `ShellBarTabs.show` reads it on every show before it compares: a still count on a
/// bar the change never reached would read as a pass, so each case also requires the reads to have moved.
/// The counts are the zone's own, per bar: a notification that reaches every bar alive in the process moves
/// only the counts of the bar that owns them.
@MainActor
final class TheTabsAreMeasuredAgainOnlyWhenWhatTheyDrawMovesTests: XCTestCase {

    private final class Reads { var count = 0 }

    private struct Bare {
        let fixture: LivePageToolbarFixture
        let token: String
        let reads: Reads
        var zone: ShellBarTabs { fixture.pageBar.tabs }
    }

    private var bars: [Bare] = []

    override func tearDown() {
        for bar in bars { bar.fixture.drop() }
        bars = []
        super.tearDown()
    }

    private func bare(_ token: String) -> Bare {
        if bars.isEmpty { PinnedBarSettings.pin(in: self) }
        let fixture = LivePageToolbarFixture(EmptyView(), selection: .module(token), width: 1060, height: 700)
        let made = Bare(fixture: fixture, token: token, reads: Reads())
        bars.append(made)
        return made
    }

    private struct Taken: Equatable {
        var measured: Int
        var redrawn: Int
        var reads: Int
    }

    /// What the zone did across `body` and the settle that follows it.
    private func taken(_ bar: Bare, _ body: () -> Void) -> Taken {
        let before = Taken(measured: bar.zone.measureCount, redrawn: bar.zone.redrawCount, reads: bar.reads.count)
        body()
        bar.fixture.settle(3)
        return Taken(measured: bar.zone.measureCount - before.measured,
                     redrawn: bar.zone.redrawCount - before.redrawn,
                     reads: bar.reads.count - before.reads)
    }

    private func tabs(ids: [String] = ["first", "second"], titles: [String] = ["Alpha", "Beta"],
                      symbols: [String] = ["circle", "square"]) -> [HelmToolbarTab] {
        zip(ids, zip(titles, symbols)).map { HelmToolbarTab(id: $0, title: $1.0, symbol: $1.1) }
    }

    private func declare(_ bar: Bare, _ tabs: [HelmToolbarTab], selected: String = "first",
                         actions: [HelmToolbarAction] = []) {
        let reads = bar.reads
        let selection = Binding<String>(get: { MainActor.assumeIsolated { reads.count += 1 }; return selected },
                                        set: { _ in })
        bar.fixture.channel.declare(HelmPageToolbarContent(tabs: tabs, selectedTab: selection, actions: actions),
                                    token: bar.token, generation: bar.fixture.channel.nextGeneration())
    }

    private func assertOnce(_ got: Taken, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(got.measured, 1, "\(what): not measured exactly once (\(got.measured))", file: file, line: line)
        XCTAssertEqual(got.redrawn, 1, "\(what): not redrawn exactly once (\(got.redrawn))", file: file, line: line)
        XCTAssertGreaterThan(got.reads, 0, "\(what): the zone was never shown the state", file: file, line: line)
    }

    private func assertNothing(_ got: Taken, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(got.measured, 0, "\(what): measured again (\(got.measured))", file: file, line: line)
        XCTAssertEqual(got.redrawn, 0, "\(what): redrawn again (\(got.redrawn))", file: file, line: line)
        XCTAssertGreaterThan(got.reads, 0, "\(what): the zone was never shown the state — a still count means nothing",
                             file: file, line: line)
    }

    /// The first declaration measures — the subject: this bar's zone does count — and the same declaration
    /// again measures and draws nothing.
    private func establish(_ bar: Bare, _ declared: [HelmToolbarTab], selected: String = "first",
                           file: StaticString = #filePath, line: UInt = #line) {
        assertOnce(taken(bar) { declare(bar, declared, selected: selected) }, "the first declaration onto a fresh bar",
                   file: file, line: line)
        assertNothing(taken(bar) { declare(bar, declared, selected: selected) }, "the same declaration again",
                      file: file, line: line)
    }

    // MARK: - One field at a time

    func testALabelStyleChangeAloneIsMeasuredOnce() {
        let bar = bare("test.tabsWidth.style")
        establish(bar, tabs())
        for style in [ToolbarSwitcherStyle.icons, .iconsAndText, .text] {
            assertOnce(taken(bar) { AppSettings.toolbarSwitcherStyle = style }, "\(style) from another style")
            XCTAssertEqual(AppSettings.toolbarSwitcherStyle, style, "precondition: the store did not take \(style)")
            assertNothing(taken(bar) { AppSettings.toolbarSwitcherStyle = style }, "\(style) again")
        }
    }

    func testTheBarsLookAloneIsMeasuredOnce() {
        let bar = bare("test.tabsWidth.look")
        establish(bar, tabs())
        for look in [HelmBarAppearance.liquidGlass, .flat] {
            assertOnce(taken(bar) { AppSettings.barAppearance = look }, "\(look) from the other look")
            XCTAssertEqual(AppSettings.barAppearance, look, "precondition: the store did not take \(look)")
            assertNothing(taken(bar) { AppSettings.barAppearance = look }, "\(look) again")
        }
    }

    /// The words are the same in every language: only the language moves. A language is not in the shape, so
    /// nothing is measured; the bar's own name for the control follows it, which is the redraw.
    func testALanguageChangeAloneIsNeverMeasuredAndReachesTheZone() {
        AppLanguage.only(.pt) {
            let bar = bare("test.tabsWidth.language")
            establish(bar, tabs())
            var redrawnAnywhere = 0
            AppLanguage.each { language in
                XCTAssertEqual(AppLanguage.current, language, "precondition: the language did not move")
                let got = taken(bar) { NotificationCenter.default.post(name: .helmLanguageChanged, object: nil) }
                XCTAssertEqual(got.measured, 0, "\(language.rawValue): the same words were measured again (\(got.measured))")
                XCTAssertGreaterThan(got.reads, 0, "\(language.rawValue): the language change never reached the zone")
                redrawnAnywhere += got.redrawn
            }
            XCTAssertGreaterThan(redrawnAnywhere, 0, """
                no language change redrew the zone: the notification reaches nothing, and the zero measurements \
                above are about no change
                """)
        }
    }

    func testAMovedSelectionAloneIsMeasuredOnce() {
        let bar = bare("test.tabsWidth.selection")
        establish(bar, tabs(), selected: "first")
        for selected in ["second", "first", "nothing-by-this-id"] {
            assertOnce(taken(bar) { declare(bar, tabs(), selected: selected) }, "selection \(selected)")
            assertNothing(taken(bar) { declare(bar, tabs(), selected: selected) }, "selection \(selected) again")
        }
    }

    func testNewWordsUnderTheSameIdsAndGlyphsAreMeasuredOnce() {
        let bar = bare("test.tabsWidth.titles")
        establish(bar, tabs())
        let plate = bar.zone.view
        let longer = tabs(titles: ["Alpha and more", "Beta"])
        assertOnce(taken(bar) { declare(bar, longer) }, "new words")
        XCTAssertNotNil(plate, "precondition: the zone had no view")
        XCTAssertIdentical(bar.zone.view, plate, "new words replaced the zone's view")
        assertNothing(taken(bar) { declare(bar, longer) }, "the same new words")
    }

    func testNewGlyphsUnderTheSameIdsAndWordsAreMeasuredOnce() {
        let bar = bare("test.tabsWidth.symbols")
        establish(bar, tabs())
        let other = tabs(symbols: ["circle", "rectangle.split.3x1"])
        assertOnce(taken(bar) { declare(bar, other) }, "new glyphs")
        assertNothing(taken(bar) { declare(bar, other) }, "the same new glyphs")
    }

    // MARK: - What is not in the shape

    /// Ids that moved under the same words, glyphs and selection are redrawn (the controls answer to the
    /// ids) and not measured: a width is a function of the words, the glyphs, the dots, the label style, the
    /// selection and the bar's look.
    func testNewIdsUnderTheSameWordsAreRedrawnAndNotMeasured() {
        let bar = bare("test.tabsWidth.ids")
        establish(bar, tabs(), selected: "first")
        let renamed = tabs(ids: ["one", "two"])
        let got = taken(bar) { declare(bar, renamed, selected: "first") }
        XCTAssertEqual(got.measured, 0, "new ids under the same words were measured (\(got.measured))")
        XCTAssertEqual(got.redrawn, 1, "new ids under the same words were not redrawn once (\(got.redrawn))")
        XCTAssertGreaterThan(got.reads, 0, "the zone was never shown the new ids")
        assertNothing(taken(bar) { declare(bar, renamed, selected: "first") }, "the same new ids")
    }

    /// An action appearing beside the same tabs changes nothing the tabs zone draws.
    func testAnActionAppearingBesideTheSameTabsMeasuresAndDrawsNothing() {
        let bar = bare("test.tabsWidth.action")
        establish(bar, tabs())
        let refresh = HelmToolbarAction(id: "refresh", title: "Refresh", symbol: "arrow.clockwise") {}
        assertNothing(taken(bar) { declare(bar, tabs(), actions: [refresh]) }, "an action appearing")
        XCTAssertFalse(bar.fixture.bar.view.reachableZones.filter { $0 == .actions }.isEmpty,
                       "precondition: the action reached the bar's actions zone")
    }
}
