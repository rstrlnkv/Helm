import AppKit
import HelmRuntime
import HelmUI
import HelmTestSupport
import XCTest
@testable import Module_Duplicates_UI

/// `DuplicatesLayout`'s thresholds against the strings that are actually
/// shipped, in all eight languages.
///
/// The thresholds were once numbers a script had printed, and the script summed
/// **two** of the row's three controls and a count line somebody had typed out
/// in five languages. So `barWithCount` said 760 for a row that needs 1000, and
/// the page overflowed its pane at the size the window opens at — in seven of
/// the eight languages, from the day the third control was added.
///
/// This is the same measurement, living where it cannot go stale: real AppKit
/// control metrics, the `.lproj` tables read at test time, and a check that the
/// row still consists of the parts measured here. It is deliberately not a
/// render — a test that needs a window server is a test that is green on this
/// machine and absent on the next. It is calibrated against one: drawing the
/// real row offscreen and binary-searching the narrowest pane it draws whole in
/// gives 968.5 / 717.5 / 603.5 / 497.5 pt for the four rows, 2.7 to 4.5 pt under
/// what this model says, because ink stops inside the last button's bezel.
///
/// One limit, stated rather than discovered later: the suite runs in this
/// machine's language, and a Japanese or Chinese string measured from an English
/// process picks up fallback advances a point or two off what that process would
/// draw — ja renders 610.5 where this says 628. It changes nothing here, because
/// the languages that set every threshold are German and French, and no CJK row
/// comes within 130 pt of the width that lets it through.
final class DuplicatesBarWidthTests: XCTestCase {

    // MARK: - The row, in points

    /// The English of every string the row measures, so that what is measured
    /// here and what `DuplicatesSettingsPage` draws cannot drift apart in
    /// silence: `testTheRowIsMadeOfThePartsMeasuredHere` reads them back off
    /// `DupStr`, and the English is the key.
    private enum Key {
        static let chooseAnother = "Choose another folder"
        static let searchAgain = "Search again"
        static let markEveryExtra = "Mark every extra copy"
    }

    /// The parts of the row that are not words, mirrored from
    /// `DuplicatesSettingsPage.toolbar`: `HStack(spacing: 8)`,
    /// `.padding(.horizontal, 20)`, the path's `minWidth: 180` and
    /// `Spacer(minLength: 12)`.
    private enum Chrome {
        static let spacing: CGFloat = 8
        static let padding: CGFloat = 20
        static let pathFloor: CGFloat = 180
        static let spacer: CGFloat = 12

        /// The `folder` symbol at the callout size the row draws it in — 17 pt,
        /// and measured rather than guessed because the guess is what put the
        /// old figure 25 pt out.
        static let folderIcon: CGFloat = {
            let callout = NSFont.preferredFont(forTextStyle: .callout)
            let image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)!
            return image.withSymbolConfiguration(
                .init(pointSize: callout.pointSize, weight: .regular))!.size.width
        }()

        /// Both paddings, the icon, the path at its floor, the spacer at its
        /// minimum, and the five gaps between six children.
        static let total = padding * 2 + folderIcon + pathFloor + spacer + spacing * 5
    }

    /// A real control, sized the way AppKit sizes it. The script this replaces
    /// estimated a bordered button as `caption + 22`, which put the two-control
    /// bar at 538 where SwiftUI draws 563.5.
    private func labelledControl(_ title: String) -> CGFloat {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .push
        button.controlSize = .small
        button.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))
        button.sizeToFit()
        return button.fittingSize.width
    }

    private func symbolControl(_ name: String) -> CGFloat {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
        let button = NSButton(image: image, target: nil, action: nil)
        button.bezelStyle = .push
        button.controlSize = .small
        button.sizeToFit()
        return button.fittingSize.width
    }

    private func captionWidth(_ string: String) -> CGFloat {
        (string as NSString).size(withAttributes: [
            .font: NSFont.preferredFont(forTextStyle: .caption1),
        ]).width
    }

    /// The count line as a real library produces it, not as a demonstration
    /// does: the count is `fixedSize`, so bigger figures widen the row rather
    /// than truncating inside it.
    private func countLine(_ language: AppLanguage) -> String {
        DupStr.found(12_345, HelmBytes.string(118_900_000_000, language: language.rawValue),
                     language: language)
    }

    /// The four rows of the ladder, widest first.
    private enum Row: String, CaseIterable {
        case countAndThreeLabels = "path + three labelled controls + count"
        case threeLabels = "path + three labelled controls"
        case markAllAsSymbol = "…with mark-all as a symbol"
        case searchAsSymbolToo = "…with search as a symbol too"
    }

    /// Every row of the ladder in one language, each part measured once.
    private func demands(in language: AppLanguage) -> [Row: CGFloat] {
        let choose = labelledControl(L(Key.chooseAnother, language: language))
        let search = labelledControl(L(Key.searchAgain, language: language))
        let markAll = labelledControl(L(Key.markEveryExtra, language: language))
        let clock = symbolControl("arrow.clockwise")
        let checklist = symbolControl("checklist")
        let threeLabels = Chrome.total + choose + search + markAll
        return [
            .countAndThreeLabels: threeLabels
                + captionWidth(countLine(language)) + Chrome.spacing,
            .threeLabels: threeLabels,
            .markAllAsSymbol: Chrome.total + choose + search + checklist,
            .searchAsSymbolToo: Chrome.total + choose + clock + checklist,
        ]
    }

    /// The widest language for a row, and what it costs there.
    private func widest(_ row: Row) -> (AppLanguage, CGFloat) {
        AppLanguage.allCases
            .map { ($0, demands(in: $0)[row]!) }
            .max { $0.1 < $1.1 }!
    }

    // MARK: - The thresholds hold

    /// Each rung against the threshold that draws it, taken from
    /// `DuplicatesLayout` itself: a copy of the number here would keep this
    /// file green through any edit to the one that ships.
    private static let rungs: [(Row, CGFloat, String)] = [
        (.countAndThreeLabels, DuplicatesLayout.barWithCount, "barWithCount"),
        (.threeLabels, DuplicatesLayout.barWithMarkAllLabel, "barWithMarkAllLabel"),
        (.markAllAsSymbol, DuplicatesLayout.barWithSearchLabel, "barWithSearchLabel"),
    ]

    /// Every rung of the ladder, against the width that lets it through, with
    /// room to spare. This is the check the shipped thresholds would have
    /// failed: at 810 pt of pane — the default window — `showsCount` was true
    /// and the row it drew needed 1000.
    ///
    /// Fitting is not enough on its own. A threshold a few points over its row
    /// is a coincidence rather than a margin, and this is a model of a drawn
    /// row, agreeing with the render to about 4 pt — so a rung clearing by 3
    /// might not clear at all. Each of these clears by around 39.
    func testEveryRowFitsTheWidthThatLetsItThroughWithRoomToSpare() {
        for (row, threshold, name) in Self.rungs {
            let (language, needs) = widest(row)
            XCTAssertGreaterThan(threshold - needs, 20, """
                \(row.rawValue) needs \(Int(needs)) pt in \(language.rawValue), and \
                `\(name)` draws it from \(Int(threshold)). Either shorten the strings \
                or raise the threshold — a threshold below its own row switches that \
                row *into* an overflow.
                """)
        }
    }

    /// The bottom rung has no threshold under it, so the pane at the smallest
    /// window is what it answers to. Below this there would be nothing left to
    /// give up but a control, and the page gives up no controls.
    func testTheLastRowFitsTheSmallestWindowInEveryLanguage() {
        let smallestPane: CGFloat = 860 - 250
        let (language, needs) = widest(.searchAsSymbolToo)
        XCTAssertLessThan(needs, smallestPane, """
            With both trailing controls as symbols the row still needs \
            \(Int(needs)) pt in \(language.rawValue), and the narrowest pane is \
            \(Int(smallestPane)).
            """)
    }

    // MARK: - The measurement still describes the row

    /// The defect underneath the defect: a third control was added to the row
    /// and no measurement was told. Every string the toolbar draws is named
    /// here, so a fourth one fails this rather than shipping unmeasured.
    func testTheRowIsMadeOfThePartsMeasuredHere() throws {
        let page = try RepoSource.text(of:
            "Sources/Modules/Duplicates/UI/DuplicatesSettingsPage.swift")
        let opens = try XCTUnwrap(page.range(of: "private func toolbar("))
        // The next section, whichever it is. Naming `// MARK: - Content`
        // outright made this read every section between the two: the policy row
        // landed there and its two strings were counted as the toolbar's.
        let closes = try XCTUnwrap(page.range(of: "// MARK: -",
                                              range: opens.upperBound..<page.endIndex))
        let toolbar = String(page[opens.lowerBound..<closes.lowerBound])
        XCTAssertTrue(toolbar.contains("HStack(spacing: 8)"),
                      "the toolbar body was not found — this check reads nothing")

        var drawn = Set<String>()
        var rest = Substring(toolbar)
        while let hit = rest.range(of: "DupStr.") {
            let after = rest[hit.upperBound...]
            drawn.insert(String(after.prefix(while: { $0.isLetter })))
            rest = after
        }
        XCTAssertEqual(drawn, [
            // Measured here, each in its own rung.
            "chooseFolder", "chooseAnother", "search", "searchAgain",
            "basketAllExtras", "found",
            // The searching row, which draws none of the above.
            "stop",
        ], """
            The toolbar draws a string this measurement does not account for, or \
            has stopped drawing one it does. Add it to a rung and re-measure — the \
            row that shipped clipped because `Mark every extra copy` was added to \
            it and never entered any measurement.
            """)
    }

    /// And the strings measured here are the strings the page draws. The English
    /// is the key, so a reworded control would leave this file measuring a key
    /// that no longer exists and quietly reporting the English width for all
    /// eight languages.
    func testTheStringsMeasuredHereAreTheOnesThePageDraws() {
        let language = AppLanguage.current
        XCTAssertEqual(DupStr.chooseAnother, L(Key.chooseAnother, language: language))
        XCTAssertEqual(DupStr.searchAgain, L(Key.searchAgain, language: language))
        XCTAssertEqual(DupStr.basketAllExtras, L(Key.markEveryExtra, language: language))
    }

    /// The count line differs by language by more than the two controls beside
    /// it do, which is why it is the first thing the row gives up.
    func testTheCountLineIsWhatSetsTheWidestRow() {
        let (language, _) = widest(.countAndThreeLabels)
        XCTAssertEqual(language, .de, """
            German was the language the count threshold was measured in; the \
            widest is now \(language.rawValue), so re-measure.
            """)
    }
}
