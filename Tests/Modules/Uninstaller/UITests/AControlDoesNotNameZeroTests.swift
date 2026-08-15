import HelmUI
import XCTest
@testable import Module_Uninstaller_UI

/// The Review button with nothing checked read «Просмотреть: 0» — a disabled
/// control naming a count of nothing, which is the same family as «0 apps»
/// over an unanswered list (`AnUnansweredListIsNotAnEmptyMacTests`): a number
/// that states more than anybody knows or needs. At zero the button says only
/// its verb; the count returns with the first tick.
final class AControlDoesNotNameZeroTests: XCTestCase {

    func testAtZeroTheButtonSaysOnlyItsVerb() {
        for language in AppLanguage.allCases {
            let label = UnStr.reviewCount(0, language: language)
            XCTAssertFalse(label.contains("0"),
                           "\(language.rawValue): «\(label)» names a count of nothing")
            XCTAssertFalse(label.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(language.rawValue): the zero branch left the button blank")
        }
    }

    /// And with something checked the count is still there — the guard must
    /// not silence the number that makes the button worth reading.
    func testACountedPressKeepsItsCount() {
        for language in AppLanguage.allCases {
            XCTAssertTrue(UnStr.reviewCount(3, language: language).contains("3"),
                          language.rawValue)
        }
    }
}
