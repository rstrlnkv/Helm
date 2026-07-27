import Foundation
import XCTest
@testable import Module_Autopilot_Engine

/// The two actions that compute a name rather than a destination.
///
/// Both are pure string work, and both are where a rule can quietly produce
/// something the filesystem will not take — an empty name, a name with a
/// slash in it, a name that is only an extension. Those are the tests.
final class RenamePatternTests: XCTestCase {

    private func facts(_ name: String, kind: FileKind = .document,
                       addedDaysAgo: Double = 0) -> FileFacts {
        // 2026-07-15 12:00 UTC, so the month bucket is checkable.
        let now = Date(timeIntervalSince1970: 1_784_116_800)
        return FileFacts(name: name, kind: kind, bytes: 1,
                         added: now.addingTimeInterval(-addedDaysAgo * 86_400),
                         modified: now, now: now)
    }

    // MARK: - Rename

    func testTheTokensAreSubstituted() {
        let f = facts("report.pdf")
        XCTAssertEqual(RenamePattern.apply("{name}-final", to: f), "report-final.pdf")
        XCTAssertEqual(RenamePattern.apply("{date} {name}", to: f), "2026-07-15 report.pdf")
    }

    /// The extension is the file's, not the pattern's business: a rule that
    /// renames a PDF must not be able to make it a `.txt` by accident.
    func testTheExtensionIsAlwaysTheFilesOwn() {
        XCTAssertEqual(RenamePattern.apply("{name}.txt", to: facts("a.pdf")), "a.txt.pdf")
        XCTAssertEqual(RenamePattern.apply("plain", to: facts("a.pdf")), "plain.pdf")
    }

    func testAFileWithNoExtensionStaysThatWay() {
        XCTAssertEqual(RenamePattern.apply("{name}-1", to: facts("Makefile")), "Makefile-1")
    }

    /// A counter is what makes a pattern usable on more than one file. It is
    /// supplied by the caller, because only the caller knows how many came
    /// before.
    func testTheCounterIsPaddedAndSupplied() {
        let f = facts("shot.png")
        XCTAssertEqual(RenamePattern.apply("{name}-{counter}", to: f, counter: 7),
                       "shot-007.png")
    }

    /// A pattern that produces nothing usable leaves the file alone. Returning
    /// an empty name would be a rule that deletes a file's identity.
    func testAPatternThatProducesNothingIsRefused() {
        XCTAssertNil(RenamePattern.apply("", to: facts("a.pdf")))
        XCTAssertNil(RenamePattern.apply("   ", to: facts("a.pdf")))
    }

    /// A slash in a name is a path, and a rename that becomes a move is the
    /// one way this action could reach outside the folder it was given.
    func testPathSeparatorsAreRefused() {
        XCTAssertNil(RenamePattern.apply("../{name}", to: facts("a.pdf")))
        XCTAssertNil(RenamePattern.apply("sub/{name}", to: facts("a.pdf")))
        XCTAssertNil(RenamePattern.apply("a:b", to: facts("a.pdf")))
    }

    /// A leading dot hides the file from Finder — not what anyone means by a
    /// renaming rule.
    func testALeadingDotIsRefused() {
        XCTAssertNil(RenamePattern.apply(".{name}", to: facts("a.pdf")))
    }

    // MARK: - Sort buckets

    func testKindBuckets() {
        XCTAssertEqual(SortBucket.name(for: facts("a.png", kind: .image), scheme: .kind),
                       "Images")
        XCTAssertEqual(SortBucket.name(for: facts("a.zip", kind: .archive), scheme: .kind),
                       "Archives")
        XCTAssertEqual(SortBucket.name(for: facts("a.bin", kind: .other), scheme: .kind),
                       "Other")
    }

    /// The month a file was added, not the month it was last touched: sorting
    /// by "when this arrived" is what a Downloads folder is asking for.
    func testMonthBucketUsesTheDateAdded() {
        XCTAssertEqual(SortBucket.name(for: facts("a.pdf"), scheme: .month), "2026-07")
        XCTAssertEqual(SortBucket.name(for: facts("a.pdf", addedDaysAgo: 40), scheme: .month),
                       "2026-06")
    }

    /// Fixed regardless of locale: a folder named `2026-07` sorts by name into
    /// chronological order, and one named `июль 2026` does not.
    func testTheMonthBucketIsNotLocalised() {
        let bucket = SortBucket.name(for: facts("a.pdf"), scheme: .month)
        XCTAssertEqual(bucket.count, 7)
        XCTAssertTrue(bucket.allSatisfy { $0.isNumber || $0 == "-" })
    }
}
