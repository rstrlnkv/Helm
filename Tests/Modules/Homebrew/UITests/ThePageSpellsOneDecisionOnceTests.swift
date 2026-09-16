import Foundation
import HelmTestSupport
import XCTest

/// **Two of this page's edges are vocabulary rather than geometry, so they are
/// read off the source — and this file says what that cannot see.**
///
/// Everything else in the design pass this belongs to is measured off the
/// mounted page (`ThePageTakesItsStepsFromTheHouseTests`,
/// `ThePageMovesRatherThanCutsTests`). These two are not, for reasons that are
/// worth stating rather than working around:
///
/// - a `Section`'s header is drawn by AppKit inside a table, and what a `Text`
///   was *set in* does not survive into anything a walk of the view tree can
///   read back — the face is gone by the time there are pixels, and a pixel
///   difference between 13 pt semibold and 11 pt semibold is a claim about
///   antialiasing rather than about type;
/// - a monospaced face spelled three ways draws the **same glyphs** all three
///   ways at the default text size. There is nothing to measure: the whole
///   defect is that a frozen `11` stops following the system text size, which is
///   a fact about a setting this process cannot change for macOS.
///
/// So: a source scan, which *can* fail — both halves were red before this landed
/// — and which is blind to whether the result looks right. What it is not is a
/// check on the appearance of anything.
///
/// The code is read with comments blanked (`SwiftSource.code`), because every
/// rule in this repository is explained by quoting the thing it forbids and the
/// comments at both sites do exactly that.
final class ThePageSpellsOneDecisionOnceTests: XCTestCase {

    private static let page = "Sources/Modules/Homebrew/UI/HomebrewSettingsPage.swift"

    private func code() throws -> String {
        try SwiftSource.code(String(contentsOf: RepoSource.root
            .appendingPathComponent(Self.page), encoding: .utf8))
    }

    /// **The premise: the scan is reading the page and not an empty string.**
    /// Every assertion below is satisfied by a file nobody could open.
    func testTheScanIsReadingThePage() throws {
        let code = try code()
        XCTAssertGreaterThan(code.count, 20_000, "\(Self.page) read as \(code.count) characters")
        XCTAssertTrue(code.contains("struct HomebrewSettingsPage"),
                      "the scan is not reading the page's own source")
    }

    /// **No `Section` here draws the system's own heading.**
    ///
    /// `Section("…")` is the one construction in this app that lets macOS draw a
    /// section heading — 13 pt semibold, sentence case, the same weight as the
    /// rows under it — which is the exact shape `HelmSectionTitle`'s doc comment
    /// names as what the redesign replaced. The Состояние segment had two of
    /// them, on a screen that also draws two headings in the app's own voice.
    ///
    /// The rule is about the **header**, not about `Section`: a section header is
    /// not selectable, which is the whole reason a heading inside a selectable
    /// list is a `Section` at all, and `Section(header: HelmSectionTitle(…))` is
    /// still a `Section`.
    func testNoSectionHereLetsMacOSDrawItsHeading() throws {
        let lines = try code().components(separatedBy: "\n")
        // `\bSection\(` and not a substring search: `.configSection(group)` is an
        // enumeration case on this page and contains the word, which the first
        // version of this rule reported as a bare-string header.
        let opens = try NSRegularExpression(pattern: #"\bSection\("#)
        let systemDrawn = lines.enumerated().filter { _, line in
            let range = NSRange(line.startIndex..., in: line)
            guard let match = opens.firstMatch(in: line, range: range),
                  let after = Range(match.range, in: line)?.upperBound else { return false }
            return !line[after...].hasPrefix("header:")
        }
        XCTAssertEqual(systemDrawn.map { "\($0.offset + 1): \($0.element.trimmingCharacters(in: .whitespaces))" },
                       [], """
            these sections hand their heading to macOS, which draws it at the weight of the \
            rows under it. Pass `header: HelmSectionTitle(…)` — the `Section` is not what is \
            wrong, the bare string is
            """)
        // And it still finds sections at all, or the emptiness above is about a
        // page with no groups in it.
        XCTAssertGreaterThanOrEqual(lines.filter { $0.contains("Section(header:") }.count, 2,
                                    "the page draws fewer than the two groups the health list "
                                    + "has, so this rule is guarding nothing")
    }

    /// **One monospaced face, spelled one way.**
    ///
    /// Three spellings were on this page: `.system(size: 11, design: .monospaced)`
    /// on the fix command and every console line, and
    /// `HelmText.rowDetail.monospaced()` on the configuration values. All three
    /// drew the identical face — `rowDetail` *is* `.subheadline` — so this is
    /// vocabulary: three spellings of one decision read as three decisions, and
    /// the frozen one additionally stops following the system text size, which
    /// the type-scale ratchet cannot see because 11 is *on* the scale.
    ///
    /// `.system(.subheadline, design: .monospaced)` is the spelling settled on:
    /// it is what `HelmExplainer` in the design system uses, what
    /// `PackageSecondTier` two files away states the rule at, and the shape every
    /// other deliberate monospaced face in the tree takes (`HostsTable`,
    /// `HostsSettingsPage`, `LayoutLists`, `LayoutTestField`).
    func testTheMonospacedFaceIsSpelledOneWay() throws {
        let code = try code()
        XCTAssertFalse(code.contains("design: .monospaced") && code.contains(".system(size:"), """
            a monospaced face is still frozen at a hand-typed size on this page. A text style \
            resolves to the same 11 at the default setting and follows the system text size \
            from there, which a literal cannot
            """)
        XCTAssertFalse(code.contains(".monospaced()"), """
            a second spelling of the monospaced face is on this page. `HelmText.rowDetail\
            .monospaced()` draws what `.system(.subheadline, design: .monospaced)` draws; two \
            spellings of one decision is the thing this rule is about
            """)
        let spelled = code.components(separatedBy: ".system(.subheadline, design: .monospaced)").count - 1
        XCTAssertEqual(spelled, 3, """
            the page spells the settled monospaced face \(spelled) times where it draws three \
            monospaced things — the fix command, a console line and a configuration value. \
            Either one of them has changed face, or this floor is stale
            """)
    }
}
