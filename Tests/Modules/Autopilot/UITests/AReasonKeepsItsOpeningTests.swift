import HelmTestSupport
import XCTest
@testable import Module_Autopilot_UI

/// The detail column truncates at the tail, not the middle.
///
/// Middle truncation is for paths, where both ends carry meaning. This
/// column never holds one: `ActionRecord.of` stores a folder's *name* for a
/// move, the landed name for a rename, the tag for a tag — and for a refusal
/// or a failure, a whole sentence. Cut in the middle, the audit read
/// «отказано: в…ённых папок» — a reason with its reason removed. The file
/// name beside it keeps `.middle`, being the one thing in the row that is a
/// name with a meaningful extension.
final class AReasonKeepsItsOpeningTests: XCTestCase {

    func testTheDetailTruncatesAtTheTail() throws {
        let lines = try RepoSource.lines(of:
            "Sources/Modules/Autopilot/UI/HistorySection.swift")
        let detail = try XCTUnwrap(lines.firstIndex { $0.contains("Text(detail(record))") },
                                   "the row no longer draws the detail under that name")
        let following = lines[detail...].prefix(5).joined(separator: "\n")
        XCTAssertTrue(following.contains(".truncationMode(.tail)"), """
            The detail truncates in the middle, which cuts a refusal's sentence \
            to nonsense: \(following)
            """)
    }
}
