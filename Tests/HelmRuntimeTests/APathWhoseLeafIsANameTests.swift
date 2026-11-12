import Foundation
import XCTest
@testable import HelmRuntime

/// `Redact.path` hides the account name and nothing else, which is right for a
/// module whose paths name the person's folders. The reading for a leaf that
/// **is** the name of software is held by `RedactSoftwareLeavesNobodyFedTests`.
final class APathWhoseLeafIsANameTests: XCTestCase {
    private let home = "/Users/x"

    /// **The default has to stay `.fileName`.** Disk and Duplicates print the
    /// person's own file names home-relative through the same three lines, and
    /// whether that should change is a decision about those modules — not something
    /// to inherit from a default that moved.
    func testAnOrdinaryFileNameIsUntouchedBeyondTheHome() {
        let line = "/Users/x/Documents/thesis final.pdf"
        XCTAssertEqual(Redact.path(line, leaf: .fileName, home: home), "~/Documents/thesis final.pdf")
        XCTAssertEqual(Redact.path(line, leaf: .fileName, home: home),
                       Redact.path(line, home: home),
                       "the two readings must agree wherever the leaf is a document")
    }
}
