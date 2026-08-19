import HelmTestSupport
import XCTest

/// **The strip a page opens with is not fenced off from the page.**
///
/// Measured on this Mac, macOS 27, at the settings window's 846 pt detail pane:
/// the background above the rule and below it is the same to the byte — luma
/// 255.0 in light, 30.0 in dark, on a grouped-`Form` page and on a bleeding one
/// alike. So the rule was never covering a change of surface; it was asserting a
/// boundary nothing else on the page expressed, and it was the **only**
/// full-bleed element on the pages that had it — 0…845 across a pane whose card
/// column runs 71…774.
///
/// The two apps it sits beside were measured the same day and neither draws one:
/// System Settings' detail pane reads luma 30.0 with a largest row-to-row step
/// of 1.6 across its top 300 pt, Finder's 30.0 with a step of 1.7 — dither, not
/// a hairline, where a `Divider()` measures 22.
///
/// The rule is deleted rather than made optional. A `showsRule:` parameter would
/// be the same four decisions with a nicer spelling, and every call site choosing
/// for itself is what «one of each, no local variants» exists to stop. `bleeds:`
/// is not a precedent for it — that is forwarded from `descriptor.pageBleeds`, a
/// fact a module declares about itself, and no module declares that its page
/// wants a line.
final class ThePageHeaderCarriesNoRuleTests: XCTestCase {

    /// The one place a rule under this header still does work, and why it is
    /// named here rather than left to somebody's judgement.
    ///
    /// `WhatsNewView` is a **sheet**, not a settings page: bare scrolling text,
    /// no grouped `Form` and no card. On every page the card's own fill (Δ8 in
    /// light, Δ7 in dark) gives a scrolled edge its shape, so the clip reads as
    /// an ordinary scroll edge once the line is gone. In the sheet there is no
    /// card and the contrast across the edge is 0, so text would pass under the
    /// title with no cue at all.
    private let sheetThatKeepsItsRule = "Sources/HelmApp/AboutPage.swift"

    func testNoPageDrawsARuleUnderItsHeader() throws {
        var offences: [String] = []
        for path in try RepoSource.swiftFiles(under: "Sources")
        where path != sheetThatKeepsItsRule {
            let lines = try RepoSource.lines(of: path)
            guard let header = lines.firstIndex(where: {
                RepoSource.code($0).contains("HelmPageHeader(")
            }) else { continue }
            guard let sibling = Self.lineAfterTheCall(startingAt: header, in: lines) else { continue }
            if RepoSource.code(lines[sibling]).contains("Divider()") {
                offences.append("\(path):\(sibling + 1)")
            }
        }
        XCTAssertEqual(offences, [], """
            a page draws a hairline between its header and its content. Measured on this Mac, \
            the background is identical either side of it, and neither System Settings nor \
            Finder draws one — so the line marks a boundary the page does not otherwise have
            """)
    }

    /// The first code line **after** the call that starts on `start` — its
    /// sibling in whatever stack it sits in.
    ///
    /// Counted rather than guessed at. One call site here spans four lines and
    /// another spans forty, because the module page's header takes a trailing
    /// closure holding a badge, a switch and a comment about `ViewBuilder`; a
    /// scan that looked a fixed number of lines ahead found two of the three
    /// rules and reported the tree clean of the third. Parens close the
    /// argument list, braces close the trailing closure if there is one, and
    /// the next line carrying code is the sibling.
    ///
    /// Nil when the call never closes, which is a file this test cannot read
    /// rather than a file that passes.
    private static func lineAfterTheCall(startingAt start: Int, in lines: [String]) -> Int? {
        var parens = 0
        var braces = 0
        var opened = false
        for index in start..<lines.count {
            for character in RepoSource.code(lines[index]) {
                switch character {
                case "(": parens += 1; opened = true
                case ")": parens -= 1
                case "{": braces += 1
                case "}": braces -= 1
                default: break
                }
            }
            guard opened, parens == 0, braces == 0 else { continue }
            // The call is closed on this line; the sibling is the next line
            // with anything on it.
            return lines[(index + 1)...].firstIndex {
                !RepoSource.code($0).trimmingCharacters(in: .whitespaces).isEmpty
            }
        }
        return nil
    }

    /// And the scan can fail: it hunts for two spellings, and either being
    /// renamed would leave it passing over a tree full of rules.
    func testTheScanIsLookingForThingsThatStillExist() throws {
        let files = try RepoSource.swiftFiles(under: "Sources")
        let headers = try files.filter { try RepoSource.text(of: $0).contains("HelmPageHeader(") }
        XCTAssertFalse(headers.isEmpty, "no page draws a header any more; the scan is idle")
        let sheet = try RepoSource.text(of: sheetThatKeepsItsRule)
        XCTAssertTrue(sheet.contains("HelmPageHeader(") && sheet.contains("Divider()"), """
            the one allowed site no longer looks the way this test excuses it for — check \
            whether the exception is still earned rather than leaving it standing
            """)
    }
}
