import Foundation
import XCTest
import HelmRuntime
import HelmTestSupport
@testable import Module_Autopilot_Engine

/// The watcher's window between planning a file and running the plan.
///
/// FSEvents on a folder swapped for a link into `~/Library` reports the target's
/// files. The watcher used to ask whether the file exists before it asked
/// whether a rule may reach it, so a file that vanished in that window came
/// back `.missing` — a record carrying the file's name and path, and a log line
/// with the leaf in clear, for a file the gate would have refused unseen. The
/// gate comes first now: a protected path is refused as out of scope whether or
/// not the file is still there, and that refusal names nothing.
final class AFileThatVanishesBehindAProtectedLinkIsNamedNowhereTests: XCTestCase {

    private var home: URL!
    private let secret = "passport-scan-2026.pdf"

    override func setUpWithError() throws {
        home = scratchDirectory("home")
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent("Library/Inbox"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent("Downloads"), withIntermediateDirectories: true)
    }

    private func plan(for name: String) -> RulePlan {
        let now = Date(timeIntervalSince1970: 1_784_116_800)
        return RulePlan(
            facts: FileFacts(name: name, kind: .document, bytes: 4,
                             added: now, modified: now, now: now),
            rule: Rule(id: "r", name: "Sort", enabled: true,
                       conditions: [.name(.contains, "")],
                       action: .move(to: home.appendingPathComponent("Sorted").path)))
    }

    /// The window made deterministic: the plan was made while the file was
    /// there, and by the time the runner looks it is gone.
    func testAProtectedPathThatIsGoneIsRefusedAsOutOfScopeNotAsMissing() {
        let path = home.appendingPathComponent("Library/Inbox/\(secret)").path
        let outcome = RuleRunner(home: home.path).run(plan(for: secret), at: path, key: nil)
        XCTAssertEqual(outcome, .refused(.outOfScope),
                       "the existence of a protected file was asked before the gate")
        let record = ActionRecord.of(plan(for: secret), outcome, run: "p")
        XCTAssertNotNil(record, "precondition: the refusal is recorded at all")
        XCTAssertEqual(record?.file, "", "a record named a protected file")
        XCTAssertEqual(record?.path, "", "a record carried a protected path")
    }

    /// Control: an ordinary file that vanished is still `.missing`, so the
    /// reorder did not turn every absence into a scope refusal.
    func testAnOrdinaryFileThatIsGoneIsStillMissing() {
        let path = home.appendingPathComponent("Downloads/gone.pdf").path
        XCTAssertEqual(RuleRunner(home: home.path).run(plan(for: "gone.pdf"), at: path, key: nil),
                       .refused(.missing))
    }
}
