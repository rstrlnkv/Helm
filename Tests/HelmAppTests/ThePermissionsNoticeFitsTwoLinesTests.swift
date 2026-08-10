import XCTest
import SwiftUI
import AppKit
import HelmUI
@testable import HelmApp

/// The panel's permissions notice sits beside a button in a 320 pt window, and
/// what fits there is a fact about eight languages rather than about English.
///
/// It shipped as «2 permissions not granted · 7 modules affected», which is two
/// lines in English and **three** in Russian, French and Portuguese — a
/// paragraph wrapped around a button that is on one line, at the top of the
/// panel, which is the first thing anybody sees when something is wrong.
///
/// Measured on the real row rather than on a string length: the height depends
/// on the button beside it, and «Показать все» is the widest of the eight at
/// 96 pt, so Russian has the least room and needed a shorter sentence than the
/// others even after the trailing participle went.
@MainActor
final class ThePermissionsNoticeFitsTwoLinesTests: XCTestCase {

    /// The widget's own arrangement, at the width the panel gives it.
    private struct Row: View {
        let notice: String
        let button: String
        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(HelmSignal.warning)
                Text(notice)
                    .font(HelmText.rowDetail)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button(button) {}.controlSize(.small)
            }
            .padding(12)
            .frame(width: helmPanelWidth - 24)
        }
    }

    private func height(_ notice: String, _ button: String) -> CGFloat {
        NSHostingView(rootView: AnyView(Row(notice: notice, button: button))).fittingSize.height
    }

    /// One line of `rowDetail` in this row, measured rather than assumed: the
    /// row is 44 pt with a single short word in it, and every further line adds
    /// about 14. Two lines is 52; three is 66.
    private let twoLines: CGFloat = 58

    func testEveryLanguageFitsTwoLines() {
        // Two and seven: the numbers on the Mac this was reported from, and the
        // plural form that is longest in most of the eight.
        var tall: [String] = []
        for language in AppLanguage.allCases {
            let notice = AppStr.permissionsWithheld(count: 2, modules: 7, language: language)
            let button = AppStr.showPermissions(language: language)
            let h = height(notice, button)
            if h > twoLines { tall.append("\(language.rawValue): \(Int(h)) pt — \(notice)") }
        }
        XCTAssertTrue(tall.isEmpty,
                      "the notice wraps past two lines beside its button, which is a "
                      + "paragraph at the top of a 320 pt panel:\n" + tall.joined(separator: "\n"))
    }

    /// The control, and it is the pair that was reported: the sentence as it
    /// shipped, beside the button as it shipped. Both have since been
    /// shortened — separately, and each shortening bought room for the other —
    /// so this is the only place either of them still exists.
    ///
    /// Without it the threshold is a number above every real case, and a check
    /// that cannot go red is not evidence of anything.
    func testTheThresholdCatchesTheRowThatWasReported() {
        let h = height("Не выдано 2 разрешения · затронуто 7 модулей", "Показать все")
        XCTAssertGreaterThan(h, twoLines,
                             "the row this test was written about measures \(Int(h)) pt, "
                             + "so the threshold is not measuring anything")
    }

    /// And the button is the short one. The sentence fits because of it: the
    /// same Russian beside «Показать все» is three lines, so a later change
    /// that lengthens the button silently un-fixes the notice.
    func testTheButtonIsWhatMakesTheSentenceFit() {
        let notice = AppStr.permissionsWithheld(count: 2, modules: 7, language: .ru)
        XCTAssertLessThanOrEqual(height(notice, AppStr.showPermissions(language: .ru)), twoLines)
        XCTAssertGreaterThan(height(notice, "Показать все"), twoLines,
                             "the notice no longer depends on the button's width, which "
                             + "means this pair has stopped being measured together")
    }
}
