import HelmRuntime
import HelmUI
import XCTest
@testable import Module_Duplicates_UI

/// The two lines of this module that can carry a six-digit figure: a photo
/// library really produces `12345` groups (the count `DuplicatesBarWidthTests`
/// measures the toolbar with), and the busy line's candidate count runs over
/// every large file under the folder. Disk's guard explains the family —
/// `Count` in `L10n.swift` existed and nothing called it.
final class BigCountsReadGroupedTests: XCTestCase {

    private let count = 1_499_308

    func testTheProgressLineGroupsBothCounts() {
        for language in AppLanguage.allCases {
            let text = DupStr.progressLine(123_456, count, language: language)
            XCTAssertFalse(text.contains("1499308"),
                           "progressLine writes raw digits in \(language.rawValue): «\(text)»")
            XCTAssertTrue(text.contains(HelmBytes.grouped(123_456, language: language.rawValue)),
                          "progressLine leaves the done count ungrouped in \(language.rawValue): «\(text)»")
        }
    }

    func testTheFoundLineGroupsItsGroupCount() {
        for language in AppLanguage.allCases {
            let text = DupStr.found(count, "1 GB", language: language)
            XCTAssertFalse(text.contains("1499308"),
                           "found writes raw digits in \(language.rawValue): «\(text)»")
            XCTAssertTrue(text.contains(HelmBytes.grouped(count, language: language.rawValue)),
                          "found leaves its count ungrouped in \(language.rawValue): «\(text)»")
        }
    }
}
