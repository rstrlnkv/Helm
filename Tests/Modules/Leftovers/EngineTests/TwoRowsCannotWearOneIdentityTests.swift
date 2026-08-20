import Foundation
import HelmRuntime
import XCTest
@testable import Module_Leftovers_Engine

/// **`StaleItem.id` is the path, and a system extension's path is its
/// identifier** — so two records of one extension are two rows with one id.
///
/// `systemextensionsctl list` prints a line per *record*, not per extension, and
/// an upgrade leaves two: the new one `[activated enabled]` and the old one
/// `[terminated waiting to uninstall on reboot]`. `SystemExtensionParser.parse`
/// answers one `SystemExtensionInfo` a line, correctly — the state and the
/// version differ — and `LeftoversScanner.systemExtensions` then builds a
/// `StaleItem` per record whose `path` is `info.identifier`, which is the same
/// string for both.
///
/// Two things rest on that string being unique to a row, and both are stated in
/// this module's own comments:
///
///   • **The sort.** «The path breaks the tie, because the identifier does not
///     always … The path is unique by construction: it is the item's `id`»
///     (`LeftoversScanner.scan`). For these two rows both keys are equal, so the
///     comparator is false in both directions, Swift's sort is not stable, and
///     «Scan again» may swap a pair whose badges disagree — one carries
///     `runAtLoad` from `enabled`, the other does not. That is the very defect
///     `ScanOrderIsTotalTests` was written for, in the one kind of row where the
///     fix does not reach.
///   • **The list.** `LeftoversSettingsPage` draws `ForEach(group.items)` over
///     `Identifiable`, and a duplicate id there is undefined by SwiftUI's own
///     documentation — rows drop, or repeat, or animate into each other. The
///     selection is a `Set<String>` of paths for the same reason.
///
/// The fixture is two records of one identifier because that is what the port
/// hands back; `LeftoversFakeLoaded` has always been able to hold it, and no test
/// had used it — a capability of a fake nobody has exercised is a missing test,
/// not dead weight (CLAUDE.md).
final class TwoRowsCannotWearOneIdentityTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/x")

    /// The two lines `systemextensionsctl` prints while an upgrade waits for a
    /// reboot: same bundle id, different version, different state, and only the
    /// new one enabled.
    private let upgrading = [
        SystemExtensionInfo(identifier: "com.vendor.app.networkextension", teamID: "T1",
                            name: "Vendor Network", version: "2.0/2258",
                            state: "activated enabled", enabled: true),
        SystemExtensionInfo(identifier: "com.vendor.app.networkextension", teamID: "T1",
                            name: "Vendor Network", version: "1.9/2201",
                            state: "terminated waiting to uninstall on reboot", enabled: false),
    ]

    private func scan() -> [StaleItem] {
        LeftoversScanner(home: home, files: LeftoversFakeFiles(),
                         apps: LeftoversFakeApps(ids: []),
                         extensions: LeftoversFakeLoaded(installed: upgrading)).scan()
    }

    /// **The finding.** Every row in a list drawn by `id` needs an id of its own.
    func testEveryRowInAScanHasAnIdNoOtherRowHas() {
        let items = scan()

        XCTAssertEqual(items.count, 2, "precondition: both records reached the list")
        XCTAssertEqual(Set(items.map(\.id)).count, items.count, """
            \(items.count) rows carry \(Set(items.map(\.id)).count) id(s): \
            \(items.map(\.id)). `StaleItem.id` is `path`, and a system extension's \
            path is its identifier, so the two records of one extension are one \
            identity — which is undefined in the `ForEach` the page draws them \
            with, and unbreakable by the sort that exists to keep a list from \
            reshuffling itself between scans.
            """)
    }

    /// And the pair the sort cannot order, said as the sort says it: neither row
    /// is less than the other, so nothing decides which is drawn first.
    ///
    /// Read off the two rows the scan produced rather than off the comparator
    /// re-typed here — a check whose two sides are one spelling is not a check.
    func testTheSortHasNothingLeftToBreakTheTieWith() {
        let items = scan()
        guard items.count == 2 else {
            return XCTFail("precondition: both records reached the list")
        }
        let (first, second) = (items[0], items[1])

        XCTAssertFalse(first.identifier == second.identifier && first.path == second.path, """
            Both of the scan's sort keys are equal for these two rows — identifier \
            \(first.identifier) and path \(first.path) — so the order they come \
            back in is whatever the sort happened to leave, and the badges differ: \
            runAtLoad \(first.runAtLoad) against \(second.runAtLoad). Pressing \
            «Scan again» can swap them.
            """)
    }
}
