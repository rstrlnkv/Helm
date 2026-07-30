import AppKit
import XCTest
import HelmUI
@testable import Module_Disk_UI

/// The header's scan statement has a width budget, and it is not written down
/// anywhere except in the threshold that decides whether the statement is shown
/// at all.
///
/// `DiskLayout.showsScanStatement` turns on at 788 pt of pane, a figure measured
/// from real font metrics for the bar *with* a statement in it. That measurement
/// was taken against the two statements that existed — "N files in M s" and
/// "Measured N ago" — so it is only true while a new statement is no wider than
/// those. The crumbs beside it are `fixedSize()` and the spacer has a minimum, so
/// a wider statement does not widen the bar: it truncates, `lineLimit(1)`.
///
/// That is how the stopped statement started. "Остановлено — файлов: 263144"
/// measured 161 pt against the existing widest of 122 — so between 788 pt and
/// roughly 830 pt of pane, the one line on the screen that says the sizes beside
/// it are not totals would have arrived as "Остановлено — файло…". The count went
/// to the hint instead, where nothing is measured in points.
///
/// This is a real-metrics test, like `DiskLayoutTests`: it renders the strings
/// with the font the header uses rather than counting characters.
final class StoppedStatementWidthTests: XCTestCase {

    /// `.font(.caption)` on macOS. The absolute number matters less than that
    /// every string in the comparison is measured with the same one.
    private static let captionSize: CGFloat = 10

    private func width(_ string: String) -> CGFloat {
        (string as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: Self.captionSize),
        ]).width
    }

    /// The two statements the 788 pt threshold was measured against, in the eight
    /// languages, with a file count wide enough to be realistic — a home
    /// directory walk reaches a quarter of a million.
    private var budget: CGFloat {
        let existing = [
            "263144 files in 45 s", "Файлов: 263144 за 45 с", "263144 archivos en 45 s",
            "263144 fichiers en 45 s", "263144 Dateien in 45 s", "263144 ファイル / 45 秒",
            "263144 个文件，45 秒", "263144 arquivos em 45 s",
            "Measured 2 hours ago", "Измерено 2 часа назад", "Medido hace 2 horas",
            "Mesuré il y a 2 heures", "Gemessen vor 2 Stunden", "計測 2 時間前",
            "测量于 2 小时前", "Medido 2 horas atrás",
        ]
        return existing.map(width).max() ?? 0
    }

    /// Every language's stopped statement, taken from the shipped tables rather
    /// than retyped here — a test against its own copy of the strings is a test
    /// that stays green while the strings drift.
    private func stoppedInEveryLanguage() -> [(AppLanguage, String)] {
        AppLanguage.allCases.map { ($0, L("Stopped", language: $0)) }
    }

    func testTheStoppedStatementFitsTheSlotTheThresholdWasMeasuredFor() {
        let budget = self.budget
        XCTAssertGreaterThan(budget, 100, "the budget itself stopped being measured")

        let tooWide = stoppedInEveryLanguage()
            .filter { width($0.1) > budget }
            .map { "\($0.0.rawValue) \"\($0.1)\" \(Int(width($0.1))) pt" }

        XCTAssertEqual(tooWide, [], """
            Wider than the widest statement the 788 pt `showsScanStatement` \
            threshold was measured against (\(Int(budget)) pt), so on a pane just \
            over that threshold this line arrives truncated — and it is the only \
            place the screen says the sizes beside it are floors rather than \
            totals. Shorten it, or re-measure the threshold and move it.
            """)
    }

    /// No language may translate it to nothing: an empty statement is a screen
    /// that says a stopped tree is a measurement.
    func testEveryLanguageHasSomethingToSay() {
        for (language, text) in stoppedInEveryLanguage() {
            XCTAssertFalse(text.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(language.rawValue) has no stopped statement")
        }
    }

    /// The hint carries what the statement gave up, so it has to actually carry
    /// it: the count is the reason the trade was worth making.
    func testTheHintNamesTheCountTheStatementNoLongerShows() {
        XCTAssertTrue(DkStr.stoppedHint(263_144).contains("263144"),
                      DkStr.stoppedHint(263_144))
    }
}
