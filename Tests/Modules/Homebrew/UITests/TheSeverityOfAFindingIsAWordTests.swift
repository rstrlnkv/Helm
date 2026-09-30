import XCTest
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **A `brew doctor` finding's severity is a word where it says something, and
/// that word is on the finding's own row.**
///
/// The findings used to be rows of a striped list, and the badge was taken off
/// them: at the master column's pinned 310 pt each badge drew 62 pt at the row's
/// leading edge, so this Mac's own two findings read «Caution Calling
/// `postflight` is depre…» and «Caution Some installed formulae are…» — cut
/// mid-word to make room for a word that was the same on both rows. The tab is a
/// page of rows now (`HomebrewHealthPage`), each with the width of the page, and
/// the badge is back on the row — **for `.danger` only**. `Error:` is what
/// brew prints for a problem and is the one severity that should stand out; a
/// `.caution` is what nearly every finding is, and a pill saying so on each row
/// says the same word on all of them. So a caution has **no word**
/// (`severityWord` answers nil), and the word that was for it is gone from the
/// app and from the eight tables: a string nothing draws is a translation
/// nobody reads.
///
/// **What this file is really guarding is the reading, not the layout.** A
/// severity that survives only as a tint is a fact that reaches nobody who
/// cannot see the tint, and a badge is a tinted pill — so the severity that
/// stands out has to carry a word, which is text, in every language, and the
/// badge that draws it has to be on the row, drawn from that word and no other
/// condition. Two cases: the words are as said, and the row draws what
/// `severityWord` gives.
///
/// **Why a source scan for the second.** `NSHostingView` builds no accessibility
/// tree until a client connects and a rendered SwiftUI button carries no readable
/// title — both measured in this suite already
/// (`TheRowsUpdateMarkerIsMoreThanAColourTests`,
/// `TheNarrowPaneCanStillActOnAPackageTests`) — so nothing mounted here can say
/// which words drew. The construction is what can be read, and the case asserts
/// its subject exists before asserting anything about its shape: a row that
/// stopped drawing findings at all would otherwise satisfy a rule about how it
/// draws them. Comments are blanked first, because the row discusses the badge
/// in prose and a raw scan would read the explanation as the code.
@MainActor
final class TheSeverityOfAFindingIsAWordTests: XCTestCase {

    private static let page = "Sources/Modules/Homebrew/UI/HomebrewHealthPage.swift"

    /// One type's body with its comments blanked, or a failure naming the type
    /// rather than a silent empty string.
    private func body(ofType name: String,
                      file: StaticString = #filePath, line: UInt = #line) -> String {
        guard let text = try? RepoSource.text(of: Self.page) else {
            XCTFail("\(Self.page) could not be read", file: file, line: line)
            return ""
        }
        let code = SwiftSource.code(text)
        let characters = Array(code)
        let bodies = SwiftSource.typeBodies(in: code).filter { $0.name == name }
        guard bodies.count == 1, let found = bodies.first else {
            XCTFail("""
                \(Self.page) declares \(bodies.count) types named \(name) where this reads \
                exactly one — the page's shape has moved and this rule is being applied to \
                whichever body the scan happened to find
                """, file: file, line: line)
            return ""
        }
        return String(characters[(found.open + 1)..<found.close])
    }

    // MARK: - The words

    /// **A problem has a word in every language, and a caution has none.**
    ///
    /// The word is what a reader who cannot see the tint has to go on, and it
    /// is the case that fails if `severityWord` ever answers empty for the
    /// danger, or answers something for the ordinary finding — a row in every
    /// language then carries a pill that says the same on all of them. The tint
    /// is asked in the same breath: a word with no tint, or a tint with no word,
    /// is a badge half drawn.
    func testAProblemHasAWordInEveryLanguageAndACautionHasNone() {
        AppLanguage.each { language in
            let danger = HomebrewSettingsPage.severityWord(.danger)
            XCTAssertNotNil(danger, "\(language.rawValue): a danger has no word")
            XCTAssertFalse((danger ?? "").trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(language.rawValue): a danger has an empty word")
            XCTAssertNotNil(HomebrewSettingsPage.severityTint(.danger),
                            "\(language.rawValue): a danger has a word and no tint")
            XCTAssertNil(HomebrewSettingsPage.severityWord(.caution), """
                \(language.rawValue): a caution has a word, so the badge on it says the same \
                on every row that has one
                """)
            XCTAssertNil(HomebrewSettingsPage.severityTint(.caution),
                         "\(language.rawValue): a caution has a tint and no word")
        }
    }

    // MARK: - Where the word is drawn

    /// **The row draws what `severityWord` gives, beside the title it belongs
    /// to, and nothing else decides whether a badge is there.**
    func testTheRowDrawsTheSeverityWordBesideTheTitle() {
        let row = body(ofType: "FindingRow")
        guard !row.isEmpty else { return }

        // The subject, before anything about its shape: a row that stopped
        // drawing the finding cannot be said to draw its severity well.
        XCTAssertTrue(row.contains("issue.title"), """
            FindingRow in \(Self.page) no longer draws the finding's title, so this rule is \
            about a row that is not there
            """)
        XCTAssertTrue(row.contains("severityWord(issue.severity)"), """
            FindingRow in \(Self.page) does not name severityWord — this row is the only place \
            the word is said, so without it the difference between a problem and a caution is a \
            colour and nothing else
            """)
        XCTAssertTrue(row.contains("if let word = HomebrewSettingsPage.severityWord(issue.severity)"), """
            FindingRow in \(Self.page) does not draw the badge from the word it is given — a \
            second condition beside `severityWord` is a second account of which findings have \
            a badge
            """)
        XCTAssertTrue(row.contains("HelmBadge(word"), """
            FindingRow in \(Self.page) draws a badge that is not the word `severityWord` gave
            """)
        XCTAssertEqual(row.components(separatedBy: "HelmBadge(").count - 1, 1, """
            FindingRow in \(Self.page) draws more than one badge, so the gate above may not be \
            the one that decides the severity's
            """)
    }
}
