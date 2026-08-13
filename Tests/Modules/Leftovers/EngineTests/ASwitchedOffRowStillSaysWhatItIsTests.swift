import XCTest
@testable import Module_Leftovers_Engine

/// What a row wears beside its name, and what two of those marks were claiming.
///
/// Measured in Russian on a leftover agent carrying `disabled: true` and
/// `runAtLoad: true`: the row drew «Выключено» and «При входе» and **no**
/// «Остаток». Two things were wrong in one line of the page. `if item.disabled`
/// *replaced* the status, so the one mark that says why the row is in this list —
/// and the one the colour of «Select all» is about — vanished for exactly the rows
/// somebody had already dealt with. And `runAtLoad` was appended regardless, in the
/// same orange the leftover pill wears: launchd's disabled list overrides the
/// plist's `RunAtLoad`, so the row asserted that a job switched off runs at the next
/// login. The two badges said opposite things about tomorrow.
///
/// Disabled is a qualifier, not a status: it takes the slot «At login» occupies,
/// and «At login» is what gives way, because it is the claim that is false.
final class ASwitchedOffRowStillSaysWhatItIsTests: XCTestCase {

    private func agent(_ name: String, status: ItemStatus = .orphaned,
                       runAtLoad: Bool = false, disabled: Bool = false) -> StaleItem {
        StaleItem(path: "\(NSHomeDirectory())/Library/LaunchAgents/\(name).plist",
                  identifier: name, kind: .launchAgent, sizeBytes: 4_096,
                  runAtLoad: runAtLoad, status: status, disabled: disabled)
    }

    /// The row the survey found: switched off, `RunAtLoad` still true in the file.
    func testASwitchedOffRowKeepsTheBadgeThatSaysWhyItIsInTheList() {
        let item = agent("com.vendor.updater", runAtLoad: true, disabled: true)

        XCTAssertEqual(LeftoverBadges.on(item), [.status(.orphaned), .disabled],
                       "the status badge was replaced by «Disabled», and «At login» was drawn "
                       + "beside it over a job launchd will not start")
    }

    /// And with nothing switched off, the qualifier is the one that is true.
    func testARunningRowSaysBothItsStatusAndThatItRunsAtLogin() {
        let item = agent("com.vendor.helper", runAtLoad: true)

        XCTAssertEqual(LeftoverBadges.on(item), [.status(.orphaned), .runsAtLogin])
    }

    /// The ordinary row: one mark, and it is the status.
    func testAnOrdinaryRowWearsItsStatusAlone() {
        XCTAssertEqual(LeftoverBadges.on(agent("com.vendor.quiet")), [.status(.orphaned)])
    }

    /// Switched off and not marked to run at login: still exactly two marks, and
    /// still the status first — the mark the eye reads down the list.
    func testTheStatusComesFirstWhicheverQualifierFollowsIt() {
        for item in [agent("a", status: .inUse, disabled: true),
                     agent("b", status: .unreadable, runAtLoad: true),
                     agent("c", status: .undetermined, runAtLoad: true, disabled: true)] {
            XCTAssertEqual(LeftoverBadges.on(item).first, .status(item.status),
                           "\(item.identifier) leads with something other than its status")
            XCTAssertLessThanOrEqual(LeftoverBadges.on(item).count, 2,
                                     "\(item.identifier) wears a third badge — the run measured "
                                     + "258 pt inside a 343 pt column at two")
        }
    }
}
