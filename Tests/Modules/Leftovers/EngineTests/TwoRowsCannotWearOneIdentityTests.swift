import Foundation
import HelmRuntime
import XCTest
@testable import Module_Leftovers_Engine

/// **`StaleItem.id` is the path, and two records of one system extension are
/// two rows with two ids.**
///
/// `systemextensionsctl list` prints a line per *record*, not per extension, and
/// an upgrade leaves two: the new one `[activated enabled]` and the old one
/// `[terminated waiting to uninstall on reboot]`, with one identifier.
///
/// Two things rest on a row's id being unique:
///
///   • **The sort.** «The path breaks the tie … it is the item's `id`»
///     (`LeftoversScanner.scan`). With both keys equal the comparator is false
///     both ways, Swift's sort is not stable, and «Scan again» could swap a pair
///     whose badges disagree.
///   • **The list.** `LeftoversSettingsPage` draws `ForEach(group.items)` over
///     `Identifiable`, and a duplicate id there is undefined by SwiftUI's own
///     documentation. The selection is a `Set<String>` of paths for the same
///     reason.
///
/// The fixture is two records of one identifier because that is what the port
/// hands back (Architecture/TestsAndMeasurement.md § Fakes).
final class TwoRowsCannotWearOneIdentityTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/x")

    /// The two lines `systemextensionsctl` prints while an upgrade waits for a
    /// reboot: same bundle id, different version, and only the
    /// new one enabled.
    private let upgrading = [
        SystemExtensionInfo(identifier: "com.vendor.app.networkextension", version: "2.0/2258", enabled: true),
        SystemExtensionInfo(identifier: "com.vendor.app.networkextension", version: "1.9/2201", enabled: false),
    ]

    private func scan() -> [StaleItem] {
        LeftoversScanner(home: home, files: LeftoversFakeFiles(),
                         apps: LeftoversFakeApps(ids: []),
                         extensions: LeftoversFakeLoaded(installed: upgrading)).scan()
    }

    /// **The guard.** Every row in a list drawn by `id` needs an id of its own.
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

    /// And the tie the sort must be able to break: the two rows differ by
    /// the key the sort reads, so something decides which is drawn first.
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
