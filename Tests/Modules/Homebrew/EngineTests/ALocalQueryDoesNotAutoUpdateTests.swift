import XCTest
@testable import Module_Homebrew_Engine

/// A query that reads the disk must not be allowed to change the machine.
///
/// `brew list --versions` answers about what is installed and `brew desc`
/// describes the names it is given; neither depends on a fresh catalogue. Left
/// to itself brew may refresh the catalogue first, so Refresh on the installed
/// list could wait on a download nobody asked for, or be refused offline.
///
/// **The rule is what the query may reach, not what it costs**: brew refreshes
/// periodically rather than per call, so the variable makes no timing
/// difference worth the name.
///
/// `outdated` and `search` are deliberately **not** in this test. They are
/// answers about the catalogue, and a stale catalogue makes «Updates: 0» a lie
/// about the machine. The gate is "does this query need the catalogue", not
/// "is this query slow".
final class ALocalQueryDoesNotAutoUpdateTests: XCTestCase {

    func testListAndDescribeRefuseTheAutoUpdate() {
        let runner = ScriptedRunner()
        _ = brewEngine(runner).listInstalled()
        XCTAssertFalse(runner.calls.isEmpty, "the query never ran")
        for call in runner.calls {
            XCTAssertEqual(call.env["HOMEBREW_NO_AUTO_UPDATE"], "1",
                           "\(call.args.first ?? "?") may refresh the catalogue it does not read")
        }
    }

    func testDescriptionsRefuseTheAutoUpdate() {
        let runner = ScriptedRunner()
        _ = brewEngine(runner).descriptions(names: ["wget"], isCask: false)
        XCTAssertEqual(runner.calls.first?.env["HOMEBREW_NO_AUTO_UPDATE"], "1")
    }

    /// The control: these two are about the catalogue, and without this half
    /// "set it everywhere" passes the test above.
    func testOutdatedAndSearchStillRefreshTheCatalogue() {
        let runner = ScriptedRunner()
        let e = brewEngine(runner)
        _ = e.outdated()
        _ = e.search("wget")
        XCTAssertFalse(runner.calls.isEmpty)
        for call in runner.calls {
            XCTAssertNil(call.env["HOMEBREW_NO_AUTO_UPDATE"],
                         "\(call.args.first ?? "?") would answer from a catalogue it refused to refresh")
        }
    }

    /// The console shows what the tool says, and brew's environment hints are
    /// several lines of advice about shells that have nothing to do with the
    /// install a person is watching.
    func testAnOperationSilencesTheEnvironmentHints() {
        let runner = ScriptedRunner()
        brewEngine(runner).install(name: "wget", isCask: false)
        XCTAssertEqual(runner.calls.first?.env["HOMEBREW_NO_ENV_HINTS"], "1")
    }
}
