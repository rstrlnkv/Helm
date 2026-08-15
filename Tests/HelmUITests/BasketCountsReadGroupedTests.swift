import HelmRuntime
import XCTest
@testable import HelmUI

/// The basket line both Disk and Duplicates draw. «Mark every extra copy» over
/// a large library puts a five- or six-digit count here, and the shared bar
/// must group it the way the counts around it now do — Disk's
/// `BigCountsReadGroupedTests` names the family.
final class BasketCountsReadGroupedTests: XCTestCase {

    private let count = 1_499_308

    func testTheBasketLineGroupsItsCount() {
        for language in AppLanguage.allCases {
            let text = HelmBasket.line(count: count, size: "1 GB", language: language)
            XCTAssertFalse(text.contains("1499308"),
                           "the basket line writes raw digits in \(language.rawValue): «\(text)»")
            XCTAssertTrue(text.contains(HelmBytes.grouped(count, language: language.rawValue)),
                          "the basket line leaves its count ungrouped in \(language.rawValue): «\(text)»")
        }
    }
}
