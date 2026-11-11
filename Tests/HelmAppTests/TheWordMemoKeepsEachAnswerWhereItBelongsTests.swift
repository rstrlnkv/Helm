import XCTest
import Foundation
import HelmRuntime
import HelmUI
import HelmAppStrings

/// `L(_ resource:language:)` remembers each answer, and what identifies an
/// answer is more than its key: the catalog it was read from, the language and
/// the arguments. A memo that leaves one of those out answers every later ask
/// with the first asker's word, and nothing on the screen says so, so this holds
/// the four parts apart on real catalogs, bundles reached by URL from the test
/// bundle's own folder, the way the shipped modules reach theirs.
///
/// What this does not hold is the memo's size: the entry count has no accessor,
/// so a memo that never forgets passes here, and nothing else sees it.
final class TheWordMemoKeepsEachAnswerWhereItBelongsTests: XCTestCase {
    private func bundleURL(_ name: String) -> URL {
        Bundle(for: TheWordMemoKeepsEachAnswerWhereItBelongsTests.self).bundleURL
            .deletingLastPathComponent().appendingPathComponent("Helm_\(name).bundle")
    }

    /// `other` is in two catalogs with two different words ("Other…" / "Other").
    private func res(_ key: String, in name: String) -> LocalizedStringResource {
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundleURL(name).path), name)
        return LocalizedStringResource(String.LocalizationValue(key), table: nil,
                                       bundle: .atURL(bundleURL(name)))
    }

    override func tearDown() { AppLanguage.override = nil }

    func testSameKeyInTwoCatalogsStaysTwoAnswers() {
        let keepAwake = res("other", in: "Module_KeepAwake_UI")
        let autopilot = res("other", in: "Module_Autopilot_UI")
        for _ in 0..<2 {
            XCTAssertEqual(L(keepAwake, language: .ru), "Другое…")
            XCTAssertEqual(L(autopilot, language: .ru), "Другое")
            XCTAssertEqual(L(autopilot, language: .en), "Other")
            XCTAssertEqual(L(keepAwake, language: .en), "Other…")
        }
    }

    func testLanguageIsPartOfTheAnswer() {
        let autopilot = res("other", in: "Module_Autopilot_UI")
        for _ in 0..<2 {
            XCTAssertEqual(L(autopilot, language: .ru), "Другое")
            XCTAssertEqual(L(autopilot, language: .en), "Other")
            XCTAssertEqual(L(autopilot, language: .ru), "Другое")
        }
    }

    func testArgumentIsPartOfTheAnswer() {
        AppLanguage.override = .ru
        for _ in 0..<2 {
            XCTAssertEqual(AppStr.logErrorCount(3), "3 ошибки")
            XCTAssertEqual(AppStr.logErrorCount(4), "4 ошибки")
            XCTAssertEqual(AppStr.logErrorCount(7), "7 ошибок")
            XCTAssertEqual(AppStr.logErrorCount(1), "1 ошибка")
        }
    }

    /// Far more values of one template than the memo keeps: every answer still
    /// belongs to its own value, on the way in and on the way round again.
    func testAnswersSurviveTheMemoForgetting() {
        AppLanguage.override = .en
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en")
        func want(_ i: Int) -> String {
            i == 1 ? "1 error" : "\(formatter.string(from: NSNumber(value: i))!) errors"
        }
        for i in 0..<9000 { XCTAssertEqual(AppStr.logErrorCount(i), want(i), "at \(i)") }
        for i in stride(from: 0, to: 9000, by: 997) { XCTAssertEqual(AppStr.logErrorCount(i), want(i)) }
    }

    /// The changelog holds one sub-bundle per language instead of going through
    /// `L`, and must follow the language the person picks, back and forth.
    func testChangelogFollowsTheLanguage() {
        func firstFix() -> String { Changelog.entries[0].items[0].text }
        AppLanguage.override = .en; let en = firstFix()
        AppLanguage.override = .ru; let ru = firstFix()
        AppLanguage.override = .de; let de = firstFix()
        AppLanguage.override = .ru; let ruAgain = firstFix()
        AppLanguage.override = .en; let enAgain = firstFix()
        XCTAssertNotEqual(en, ru); XCTAssertNotEqual(ru, de); XCTAssertNotEqual(en, de)
        XCTAssertEqual(ru, ruAgain); XCTAssertEqual(en, enAgain)
        XCTAssertTrue(ru.unicodeScalars.contains { $0.value >= 0x400 && $0.value < 0x500 }, ru)
    }
}
