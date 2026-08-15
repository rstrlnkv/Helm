import HelmRuntime
import HelmUI
import XCTest
@testable import Module_Disk_UI

/// A scan of `/` really reports seven digits, and seven ungrouped digits are
/// read by counting them: the ring's statement said "1499308 files" while
/// macOS itself groups the digits everywhere it counts anything.
///
/// `Count` exists for exactly this — it lives beside `Bytes` and `Decimal` in
/// `L10n.swift` — and at the time this test was written nothing called it, so
/// deleting it broke no test. This is the call-site guard: the three lines of
/// this module that can carry a six-digit figure go through it, in every
/// language named outright, since the suite runs in whatever this machine is
/// set to.
final class BigCountsReadGroupedTests: XCTestCase {

    /// The count the defect shipped with, and one that cannot appear grouped
    /// by accident: every language writes it with at least one separator.
    private let files = 1_499_308

    /// The other half of the guard, or the two assertions below become one
    /// shared constant: if the formatter itself stopped grouping, the line and
    /// the expectation would agree on ungrouped digits and nothing would fail.
    func testTheGroupedFormIsNotTheRawDigits() {
        for language in AppLanguage.allCases {
            XCTAssertNotEqual(HelmBytes.grouped(files, language: language.rawValue),
                              "1499308", language.rawValue)
        }
    }

    func testTheScanStatementGroupsItsFileCount() {
        assertGrouped("scannedIn") { DkStr.scannedIn(self.files, "12", language: $0) }
    }

    func testTheStoppedHintGroupsItsFileCount() {
        assertGrouped("stoppedHint") { DkStr.stoppedHint(self.files, language: $0) }
    }

    func testTheLiveCountGroupsItsFileCount() {
        assertGrouped("liveCount") { DkStr.liveCount(self.files, language: $0) }
    }

    private func assertGrouped(_ name: String, _ line: (AppLanguage) -> String,
                               file: StaticString = #filePath, line lineNo: UInt = #line) {
        for language in AppLanguage.allCases {
            let text = line(language)
            XCTAssertFalse(text.contains("1499308"),
                           "\(name) writes raw digits in \(language.rawValue): «\(text)»",
                           file: file, line: lineNo)
            XCTAssertTrue(text.contains(HelmBytes.grouped(files, language: language.rawValue)),
                          "\(name) does not carry the grouped count in \(language.rawValue): «\(text)»",
                          file: file, line: lineNo)
        }
    }
}
