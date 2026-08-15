import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
@testable import Module_Duplicates_UI

/// The group header says what the group is worth, not only what it is.
///
/// «21 MB × 2» is the size of the copy that stays times how many there are —
/// true, and read as «21 MB comes back». For a clone pair the page's every
/// other figure knows better (`DuplicateGroup.reclaimable`), and the header was
/// the one line still inviting the doubled reading. It now carries the group's
/// own `wasted` through the same tail the toolbar total uses, so the two cannot
/// part company.
final class TheGroupHeaderSaysWhatItIsWorthTests: XCTestCase {

    /// One tail, two readers: the total line is built from the same sentence
    /// the header draws, in every language — a second spelling of «once the
    /// Trash is emptied» would be free to drift the way `movedToTrash` did.
    func testTheTotalLineIsBuiltFromTheHeadersOwnTail() {
        for language in AppLanguage.allCases {
            let size = HelmBytes.string(118_900_000_000, language: language.rawValue)
            XCTAssertTrue(DupStr.found(12_345, size, language: language)
                .contains(DupStr.onceEmptied(size, language: language)), """
                \(language.rawValue): the toolbar total no longer contains the tail the \
                group header draws, so the two spellings are free to drift apart.
                """)
        }
    }

    /// The header's figure is `wasted` — the clone-aware fold — and not the
    /// size of the survivor. Read from the source the way
    /// `TheGroupHeaderKeepsItsButtonsTests` reads it, because the claim is
    /// about which value is drawn.
    func testTheHeaderDrawsTheGroupsWasted() throws {
        let page = try RepoSource.text(of: "Sources/Modules/Duplicates/UI/DuplicatesView.swift")
        let opens = try XCTUnwrap(page.range(of: "private func header(_ group: DuplicateGroup"))
        let closes = try XCTUnwrap(page.range(of: "\n    }",
                                              range: opens.upperBound..<page.endIndex))
        let header = String(page[opens.lowerBound..<closes.upperBound])

        XCTAssertTrue(header.contains("DupStr.onceEmptied(Bytes(group.wasted))"), """
            The header no longer says what removing the group's extras returns, \
            so a clone pair reads as recoverable space again.
            """)
    }
}
