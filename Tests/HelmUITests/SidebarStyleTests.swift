import XCTest
@testable import HelmUI

/// A stored enum is two things that can disagree: the value and the string it
/// becomes. The round trip is the only assertion that catches a case added to
/// one and not the other.
final class SidebarStyleTests: XCTestCase {

    func testRoundTripsThroughItsRawValue() {
        for style in SidebarStyle.allCases {
            XCTAssertEqual(SidebarStyle(stored: style.rawValue), style)
        }
    }

    /// An unknown string is what a downgrade looks like: a newer build wrote a
    /// case this one has never heard of. Falling back beats crashing, and
    /// falling back to `.colour` beats `.plain` — the person chose a look, and
    /// the richer one is the one they can see is wrong.
    func testUnknownStoredValueFallsBackToColour() {
        XCTAssertEqual(SidebarStyle(stored: "rainbow"), .colour)
        XCTAssertEqual(SidebarStyle(stored: ""), .colour)
    }

    /// The raw values are written to disk. Renaming one silently resets every
    /// existing install, so they are pinned here rather than derived.
    func testRawValuesArePinned() {
        XCTAssertEqual(SidebarStyle.colour.rawValue, "colour")
        XCTAssertEqual(SidebarStyle.plain.rawValue, "plain")
    }

    /// The key is written to `UserDefaults` and read by two call sites — the
    /// settings control that sets it and the sidebar that draws by it. Pinning
    /// it here is what stops one of them being renamed alone.
    func testTheStorageKeyIsPinned() {
        XCTAssertEqual(SidebarStyle.storageKey, "sidebarStyle")
    }
}
