import HelmRuntime
import HelmUI
import XCTest
import Module_Leftovers_Engine
@testable import Module_Leftovers_UI

/// **Two rows say something now that neither used to say, and both are about a
/// control that is missing.**
///
/// A folder the scan never read draws a row whose only content is its own line: no
/// size, no checkbox, no menu about deleting it. A launch agent whose label another
/// file registers draws no «Turn off». In both cases something a person would
/// expect is absent, and an absence with no sentence beside it is the defect
/// `LeftoversEmpty.notEverythingChecked` was written for one screen out — «the
/// refusal is in the log, where the person reading the green tick is not».
///
/// Read in **all eight languages**, never in this machine's own: the suite runs in
/// whatever language this Mac is set to, and a bare assertion reads exactly one of
/// them (CLAUDE.md — and the machine this was written on is `.ru`, not English).
@MainActor
final class AControlThatIsNotThereSaysWhyTests: XCTestCase {

    private func sourceRow(_ status: ItemStatus, leadsTo: String? = nil) -> StaleItem {
        StaleItem(path: "/Users/x/Library/QuickLook", identifier: "QuickLook",
                  kind: .plugin, sizeBytes: 0, status: status, writable: false,
                  leadsTo: leadsTo)
    }

    private func agent(alsoClaimedBy other: String?) -> StaleItem {
        StaleItem(path: "/Users/x/Library/LaunchAgents/com.vendor.updater.plist",
                  identifier: "com.vendor.updater", kind: .launchAgent, sizeBytes: 4_096,
                  missingTarget: "/Library/Application Support/Vendor/updater",
                  labelAlsoClaimedBy: other)
    }

    /// The redirected folder names where it leads — the one fact the row cannot
    /// show anywhere else, since its name and its path are both the spelling the
    /// link does not honour.
    func testARedirectedSourceSaysWhereItLeadsInEveryLanguage() throws {
        let destination = "/Volumes/Elsewhere/QuickLook"
        for language in AppLanguage.allCases {
            let detail = try XCTUnwrap(
                LfStr.detail(for: sourceRow(.sourceRedirected, leadsTo: destination),
                             language: language))
            let clause = try XCTUnwrap(detail.clause, "\(language.rawValue) has no sentence")
            XCTAssertTrue(clause.contains(destination),
                          "\(language.rawValue) does not say where the link goes: \(clause)")
            XCTAssertEqual(detail.path, "/Users/x/Library/QuickLook",
                           "and the row still spells the folder the scan was told to read")
        }
    }

    /// The unopened folder says so, in Autopilot's own sentence for the same fact —
    /// one English key means one thing, and «Helm cannot read this folder» is
    /// already that thing.
    func testAnUnreadableSourceSaysSoInEveryLanguage() throws {
        for language in AppLanguage.allCases {
            let detail = try XCTUnwrap(LfStr.detail(for: sourceRow(.sourceUnreadable),
                                                    language: language))
            XCTAssertEqual(detail.clause, LfStr.folderUnreadable(language: language))
            XCTAssertFalse(try XCTUnwrap(detail.clause).isEmpty)
        }
        // Eight languages, and not one word repeated eight times: a table nobody
        // filled in reads as a pass here otherwise.
        let sentences = AppLanguage.allCases.map { LfStr.folderUnreadable(language: $0) }
        XCTAssertGreaterThan(Set(sentences).count, 6,
                             "\(Set(sentences).count) distinct sentences for eight languages")
    }

    /// **The row that has lost its switch names the file that took it.** Not a
    /// count: the question a person is left with is «then which of these am I
    /// looking at», and the pair point at each other.
    func testALabelTwoFilesClaimNamesTheOtherFileInEveryLanguage() throws {
        let other = "/Library/LaunchAgents/com.vendor.updater.plist"
        for language in AppLanguage.allCases {
            let detail = try XCTUnwrap(LfStr.detail(for: agent(alsoClaimedBy: other),
                                                    language: language))
            let clause = try XCTUnwrap(detail.clause)
            XCTAssertTrue(clause.contains(other),
                          "\(language.rawValue) does not name the other file: \(clause)")
        }
    }

    /// And it is the clause the row draws, over the one it would otherwise carry.
    ///
    /// Both facts are true of this row — it points at a missing file *and* another
    /// file wears its name — and there is one clause. The missing target explains
    /// the «Leftover» badge, which is already on screen; the shared label explains
    /// the switch that is not, which nothing else on the row can say.
    func testTheSharedLabelIsWhatTheOneClauseSays() throws {
        let alone = try XCTUnwrap(LfStr.detail(for: agent(alsoClaimedBy: nil), language: .en))
        XCTAssertEqual(alone.clause, LfStr.missingTarget(
            "/Library/Application Support/Vendor/updater", language: .en),
                       "precondition: on its own this row says what it points at")

        let shared = try XCTUnwrap(LfStr.detail(
            for: agent(alsoClaimedBy: "/Library/LaunchAgents/com.vendor.updater.plist"),
            language: .en))
        XCTAssertNotEqual(shared.clause, alone.clause)
    }

    /// The badge over a source row is the word the empty screen uses for the same
    /// rows: «Helm could not check N items» counts them, and a second word for one
    /// fact is how a badge and a sentence come to disagree.
    func testASourceRowWearsTheUncheckedBadge() {
        for status in [ItemStatus.sourceRedirected, .sourceUnreadable] {
            XCTAssertEqual(LeftoverBadges.on(sourceRow(status)), [.status(status)])
        }
    }
}
