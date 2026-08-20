import Foundation
import HelmRuntime
import XCTest
@testable import Module_Leftovers_Engine

/// **Unique within one scan is not the same as the same row between two.**
///
/// `TwoRowsCannotWearOneIdentityTests` asks that two records of one system
/// extension carry two ids, and an ordinal — first record, second record — answers
/// that on its own. It answers it the way the defect was written, though: the row's
/// identity would then be its *position in `systemextensionsctl list`*, and the
/// tool's order is not a promise. The pair would swap between two scans exactly as
/// they did when both rows had one id, only with the swap now moving the ids as
/// well, so `ScanOrderIsTotalTests`' subject — «Scan again» must not reshuffle a
/// list for no reason a person can see — is still open.
///
/// So the spelling is read from the record: the version tells the activated one
/// from the one waiting for a reboot, and an ordinal is only what is left where two
/// records are identical in every field the tool prints — where a swap is invisible
/// because the two rows are.
final class ARecordKeepsItsIdBetweenScansTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/x")

    private func record(_ version: String, enabled: Bool) -> SystemExtensionInfo {
        SystemExtensionInfo(identifier: "com.vendor.app.networkextension", teamID: "T1",
                            name: "Vendor Network", version: version,
                            state: enabled ? "activated enabled"
                                           : "terminated waiting to uninstall on reboot",
                            enabled: enabled)
    }

    private func scan(_ list: [SystemExtensionInfo]) -> [StaleItem] {
        LeftoversScanner(home: home, files: LeftoversFakeFiles(),
                         apps: LeftoversFakeApps(ids: []),
                         extensions: LeftoversFakeLoaded(installed: list)).scan()
    }

    /// **The finding.** The tool prints the same two records in the other order, and
    /// the row that carries «At login» must still be the same row.
    func testARecordCarriesItsIdWhicheverOrderTheToolPrintsItIn() throws {
        let new = record("2.0/2258", enabled: true)
        let old = record("1.9/2201", enabled: false)

        let first = scan([new, old])
        let second = scan([old, new])

        XCTAssertEqual(first.count, 2, "precondition: both records reached the list")
        let enabledID = try XCTUnwrap(first.first(where: \.runAtLoad)).id
        XCTAssertEqual(try XCTUnwrap(second.first(where: \.runAtLoad)).id, enabledID, """
            the same record came back with a different id because the tool listed it \
            second: \(first.map(\.id)) then \(second.map(\.id)). An id that is a \
            record's position is what «Scan again» reshuffles, which is the defect \
            the sort's tie-break exists to close — and a selection keyed by path \
            follows the id onto the other row.
            """)
        XCTAssertEqual(Set(first.map(\.id)), Set(second.map(\.id)),
                       "and neither row invented an identity the other scan did not have")
    }

    /// What is left for the ordinal: two records the tool prints identically. They
    /// still need two ids — the `ForEach` is undefined otherwise — and which of the
    /// two is drawn first is a question about two rows nobody can tell apart.
    func testTwoRecordsTheToolPrintsIdenticallyStillGetTwoIds() {
        let items = scan([record("2.0/2258", enabled: true), record("2.0/2258", enabled: true)])

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(Set(items.map(\.id)).count, 2)
    }
}
