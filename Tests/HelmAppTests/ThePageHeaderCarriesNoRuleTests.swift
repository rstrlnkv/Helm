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
///
/// # A page header is spelled two ways now, and this reads both
///
/// The settings pages hand their content to `helmPageHeader`, which lays the
/// strip **over** the page and gives it the system's scroll edge; a page whose
/// top band does not scroll — the Log page, the What's New sheet — draws
/// `HelmPageHeader` directly and gets no edge. The scan was written when there
/// was one spelling, and on the day the second landed it silently stopped
/// reading two of the three pages it was written for: every one of them had
/// become a modifier, and «find `HelmPageHeader(`» found nothing there. So it
/// asks for both, and `testTheScanIsLookingForThingsThatStillExist` fails if
/// either spelling leaves the tree.
///
/// **What the sibling check can and cannot mean under each spelling.** A header
/// drawn as a view has a next line in the stack, and that line is where the
/// hairline used to be. A header applied as a modifier has no sibling at all —
/// the thing under it is the page's own scrolling content, and a rule at the
/// top of *that* scrolls away rather than fencing the strip off. The scan
/// therefore reads the sibling where there is one, and the list below records
/// which files that is, so «no offences» is never read as «every page was
/// looked at».
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
    ///
    /// **Re-read on 2026-08-20 and still earned, but for one commit less than
    /// it used to be.** The sheet is a header stacked above a `ScrollView`, and
    /// the reasoning above is about that shape, which this change did not touch.
    /// What did change is that there is now a mechanism which would serve the
    /// sheet better than a permanent hairline: `helmPageHeader` lays the strip
    /// over the scroll view and lights it — fill and rule together — exactly
    /// when text goes under, which is the cue this rule is standing in for and
    /// the only moment it is needed. Moving the sheet onto it is a change of
    /// its own with its own capture, not a side effect of this one; recorded
    /// here so the next person weighs the exception again rather than
    /// inheriting it.
    private let sheetThatKeepsItsRule = "Sources/HelmApp/AboutPage.swift"

    func testNoPageDrawsARuleUnderItsHeader() throws {
        var offences: [String] = []
        var read: [String] = []
        for path in try RepoSource.swiftFiles(under: "Sources")
        where path != sheetThatKeepsItsRule {
            let lines = try RepoSource.lines(of: path)
            guard let header = lines.firstIndex(where: {
                RepoSource.code($0).contains("HelmPageHeader(")
            }) else { continue }
            read.append(path)
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
        XCTAssertEqual(read.sorted(), Self.headersDrawnAsAView, """
            the files drawing a header as a view are \(read.sorted()), not \
            \(Self.headersDrawnAsAView). Recorded rather than counted, because this scan \
            reads a sibling and a page that has moved to `helmPageHeader` has none — it \
            leaves the scan silently, and «no offences» then means «nothing was looked at»
            """)
    }

    /// **Recorded, so the scan cannot lose a page without saying so.**
    ///
    /// `HelmPageHeader.swift` is `helmPageHeader`'s own construction of the
    /// header — the one place the two spellings meet — and `LogView` is the one
    /// page built as a stack of bands. The What's New sheet is excluded above
    /// and so is not in this list.
    private static let headersDrawnAsAView = [
        "Sources/HelmApp/LogView.swift",
        "Sources/HelmUI/DesignSystem/HelmPageHeader.swift",
    ]

    /// And the pages that draw it as a modifier are read for the same reason —
    /// by name, so one dropping the header entirely is a failure rather than a
    /// file that quietly stopped matching.
    func testTheSettingsPagesLayTheirHeaderOverTheirContent() throws {
        for path in ["Sources/HelmApp/GeneralSettingsPage.swift",
                     "Sources/HelmApp/SettingsWindow.swift"] {
            let source = try RepoSource.text(of: path)
            XCTAssertTrue(source.contains(".helmPageHeader("), """
                \(path) no longer lays its header over its content. Either the page lost its \
                header, or it went back to being a sibling in a stack — in which case nothing \
                passes behind the strip and its material is blurring the window
                """)
        }
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
        let modifiers = try files.filter { try RepoSource.text(of: $0).contains(".helmPageHeader(") }
        XCTAssertFalse(modifiers.isEmpty, """
            nothing in the tree lays a header over its content any more. Either the spelling \
            was renamed — in which case the scan above is reading for a word that no longer \
            exists — or every page went back to stacking one on top
            """)
        let sheet = try RepoSource.text(of: sheetThatKeepsItsRule)
        XCTAssertTrue(sheet.contains("HelmPageHeader(") && sheet.contains("Divider()"), """
            the one allowed site no longer looks the way this test excuses it for — check \
            whether the exception is still earned rather than leaving it standing
            """)
    }
}
