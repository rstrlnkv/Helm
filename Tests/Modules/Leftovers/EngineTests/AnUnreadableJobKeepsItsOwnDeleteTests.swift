import Foundation
import XCTest
@testable import Module_Leftovers_Engine

/// A row Helm could not read is still a row somebody may delete on purpose, and
/// two things hold of it: the row keeps its own delete while the batch does not,
/// and the switch is not offered on a guessed label.
///
/// An unreadable launchd job is kept out of «Select all»
/// (`APlistNobodyCouldReadTests`), which leaves the row's own menu. The question
/// that menu asks first is a rule of `Architecture/Leftovers.md`.
final class AnUnreadableJobKeepsItsOwnDeleteTests: XCTestCase {

    private func item(_ status: ItemStatus) -> StaleItem {
        StaleItem(path: "/Users/x/Library/LaunchAgents/com.vendor.updater.plist",
                  identifier: "com.vendor.updater", kind: .launchAgent, sizeBytes: 100,
                  status: status)
    }

    /// The bulk tick is the offer being withheld, and the row's own delete is not
    /// — a row nobody can read is worth showing, and worth being able to clear
    /// deliberately.
    func testTheRowKeepsItsOwnDeleteWhileTheBatchDoesNot() {
        XCTAssertFalse(item(.unreadable).removable,
                       "«Select all» ticks a job whose plist could not be read")
        XCTAssertTrue(LeftoverActions.available(for: item(.unreadable)).contains(.delete),
                      "and the row's own menu lost the way to clear it")
    }

    /// **And it does not offer the switch, because the label is a guess.**
    /// `LaunchAgentReader` falls back to the file name when `Label` cannot be
    /// read, which is right for a job that *omits* the key — launchd does the same
    /// — and is an invention for a file whose contents never came. Sending that
    /// guess to `launchctl disable` would write an entry under a name that may be no
    /// job at all, and the row would read it back and wear «Disabled» over a job
    /// nobody switched off.
    func testAnUnreadableJobIsNotOfferedTheSwitchEither() {
        XCTAssertFalse(item(.unreadable).canToggle)
        XCTAssertTrue(item(.inUse).canToggle,
                      "precondition: an agent Helm did read still offers it")
    }
}
