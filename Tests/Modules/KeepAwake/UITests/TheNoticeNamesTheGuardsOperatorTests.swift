import HelmUI
import XCTest
@testable import Module_KeepAwake_Engine
@testable import Module_KeepAwake_UI

/// «Stopped below 20 %» is drawn at 20 %.
///
/// `BatteryGuard.shouldDeactivate` is `percent <= threshold`, so the floor is
/// inclusive: the session ends **at** the figure, not under it. That exact
/// mismatch was audited and corrected once already, on the string one function
/// away — `belowPercent`, the note under the slider, whose own doc comment
/// records it: «Every language used to say "below" — and ja/zh said it with
/// 未満 / 低于, the strict operators, in languages that have the inclusive one.»
///
/// `stoppedByBattery` was written ten days after that correction and says the
/// strict operator in all eight languages, including 未満 and 低于 verbatim. It
/// could not be seen until now: the branch that draws it was unreachable from
/// the settings page and the panel's copy is new, so the sentence the audit
/// rejected reached the screen in the same commit that wired the notice up.
///
/// The two strings are about one number and sit six rows apart on one page —
/// «At 20 % or less» under the slider, «Stopped below 20 %» in the notice above
/// it. One of them is wrong about what the Mac does.
///
/// **One function, both surfaces.** The hero and the panel tile draw the same
/// `KAStr.stoppedByBattery`, so this is not asserted twice; what a *render* has
/// to say about the notice is `TheBatteryNoticeReachesThePageTests`'s question,
/// and this is the sentence itself.
final class TheNoticeNamesTheGuardsOperatorTests: XCTestCase {

    private static let floor = 20

    /// The spelling each language uses for the **strict** comparison, as this app
    /// itself used to write it: the table is the one `belowPercent` carried before
    /// the audit, plus French's «sous», which is the same operator in shorter form.
    ///
    /// The figure is interpolated into two of them on purpose. Russian's
    /// *inclusive* form is «при 20 % и ниже» — the same word, after the number,
    /// where the strict form puts it before — so a check for the bare word would
    /// fail the corrected string it is meant to hold up as the good example.
    /// French is the same shape. A word list would have been wrong about two
    /// languages out of eight, which is the sort of check that gets switched off
    /// by hand.
    private static func strictOperator(in language: AppLanguage) -> String {
        switch language {
        case .en: return "below"
        case .ru: return "ниже \(floor)"
        case .es: return "por debajo"
        case .fr: return "sous \(floor)"
        case .de: return "unter"
        case .ja: return "未満"
        case .zh: return "低于"
        case .pt: return "abaixo"
        }
    }

    /// The subject, first: the guard really is inclusive, so there is something
    /// for the sentence to be wrong about. A test about the wording of a boundary
    /// is empty if the boundary moved.
    func testTheGuardStopsAtExactlyTheFloorAndNotOnlyUnderIt() {
        XCTAssertTrue(BatteryGuard.shouldDeactivate(enabled: true, isOnBattery: true,
                                                    percent: Self.floor, threshold: Self.floor),
                      "the guard no longer fires at exactly the floor, so «below» would be "
                      + "the right word and this whole file is about nothing")
        XCTAssertFalse(BatteryGuard.shouldDeactivate(enabled: true, isOnBattery: true,
                                                     percent: Self.floor + 1,
                                                     threshold: Self.floor),
                       "a percent above the floor stops the session")
    }

    /// And 0 % is under every floor the slider offers, in case the reading above
    /// is the only one anybody trusts.
    func testTheGuardFiresAtNothingLeftAtAll() {
        XCTAssertTrue(BatteryGuard.shouldDeactivate(enabled: true, isOnBattery: true,
                                                    percent: 0, threshold: 5))
    }

    func testTheNoticeDoesNotClaimAStrictFloorInAnyLanguage() {
        let previous = AppLanguage.override
        defer { AppLanguage.override = previous }

        for language in AppLanguage.allCases {
            AppLanguage.override = language
            let sentence = KAStr.stoppedByBattery(Self.floor)
            XCTAssertTrue(sentence.contains("\(Self.floor)"),
                          "\(language.rawValue): «\(sentence)» does not carry the floor at all")
            XCTAssertFalse(sentence.localizedLowercase
                .contains(Self.strictOperator(in: language).localizedLowercase),
                           "\(language.rawValue): «\(sentence)» says the session stopped "
                           + "*below* \(Self.floor) %, and `BatteryGuard` stops at it — the "
                           + "same defect the audit corrected in `belowPercent`, which sits "
                           + "six rows under this notice saying «\(KAStr.belowPercent(Self.floor))»")
        }
    }

    /// The control, and the reason the table above is a list of eight real
    /// spellings rather than eight guesses: the string that *was* corrected is
    /// clean against the very same table. Without this, a table of words no
    /// language ever uses would pass the check above for ever.
    func testTheCorrectedRowIsCleanAgainstTheSameTable() {
        let previous = AppLanguage.override
        defer { AppLanguage.override = previous }

        for language in AppLanguage.allCases {
            AppLanguage.override = language
            let row = KAStr.belowPercent(Self.floor)
            XCTAssertFalse(row.localizedLowercase
                .contains(Self.strictOperator(in: language).localizedLowercase),
                           "\(language.rawValue): the corrected string «\(row)» matches the "
                           + "strict spelling this file looks for, so the check is testing the "
                           + "table rather than the app")
        }
    }

    /// The eight readings really are eight. An inline table wins outright over the
    /// `.lproj` files, so a language that never reaches `L` would give English
    /// eight times — and English is the one language whose marker is a bare word.
    func testEachLanguageDrawsItsOwnSentence() {
        let previous = AppLanguage.override
        defer { AppLanguage.override = previous }

        var seen: Set<String> = []
        for language in AppLanguage.allCases {
            AppLanguage.override = language
            seen.insert(KAStr.stoppedByBattery(Self.floor))
        }
        XCTAssertEqual(seen.count, AppLanguage.allCases.count,
                       "\(seen.count) distinct sentences for \(AppLanguage.allCases.count) "
                       + "languages — the override is not reaching `KAStr`")
    }
}
