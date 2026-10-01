import AppKit
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
@testable import HelmApp

/// The Log page's cards ran off their own inset in no language — and this holds
/// it, because the page it replaced did in Russian.
///
/// **Measured 2026-08-14 on the page this one replaced**, offscreen, `.aqua`:
/// the filter row's furthest drawn layer reached x = 632.5 at a 645 pt pane in
/// `ru`, against 625.0 — the pane minus the 20 pt form inset — for every other
/// language. That row is gone (its controls are the window's toolbar now); what
/// is left to overflow is the card: a header with a time, a version and two
/// badges that a longer language spells wide, and rows with a wrapped message
/// and a source line.
///
/// 645 is a real width: `contentMinSize` is 860 and the sidebar's default is 214.
///
/// **What is measured is the drawn layers, not the offered widths.** A control
/// asked how wide it would like to be answers with what it wants; this asks the
/// window what it drew.
@MainActor
final class TheLogPageStaysInsideItsGutterTests: XCTestCase {

    /// The pane at `contentMinSize` with the default sidebar — the narrowest the
    /// window can be made without also dragging the divider.
    private let narrowest: CGFloat = 645
    /// And with the divider dragged to its stop: `contentMinSize` 860 less the
    /// sidebar at `sidebarMaximum` (320) and the split view's own rule.
    private let narrowestWithWidestSidebar: CGFloat = 539

    override func tearDown() {
        AppLanguage.override = nil
        super.tearDown()
    }

    /// Two launches with everything a card can carry: a fold, a run of the same
    /// warning with a count, an error with a long message and a source line, a
    /// line this app did not write, and enough badges for the header to be
    /// crowded in the languages that spell «warnings» longest.
    private func fixture() -> [LogEntry] {
        let base = Date(timeIntervalSince1970: 1_790_000_000)
        func at(_ seconds: Double) -> Date { base.addingTimeInterval(seconds) }
        let site = LogSite(file: "LayoutEngine.swift", line: 214, function: "startTap()")
        var lines = [LogEntry(date: at(0), level: .info, category: "app",
                              message: "Helm 0.11.1-dev.14 started")]
        for index in 1...8 {
            lines.append(LogEntry(date: at(Double(index) * 0.01), level: .info, category: "host",
                                  message: "enable module \(index)"))
        }
        for index in 0..<12 {
            lines.append(LogEntry(date: at(60 + Double(index)), level: .warn, category: "layout",
                                  message: "no accessibility grant — not watching", site: site))
        }
        lines.append(LogEntry(date: at(90), level: .error, category: "uninstaller.scanLeftovers",
                              message: String(repeating: "trash refused the folder ", count: 14),
                              site: LogSite(file: "HelmTrash.swift", line: 140,
                                            function: "remove(allowed:outOfScope:sharedWith:module:leaf:)")))
        lines.append(LogEntry(date: at(91), level: .info, category: "",
                              message: "Helm-OLD-FORMAT half-written line without a stamp or a level"))
        lines.append(LogEntry(date: at(9_000), level: .info, category: "app",
                              message: "Helm 0.11.1-dev.15 started"))
        lines.append(LogEntry(date: at(9_001), level: .warn, category: "vpn", message: "never connected"))
        return lines
    }

    /// The furthest right anything is drawn, ignoring the full-width containers —
    /// the hosting view's own layer and the dividers reach the pane's edge by
    /// construction and say nothing about content. The cards' own fill ends at
    /// the gutter, which is the bound.
    private func furthestDrawn(_ shell: ModulePageRender.Shell, width: CGFloat) -> CGFloat {
        shell.layers
            .filter { $0.frame.width < width - 1 }
            .map(\.frame.maxX)
            .max() ?? 0
    }

    private func offenders(_ shell: ModulePageRender.Shell, width: CGFloat) -> String {
        shell.layers
            .filter { $0.frame.width < width - 1 && $0.frame.maxX > width - HelmLayout.formInset }
            .sorted { $0.frame.maxX > $1.frame.maxX }
            .prefix(4)
            .map { "\($0.owner) \(Int($0.frame.width))×\(Int($0.frame.height)) "
                + "at x \(($0.frame.minX)) → \($0.frame.maxX), y \($0.frame.minY)" }
            .joined(separator: "\n  ")
    }

    func testTheCardsFitTheNarrowPanesInEveryLanguage() {
        let lines = fixture()
        for width in [narrowest, narrowestWithWidestSidebar] {
            for language in AppLanguage.allCases {
                AppLanguage.override = language
                let drawn = ModulePageRender.drawn(LogView(source: { lines }, storedLog: { false }),
                                                   in: .aqua, width: width)

                XCTAssertGreaterThanOrEqual(drawn.layers.count, 30, """
                    the log page drew \(drawn.layers.count) layers in \(language.rawValue) at \
                    \(width) pt — either it has lost its content or nothing rendered at all, and in \
                    the second case the measurement below is zero for free
                    """)
                XCTAssertLessThanOrEqual(furthestDrawn(drawn, width: width),
                                         width - HelmLayout.formInset + 0.5, """
                    the log page draws to x = \(furthestDrawn(drawn, width: width)) in \
                    \(language.rawValue) at \(width) pt, past its own \(HelmLayout.formInset) pt \
                    inset at \(width - HelmLayout.formInset).
                      \(offenders(drawn, width: width))
                    """)
            }
        }
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
