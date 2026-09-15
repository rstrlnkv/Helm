import XCTest
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **A `brew doctor` finding's severity is a word, and the word is in the
/// inspector — the row is the title alone.**
///
/// The row used to carry the badge too, and at the master column's pinned 310 pt
/// that was not free: measured 2026-09-16 at a 984 pt pane, each badge drew
/// 62 pt at the row's leading edge and took `HelmSpace.s3` after it, so the title
/// began 68 pt in and this Mac's own two findings read «Caution Calling
/// `postflight` is depre…» and «Caution Some installed formulae are…» — cut
/// mid-word to make room for a word that was the same on both rows. The badge is
/// gone from the row; `issueDetail` draws it beside the full title, which is on
/// the same screen above `HomebrewSplit`'s threshold and one selection away
/// below it.
///
/// **What this file is really guarding is the reading, not the layout.** A
/// severity that survives only as a tint is a fact that reaches nobody who
/// cannot see the tint, and a badge is a tinted pill — so the difference between
/// `.danger` and `.caution` has to be carried by `severityWord`, which is text,
/// in every language, and that word has to be drawn somewhere. Three cases, in
/// that order: the words differ, the inspector says one of them, and the row
/// spends no width saying it twice.
///
/// **Why a source scan for the last two.** `NSHostingView` builds no
/// accessibility tree until a client connects and a rendered SwiftUI button
/// carries no readable title — both measured in this suite already
/// (`TheRowsUpdateMarkerIsMoreThanAColourTests`,
/// `TheNarrowPaneCanStillActOnAPackageTests`) — so nothing mounted here can say
/// which words drew. The construction is what can be read, and each case asserts
/// its subject exists before asserting anything about its shape: a builder that
/// stopped drawing findings at all would otherwise satisfy a rule about how it
/// draws them. Comments are blanked first, because the two builders discuss the
/// badge in prose at length and a raw scan would read the explanation as the
/// code.
final class TheSeverityOfAFindingIsAWordTests: XCTestCase {

    private static let page = "Sources/Modules/Homebrew/UI/HomebrewSettingsPage.swift"

    /// One builder's body with its comments blanked, or a failure naming the
    /// builder rather than a silent empty string.
    private func body(of name: String,
                      file: StaticString = #filePath, line: UInt = #line) -> String {
        guard let text = try? RepoSource.text(of: Self.page) else {
            XCTFail("\(Self.page) could not be read", file: file, line: line)
            return ""
        }
        let bodies = SwiftSource.bodiesNamed(name, in: SwiftSource.code(text))
        guard bodies.count == 1 else {
            XCTFail("""
                \(Self.page) declares \(bodies.count) builders named \(name) where this reads \
                exactly one — the page's shape has moved and this rule is being applied to \
                whichever body the scan happened to find
                """, file: file, line: line)
            return ""
        }
        return bodies[0]
    }

    // MARK: - The words

    /// **The two severities are two different words, in all eight languages.**
    ///
    /// This is the whole of what a reader who cannot see the tint has to go on,
    /// and it is the case that fails if `severityWord` ever collapses — a
    /// `switch` that answered one string for both would leave a page where the
    /// two badges differ by hue and by nothing else.
    func testTheTwoSeveritiesAreDifferentWordsInEveryLanguage() {
        AppLanguage.each { language in
            let caution = HomebrewSettingsPage.severityWord(.caution)
            let danger = HomebrewSettingsPage.severityWord(.danger)
            XCTAssertFalse(caution.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(language.rawValue): a caution has no word")
            XCTAssertFalse(danger.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(language.rawValue): a danger has no word")
            XCTAssertNotEqual(caution, danger, """
                \(language.rawValue): both severities read «\(caution)», so the only thing \
                separating a problem from a caution on this page is the tint — which is exactly \
                the reader this word exists for
                """)
        }
    }

    // MARK: - Where the word is drawn

    /// **The inspector draws it, beside the title it belongs to.**
    func testTheInspectorDrawsTheSeverityWordBesideTheTitle() {
        let detail = body(of: "issueDetail")
        guard !detail.isEmpty else { return }

        // The subject, before anything about its shape: a builder that stopped
        // drawing the finding cannot be said to draw its severity well.
        XCTAssertTrue(detail.contains("issue.title"), """
            issueDetail in \(Self.page) no longer draws the finding's title, so this rule is \
            about a screen that is not there
            """)
        XCTAssertTrue(detail.contains("severityWord(issue.severity)"), """
            issueDetail in \(Self.page) does not name severityWord — the row deliberately spends \
            no width on the severity, so this builder is the only place the word is said. \
            Without it the difference between a problem and a caution is a colour and nothing else
            """)
        XCTAssertTrue(detail.contains("HelmBadge("), """
            issueDetail in \(Self.page) draws no badge, so the word has nothing to be drawn in
            """)
    }

    /// **And the row does not say it a second time.**
    ///
    /// The row is a handle: 62 pt of a 254 pt row spent repeating a word the
    /// screen beside it carries at full size is 62 pt taken off a title that was
    /// already being cut mid-word.
    func testTheRowSpendsNoWidthOnTheSeverity() {
        let row = body(of: "issueRow")
        guard !row.isEmpty else { return }

        XCTAssertTrue(row.contains("issue.title"), """
            issueRow in \(Self.page) no longer draws the finding's title — a rule about what the \
            row does *not* draw passes over a row that draws nothing at all
            """)
        XCTAssertFalse(row.contains("HelmBadge("), """
            issueRow in \(Self.page) draws a badge again. At the master column's pinned 310 pt \
            that is roughly 62 pt plus a step off the title, measured, and the title is what \
            tells one finding from another — the severity is said in issueDetail, at full size
            """)
        XCTAssertFalse(row.contains("severityWord"), """
            issueRow in \(Self.page) names severityWord — whatever it draws it in, that is width \
            spent repeating what the inspector beside it already says
            """)
    }
}
