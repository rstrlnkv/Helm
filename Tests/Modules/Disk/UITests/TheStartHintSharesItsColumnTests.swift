import HelmTestSupport
import XCTest
@testable import Module_Disk_UI

/// The start screen's opening line sat centred over a left-aligned column:
/// `startHint` had no frame, so the `VStack` centred it, while the lost-list
/// note directly under it — and every card below — pins to the leading edge.
/// One alignment for the one column; `StartScreenColumnTests` already holds
/// the column against its header, and this is the same rule one line up.
final class TheStartHintSharesItsColumnTests: XCTestCase {

    func testTheHintPinsToTheLeadingEdgeLikeTheNoteUnderIt() throws {
        let lines = try RepoSource.lines(of: "Sources/Modules/Disk/UI/DiskSettingsPage.swift")
        let hint = try XCTUnwrap(lines.firstIndex { $0.contains("Text(DkStr.startHint)") },
                                 "the start screen no longer opens with that line")
        let following = lines[hint...].prefix(4).joined(separator: "\n")
        XCTAssertTrue(following.contains(".frame(maxWidth: .infinity, alignment: .leading)"), """
            The start hint centres while everything under it starts at the \
            leading edge: \(following)
            """)
    }
}
