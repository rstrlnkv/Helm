import HelmRuntime
import HelmUI
import XCTest
import Module_Leftovers_Engine
@testable import Module_Leftovers_UI

/// One act, one name — and the punctuation an interpolated line takes with it.
///
/// **The wrong word was on the most dangerous control.** Files go to the Trash:
/// the bar's destructive button says so, the report says «Moved to the Trash»,
/// and the row's menu said «Delete…» while the dialog it opened was titled
/// «Delete X?». Three names for one act, and the one a person reads just before
/// pressing was the one that named the wrong act.
///
/// **Every assertion here is parameterized by language**, because the English
/// being right is exactly how this hid in the other seven: `L()` falls back to
/// its key, so a test that reads `AppLanguage.current` checks English eight
/// times (ARCHITECTURE.md § Localization).
///
/// And the inline tables are checked for French's spaces and Russian's dash,
/// because `PunctuationIsTerminologyTests` reads the eight `.strings` files —
/// which is where an interpolated line never goes.
@MainActor
final class OneActHasOneNameTests: XCTestCase {

    private var previous: AppLanguage?

    override func setUp() {
        super.setUp()
        previous = AppLanguage.override
    }

    override func tearDown() {
        AppLanguage.override = previous
        super.tearDown()
    }

    private func agent(_ name: String = "com.vendor.updater",
                       missingTarget: String? = nil) -> StaleItem {
        StaleItem(path: "\(NSHomeDirectory())/Library/LaunchAgents/\(name).plist",
                  identifier: name, kind: .launchAgent, sizeBytes: 4_096,
                  missingTarget: missingTarget)
    }

    // MARK: - One act, one name

    /// The row's menu item and the bar's button are the same act, so the row's
    /// label is the button's own word plus the ellipsis that promises a question
    /// — never a different verb.
    func testTheRowsLabelIsTheButtonsWordAndAnEllipsis() {
        for language in AppLanguage.allCases {
            AppLanguage.override = language
            XCTAssertTrue(LfStr.deleteItem.hasPrefix(LfStr.removeSelected), """
                \(language.rawValue): the row's menu says «\(LfStr.deleteItem)» where the button \
                that performs the same act says «\(LfStr.removeSelected)» — two names for moving \
                one file to the Trash.
                """)
            XCTAssertTrue(LfStr.deleteItem.hasSuffix("…"), """
                \(language.rawValue): «\(LfStr.deleteItem)» promises no further step, and one \
                follows — the row opens a dialog.
                """)
            XCTAssertNotEqual(LfStr.deleteItem, LfStr.removeSelected,
                              "\(language.rawValue): the label that asks first has lost its ellipsis")
        }
    }

    /// The question asked over a loaded item names the switch that actually stops
    /// it, and names it by asking the switch — not by spelling its word a second
    /// time (ARCHITECTURE.md § A sentence that names a control).
    ///
    /// Moving a launch agent's file to the Trash does not unload the job:
    /// `LeftoversEngine.trash` moves paths and nothing else, while
    /// `ActiveExtensions.setDisabled` sends `launchctl disable` **and**
    /// `bootout`. So «it is loaded now» was warning about the lesser fact.
    func testTheLoadedQuestionNamesTheSwitchThatStopsIt() {
        for language in AppLanguage.allCases {
            AppLanguage.override = language
            let question = LfStr.confirmDeleteInUse("com.vendor.updater")
            XCTAssertTrue(question.contains(LfStr.disable()), """
                \(language.rawValue): the question over a loaded item does not name \
                «\(LfStr.disable())», which is the only control on the row that stops it: \
                \(question)
                """)
        }
    }

    /// The report counts what moved as well as measuring it: the person ticked a
    /// number of rows, and `removedCount` is in hand when the line is built.
    func testTheReportSaysHowManyMovedAndNotOnlyHowMuch() {
        for language in AppLanguage.allCases {
            AppLanguage.override = language
            let three = LfStr.movedToTrash(3, "4 KB")
            XCTAssertTrue(three.contains("4 KB"),
                          "\(language.rawValue): the size left the line: \(three)")
            XCTAssertNotEqual(LfStr.movedToTrash(1, "4 KB"), three, """
                \(language.rawValue): the line says the same thing for one file and for three, \
                so it is not carrying the count: \(three)
                """)
        }
    }

    // MARK: - Punctuation the .strings guard cannot see

    /// Japanese joins with its own middle dot everywhere else in this module —
    /// `selectedLine` three lines away sets `・` — and the row's detail line
    /// joined with a Latin one for all eight languages.
    func testTheJapaneseRowJoinsWithJapanesesOwnMiddleDot() throws {
        AppLanguage.override = .ja
        let line = try XCTUnwrap(OneLineUnderTheNameTests.joined(agent(missingTarget: "/opt/gone/helper")))

        XCTAssertTrue(line.contains("・"), "the Japanese row joins with a Latin dot: \(line)")
        XCTAssertFalse(line.contains(" · "), "and it still carries the Latin one: \(line)")
    }

    /// French's space before `: ; ? !` is a character, and the ordinary one is a
    /// *breaking* space — so the mark can start the next line on its own.
    func testFrenchSpacesItsPunctuationInTheInlineTablesToo() {
        AppLanguage.override = .fr
        for line in Self.everyInterpolatedLine(broken: agent(missingTarget: "/opt/gone/helper")) {
            let characters = Array(line)
            for (index, character) in characters.enumerated() where ":;?!".contains(character) {
                let before = index > 0 ? characters[index - 1] : nil
                XCTAssertNotEqual(before, " ", """
                    an ordinary space before \(character), where macOS's French writes U+00A0 \
                    129 times before a colon and 121 before a question mark and never an \
                    ordinary one: \(line)
                    """)
            }
        }
    }

    /// Russian keeps an em dash with the word before it — 8195 unbreakable
    /// spaces to 59 ordinary ones in macOS's own tables, and Russian is the only
    /// one of the eight that does this.
    func testRussianKeepsTheEmDashWithTheWordBeforeIt() {
        AppLanguage.override = .ru
        for line in Self.everyInterpolatedLine(broken: agent(missingTarget: "/opt/gone/helper")) {
            XCTAssertFalse(line.contains(" —"),
                           "an ordinary space before an em dash, so the dash can begin a "
                           + "line by itself: \(line)")
        }
    }

    /// Every line this module builds by interpolation, which is every line the
    /// eight `.strings` files never see.
    private static func everyInterpolatedLine(broken: StaleItem) -> [String] {
        [LfStr.selectedLine(3, "4 KB"),
         LfStr.foundLine(3),
         LfStr.uncheckedLine(3),
         LfStr.couldNotCheck(3),
         LfStr.movedToTrash(3, "4 KB"),
         LfStr.confirmDeleteInUse("com.vendor.updater"),
         LfStr.confirmDeleteUnreadable("com.vendor.updater"),
         LfStr.confirmDeleteUnchecked("com.vendor.updater"),
         LfStr.missingTarget("/opt/gone/helper"),
         OneLineUnderTheNameTests.joined(broken) ?? ""]
    }
}
