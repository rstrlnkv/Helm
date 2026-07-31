import XCTest
@testable import Module_Autopilot_Engine

/// Matching a file's name without its extension.
///
/// `.name` compares `url.lastPathComponent`, which carries the extension — so
/// "name is report" never matches `report.pdf`, on a screen that offers
/// Extension as a separate field one row up. Hazel, which everybody has in
/// mind, strips the extension for Name and offers Full name separately.
///
/// The fix is a second condition rather than a changed one: somebody's rule
/// saying "name contains .pdf" works today, and quietly turning it into a rule
/// that never fires is the worst kind of break — no error, no message, and an
/// Autopilot that simply stops tidying.
final class BaseNameConditionTests: XCTestCase {

    private func facts(_ name: String) -> FileFacts {
        FileFacts(name: name, kind: .document, bytes: 10,
                  added: Date(timeIntervalSince1970: 0),
                  modified: Date(timeIntervalSince1970: 0))
    }

    func testTheNameWithoutItsExtensionMatchesExactly() {
        XCTAssertTrue(RuleMatcher.holds(.baseName(.is, "report"), facts("report.pdf")))
    }

    /// The case that motivates the whole thing: the same rule against `.name`
    /// is false, and both must stay true of their own field.
    func testTheFullNameConditionIsUnchanged() {
        XCTAssertFalse(RuleMatcher.holds(.name(.is, "report"), facts("report.pdf")))
        XCTAssertTrue(RuleMatcher.holds(.name(.is, "report.pdf"), facts("report.pdf")))
    }

    func testAFileWithNoExtensionIsItsOwnBaseName() {
        XCTAssertTrue(RuleMatcher.holds(.baseName(.is, "README"), facts("README")))
    }

    /// A dotfile is not an extension with an empty name: `.gitignore` is called
    /// `.gitignore`, and a rule for it must be writable.
    func testADotfileKeepsItsWholeName() {
        XCTAssertTrue(RuleMatcher.holds(.baseName(.is, ".gitignore"), facts(".gitignore")))
    }

    /// Only the last dot is the extension — `archive.tar.gz` is `archive.tar`,
    /// which is what `deletingPathExtension` says and what Finder shows.
    func testOnlyTheLastDotSeparatesTheExtension() {
        XCTAssertTrue(RuleMatcher.holds(.baseName(.is, "archive.tar"), facts("archive.tar.gz")))
    }

    func testContainsAndBeginsWorkOnTheBaseName() {
        XCTAssertTrue(RuleMatcher.holds(.baseName(.contains, "port"), facts("report.pdf")))
        XCTAssertTrue(RuleMatcher.holds(.baseName(.beginsWith, "rep"), facts("report.pdf")))
    }

    /// Case matters to a filesystem and not to a person writing a rule — the
    /// same rule `.name` already keeps.
    func testCaseDoesNotDecide() {
        XCTAssertTrue(RuleMatcher.holds(.baseName(.is, "REPORT"), facts("report.pdf")))
    }

    /// The extension is not searchable through this field: that is what the
    /// Extension condition is for, and a rule that found `.pdf` here would be
    /// the confusion this exists to end.
    func testTheExtensionIsNotPartOfTheBaseName() {
        XCTAssertFalse(RuleMatcher.holds(.baseName(.contains, "pdf"), facts("report.pdf")))
    }
}
