import AppKit
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
@testable import Module_Uninstaller_UI

/// The Trash-offer window is a fixed width, and the comment beside the old 460
/// said outright it was sized to the widest *group header* — the footer was
/// never measured. The footer is two verbs and a count: «Diese Dateien
/// behalten» and «In den Papierkorb legen» both arrived truncated on the audit
/// render, in the window that deletes somebody's files.
///
/// Modeled the way `ThePolicyRowFitsThePaneTests` models its row: real AppKit
/// control metrics against the shipped strings, in all eight languages named
/// outright, against the constant the view actually draws.
final class TheTrashOfferFooterFitsTheWindowTests: XCTestCase {

    /// The English of the two verbs, so what is measured here and what the
    /// footer draws cannot drift apart in silence — the English is the key.
    private enum Key {
        static let keep = "Keep these files"
        static let trash = "Move to Trash"
    }

    /// Mirrored from `TrashedLeftoversView.footer`: `HStack(spacing: 8)` and
    /// `.padding(.horizontal, HelmLayout.formInset)`.
    private enum Chrome {
        static let spacing: CGFloat = 8
        static let padding = HelmLayout.formInset
        /// Both paddings and the two gaps between three children.
        static let total = padding * 2 + spacing * 2
    }

    private func button(_ title: String) -> CGFloat {
        ControlMetrics.button(title)
    }

    /// The summary at `HelmText.rowDetail`, which is `Font.system(size: 11)`.
    private func summary(_ string: String) -> CGFloat {
        ControlMetrics.label(string, font: NSFont.systemFont(ofSize: 11))
    }

    /// What the footer asks for in one language, with a summary a real removal
    /// produces. The summary is the part allowed to truncate, so it enters the
    /// demand at a width it actually reaches rather than at a demonstration's.
    private func demand(in language: AppLanguage) -> CGFloat {
        Chrome.total
            + button(L(Key.keep, language: language))
            + summary(UnStr.selectedSummary(12, "999,9 MB", language: language))
            + button(L(Key.trash, language: language))
    }

    func testTheFooterFitsTheWindowInEveryLanguage() {
        let (language, needs) = AppLanguage.allCases
            .map { ($0, demand(in: $0)) }
            .max { $0.1 < $1.1 }!
        XCTAssertLessThan(needs, TrashedLeftoversView.windowWidth - 10, """
            The footer needs \(Int(needs)) pt in \(language.rawValue) and the \
            window is \(Int(TrashedLeftoversView.windowWidth)). The old width \
            was measured against the widest group header, and the footer's two \
            verbs truncated — «Diese Dateien behal…» on the button that keeps \
            somebody's files. Raise `windowWidth` or shorten the verbs.
            """)
    }

    /// The strings measured here are the ones the footer draws.
    func testTheStringsMeasuredHereAreTheOnesTheFooterDraws() {
        XCTAssertEqual(UnStr.trashOfferKeep, L(Key.keep, language: AppLanguage.current))
        XCTAssertEqual(UnStr.moveToTrash, L(Key.trash, language: AppLanguage.current))
    }
}
