import AppKit
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
@testable import HelmApp

/// The Log page's filter row ran off its own inset in Russian at the app's
/// smallest window.
///
/// **Measured 2026-08-14**, offscreen, `.aqua`, three consecutive runs identical:
/// the furthest drawn layer reached **x = 632.5** at a 645 pt pane in `ru`,
/// against **625.0** — the pane minus the 20 pt form inset — for every other
/// language at that width and for `ru` at 680, 720, 770 and 810. The row holds
/// three controls of fixed width: a segmented picker pinned to
/// `HelmPickerWidth.segmented`, 403.5 pt in Russian, a `.fixedSize()` menu, and
/// the `.fixedSize()` Follow toggle — 605 pt of room for the three of them and a
/// `Spacer(minLength: 12)`.
///
/// 645 is a real width: `contentMinSize` is 860 and the sidebar's default is 214.
///
/// **What is measured is the drawn layers, not the offered widths.** A control
/// asked how wide it would like to be answers with what it wants; this asks the
/// window what it drew.
@MainActor
final class TheLogPageStaysInsideItsGutterTests: XCTestCase {

    /// The pane at `contentMinSize` with the default sidebar — the narrowest the
    /// window can be made.
    private let narrowest: CGFloat = 645
    /// The pane at the default 1060 pt window, where nothing has ever overflowed.
    private let widest: CGFloat = 810

    override func tearDown() {
        AppLanguage.override = nil
        super.tearDown()
    }

    /// The furthest right anything is drawn, ignoring the full-width containers —
    /// the hosting view's own layer, the dividers and the row backgrounds all
    /// reach the pane's edge by construction and say nothing about content.
    private func furthestDrawn(_ shell: ModulePageRender.Shell, width: CGFloat) -> CGFloat {
        shell.layers
            .filter { $0.frame.width < width - 1 }
            .map(\.frame.maxX)
            .max() ?? 0
    }

    /// The layers past the inset, furthest first, for a message somebody has to
    /// act on: a number says the row overflows and not which control did it.
    private func offenders(_ shell: ModulePageRender.Shell, width: CGFloat) -> String {
        shell.layers
            .filter { $0.frame.width < width - 1 && $0.frame.maxX > width - HelmLayout.formInset }
            .sorted { $0.frame.maxX > $1.frame.maxX }
            .prefix(4)
            .map { "\($0.owner) \(Int($0.frame.width))×\(Int($0.frame.height)) "
                + "at x \(($0.frame.minX)) → \($0.frame.maxX), y \($0.frame.minY)" }
            .joined(separator: "\n  ")
    }

    private func page(_ width: CGFloat) -> ModulePageRender.Shell {
        ModulePageRender.drawn(LogView(source: { [] }, storedLog: { false }),
                               in: .aqua, width: width)
    }

    func testTheFilterRowFitsTheNarrowestPaneInEveryLanguage() {
        let inset = HelmLayout.formInset
        for language in AppLanguage.allCases {
            AppLanguage.override = language
            let drawn = page(narrowest)

            XCTAssertGreaterThanOrEqual(drawn.layers.count, 20, """
                the log page drew \(drawn.layers.count) layers in \(language.rawValue) — either \
                it has lost its content or nothing rendered at all, and in the second case the \
                measurement below is zero for free
                """)
            XCTAssertLessThanOrEqual(furthestDrawn(drawn, width: narrowest), narrowest - inset, """
                the log page draws to x = \(furthestDrawn(drawn, width: narrowest)) in \
                \(language.rawValue) at the narrowest pane the window allows (\(narrowest) pt), \
                past its own \(inset) pt inset at \(narrowest - inset). A reader of that language \
                loses the right edge of the last control in the filter row.
                  \(offenders(drawn, width: narrowest))
                """)
        }
    }

    /// **The fold happened**, and this is the assertion that says the test above
    /// is measuring a fix rather than a page that stopped drawing. Russian at
    /// 645 pt is the one reading that overflowed, and it is the one row here that
    /// is two lines tall.
    func testTheRussianRowFoldsAtTheNarrowestPane() {
        AppLanguage.override = .ru

        XCTAssertGreaterThan(filterRowHeight(page(narrowest)), filterRowHeight(page(widest)) + 10,
                             "the Russian filter row is the same height at 645 pt as at 810 — it "
                             + "did not fold, so whatever keeps it inside the inset is something "
                             + "else")
    }

    /// One line of this row, measured 2026-08-14: **49.0 pt** — two
    /// `HelmSpace.s5` insets around a 33 pt control — at every width in all
    /// eight languages, against 79.0 for the Russian fold at 645.
    ///
    /// A number rather than the English row's height, which is what this was
    /// first written against: a row that wrapped at *every* width kept all eight
    /// readings equal to each other and passed, so the check could not fail for
    /// the thing it exists to catch. Measured with a mutation that folded
    /// unconditionally.
    private let oneLineRow: CGFloat = 49

    /// And it folds **only** where it must: a row wrapped at every width would
    /// pass the overflow test above and lose the layout for everybody.
    ///
    /// Two readings, because neither is enough on its own. The height says the
    /// row is one line — and a wrapping row is *also* one line whenever the
    /// three controls fit, which is every language at 810 pt, so a page that had
    /// given up the arrangement entirely measured 49.0 pt exactly like this one.
    /// What the arrangement is *for* is the right edge: Follow sits against the
    /// gutter with the gap in the middle, and a wrap packs it to the left.
    func testNoLanguageFoldsTheRowAtTheDefaultWindow() {
        for language in AppLanguage.allCases {
            AppLanguage.override = language
            let drawn = page(widest)
            let height = filterRowHeight(drawn)
            let rightmost = furthestDrawn(inFilterRowOf: drawn)

            XCTAssertEqual(height, oneLineRow, accuracy: 1,
                           "the filter row is \(height) pt tall in \(language.rawValue) at the "
                           + "default window against the \(oneLineRow) pt one line of it takes — "
                           + "it has folded where it has the room not to")
            XCTAssertEqual(rightmost, widest - HelmLayout.formInset, accuracy: 1,
                           "the filter row ends at x = \(rightmost) in \(language.rawValue) at the "
                           + "default window, not at the \(widest - HelmLayout.formInset) pt "
                           + "gutter — Follow has stopped being pushed to the right edge, so the "
                           + "row is being laid out as if it had no room")
        }
    }

    /// The furthest right anything is drawn *inside the filter band*. The page's
    /// own right edge says nothing here: the writing row above it also ends at
    /// the gutter, so a measurement over the whole page reads that instead.
    private func furthestDrawn(inFilterRowOf shell: ModulePageRender.Shell) -> CGFloat {
        let rules = fullWidthRules(of: shell)
        guard rules.count == 4 else { return 0 }
        return shell.layers
            .filter { $0.frame.width < shell.width - 1
                && $0.frame.minY >= rules[1] && $0.frame.maxY <= rules[2] }
            .map(\.frame.maxX)
            .max() ?? 0
    }

    /// The filter row is what lies between the second and third rules on the
    /// page: header, rule, the writing switch, rule, **the filters**, rule, the
    /// lines, rule, footer. Its height is the only signal of the fold that does
    /// not depend on recognising a SwiftUI-drawn control by its class.
    private func filterRowHeight(_ shell: ModulePageRender.Shell) -> CGFloat {
        let rules = fullWidthRules(of: shell)
        guard rules.count == 4 else {
            XCTFail("the log page draws \(rules.count) full-width rules, not the four this "
                    + "measurement is built on — it is measuring some other band of the page")
            return 0
        }
        return rules[2] - rules[1]
    }

    /// The `Divider()`s, top down — the only band boundary on this page that
    /// does not mean recognising a SwiftUI-drawn control by its class.
    private func fullWidthRules(of shell: ModulePageRender.Shell) -> [CGFloat] {
        shell.layers
            .filter { $0.frame.height <= 1.5 && $0.frame.width >= shell.width - 1 }
            .map(\.frame.minY)
            .sorted()
    }

    // MARK: - What the two buttons under the lines can do

    /// The gate that shipped was the tail, so a build with logging off greyed
    /// «Clear» over 391 KB of log.
    func testClearIsOfferedForALogOnDiskWithNothingOnThePage() {
        XCTAssertTrue(LogView.canClear(entries: [], storedLog: true),
                      "a log file on disk reads as nothing to clear")
        XCTAssertTrue(LogView.canClear(entries: [line()], storedLog: false),
                      "lines on the page read as nothing to clear")
        XCTAssertFalse(LogView.canClear(entries: [], storedLog: false))
    }

    /// «Copy log» writes the line the file carries — one format, spelled once.
    func testTheCopiedTextIsTheFilesOwnLine() {
        let entry = line()

        let copied = LogView.pasteboardText([entry])

        XCTAssertEqual(copied, LogLine.line(entry))
        XCTAssertTrue(copied.contains("[warn]"), "the level is missing from «Copy log»: \(copied)")
        XCTAssertTrue(copied.contains("LayoutEngine.swift:214"),
                      "the source site is missing from «Copy log»: \(copied)")
        XCTAssertTrue(copied.contains("-"), "the date is missing from «Copy log»: \(copied)")
    }

    /// One line per line, because the file is one line per event and a bug
    /// report is read by whoever triages it.
    func testTheCopiedTextIsOneLinePerEntry() {
        let copied = LogView.pasteboardText([line(), line()])

        XCTAssertEqual(copied.components(separatedBy: "\n").count, 2, copied)
    }

    // MARK: - What a row says to somebody who is not looking at it

    /// The level was a 6 % wash and a 3 pt rule, on a row combined into one
    /// accessibility element whose value never named it.
    func testEveryLanguageHasAWordForTheTwoLevelsThatMatter() {
        for language in AppLanguage.allCases {
            AppLanguage.override = language
            let warning = AppStr.logLevelWord(.warn)
            let error = AppStr.logLevelWord(.error)

            XCTAssertNil(AppStr.logLevelWord(.info),
                         "an ordinary line is read out with a level in \(language.rawValue)")
            XCTAssertFalse(warning?.isEmpty ?? true, "no word for a warning in \(language.rawValue)")
            XCTAssertFalse(error?.isEmpty ?? true, "no word for an error in \(language.rawValue)")
            XCTAssertNotEqual(warning, error,
                              "a warning and an error are read out the same in "
                              + "\(language.rawValue), which is the distinction being fixed")
        }
        // In English, where the key is the string: the row's word and the
        // filter's setting are two keys, because one English key means one thing
        // and «Warnings» names a setting. Japanese and Chinese translate both to
        // 警告 and are right to — that is two keys agreeing, not one key reused.
        AppLanguage.override = .en
        XCTAssertNotEqual(AppStr.logLevelWord(.warn), AppStr.logLevelWarnings)
        XCTAssertNotEqual(AppStr.logLevelWord(.error), AppStr.logLevelErrors)
    }

    /// And the row says it. The words above are a promise about a screen, and a
    /// promise with no test under it is how five of them went silent.
    func testTheRowIsGivenTheWord() throws {
        let source = try RepoSource.text(of: "Sources/HelmApp/LogView.swift")

        XCTAssertTrue(source.contains(".accessibilityValue(AppStr.logLevelWord("), """
            LogView draws a row with no `accessibilityValue` taken from `AppStr.logLevelWord` — \
            the words exist and nothing reads them out.
            """)
    }

    private func line() -> LogEntry {
        LogEntry(date: Date(timeIntervalSince1970: 1_700_000_000), level: .warn,
                 category: "layout", message: "no accessibility grant — not watching",
                 site: LogSite(file: "LayoutEngine.swift", line: 214, function: "startTap()"))
    }
}
